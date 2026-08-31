#include "core/graph/GraphBuilder.h"

#include <algorithm>
#include <utility>

namespace gbm {

GraphBuilder::GraphBuilder(GraphOptions options) : options_(options) {
    snapshot_.rows.reserve(4096);
    snapshot_.oids.reserve(4096);
    snapshot_.edges.reserve(4096);
    snapshot_.parentPool.reserve(4096);

    // Invariant 2: HEAD's branch owns lane 0. Held from before the first row,
    // because the row that would otherwise take it is emitted first -- git
    // orders by timestamp, and HEAD's tip is not always the newest commit.
    if (!options_.trunkTip.isNull()) {
        lanes_.reserve(0);
    }
}

EdgeId GraphBuilder::createEdge(
    RowId childRow, LaneId childLane, LaneId descendLane, std::uint8_t color, EdgeKind kind) {
    const auto id = static_cast<EdgeId>(snapshot_.edges.size());
    Edge edge;
    edge.childRow = childRow;
    edge.parentRow = kRowBoundary;  // Patched when the parent is emitted.
    edge.lane = descendLane;
    edge.childLane = childLane;
    edge.color = color;
    edge.kind = kind;
    snapshot_.edges.push_back(edge);

    if (LaneAllocator::isOverflow(descendLane)) {
        ++snapshot_.overflowedEdges;
    }
    return id;
}

LaneId GraphBuilder::chooseLane(const std::vector<PendingEdge>& incoming) const {
    // *** The straightness rule. ***
    //
    // Prefer an incoming first-parent edge; among equals prefer the lowest lane.
    // Because every commit offers its first parent the very same lane it occupies
    // itself, and this rule only ever rejects a first-parent edge in favour of
    // another first-parent edge further left, a first-parent chain can only move
    // *left*, and only where it merges into an older chain. It never moves right
    // and never oscillates -- so a chain that starts in lane 0 stays in lane 0
    // for the whole of history, which is the straight trunk Fork shows.
    const PendingEdge* best = nullptr;
    for (const PendingEdge& candidate : incoming) {
        if (best == nullptr) {
            best = &candidate;
            continue;
        }
        const int candidateRank = candidate.firstParent ? 0 : 1;
        const int bestRank = best->firstParent ? 0 : 1;
        if (candidateRank < bestRank ||
            (candidateRank == bestRank && candidate.lane < best->lane)) {
            best = &candidate;
        }
    }
    return best != nullptr ? best->lane : LaneId{0};
}

void GraphBuilder::patchIncoming(const std::vector<PendingEdge>& incoming, RowId row) {
    for (const PendingEdge& edge : incoming) {
        snapshot_.edges[edge.edgeId].parentRow = row;
        if (edge.parentPoolIndex < snapshot_.parentPool.size()) {
            snapshot_.parentPool[edge.parentPoolIndex] = row;
        }
        if (!LaneAllocator::isOverflow(edge.lane) && laneRefCount_[edge.lane] > 0) {
            --laneRefCount_[edge.lane];
        }
    }
}

void GraphBuilder::add(const ObjectId& oid,
                       std::span<const ObjectId> parents,
                       std::uint32_t commitTime) {
    if (snapshot_.rows.size() >= options_.maxRows) {
        snapshot_.truncated = true;
        return;
    }

    const auto row = static_cast<RowId>(snapshot_.rows.size());

    // --- 1. Which lane does this commit occupy? ----------------------------
    std::vector<PendingEdge> incoming;
    if (auto it = pending_.find(oid); it != pending_.end()) {
        incoming = std::move(it->second);
        pending_.erase(it);
    }

    LaneId lane = 0;
    std::uint8_t color = 0;

    // Invariant 2, and it has to come before both branches below.
    //
    // The reservation made in the constructor keeps every other row out of lane
    // 0; this is where it is redeemed. It applies on the `incoming`-non-empty
    // path too, and that half is the one worth stating: when HEAD's tip is also
    // the first parent of a row already emitted, an edge is descending towards
    // it in some other column, and `chooseLane()`'s straightness rule would keep
    // it there -- leaving the reservation unclaimed and lane 0 blank for the
    // *whole* graph rather than only for the rows above HEAD. Forcing lane 0
    // instead is consistent with that rule rather than an exception to it: it
    // only ever moves a first-parent chain further left, which is exactly what
    // chooseLane() already permits, and the bend it produces is spec's own
    // 「分岔與合併…接進 lane 0」.
    const bool isTrunkTip = !options_.trunkTip.isNull() && oid == options_.trunkTip;

    if (isTrunkTip) {
        lane = 0;
        lanes_.seed(lane, oid);
        color = lanes_.colorOf(lane);
    } else if (incoming.empty()) {
        // A ref tip, or a root reached before any of its children.
        lane = lanes_.allocateLeftmost();
        lanes_.seed(lane, oid);
        color = lanes_.colorOf(lane);
    } else {
        lane = chooseLane(incoming);
        color = lanes_.colorOf(lane);
    }

    if (!incoming.empty()) {
        patchIncoming(incoming, row);

        // Every other incoming lane bends into `lane` here. If nothing else is
        // still descending in it, that column has ended and can be reused.
        //
        // This runs for the trunk-tip path too, and must: those edges bend into
        // lane 0 like any others, and skipping the release would strand their
        // columns as occupied for the rest of the walk.
        for (const PendingEdge& edge : incoming) {
            if (edge.lane != lane && !LaneAllocator::isOverflow(edge.lane) &&
                laneRefCount_[edge.lane] == 0) {
                lanes_.release(edge.lane);
            }
        }
    }

    RowMeta meta;
    meta.lane = lane;
    meta.color = color;
    meta.commitTime = commitTime;
    meta.parentOffset = static_cast<std::uint32_t>(snapshot_.parentPool.size());
    meta.edgeOffset = static_cast<std::uint32_t>(snapshot_.edges.size());
    meta.flags = static_cast<std::uint8_t>(std::min<std::size_t>(parents.size(), 7));
    if (parents.size() > 1) {
        meta.flags |= RowMeta::FlagIsMerge;
    }
    if (LaneAllocator::isOverflow(lane)) {
        meta.flags |= RowMeta::FlagLaneOverflow;
    }

    snapshot_.oids.push_back(oid);
    snapshot_.rows.push_back(meta);

    // Parent row numbers are unknown until the parents are emitted, so reserve
    // the slots now and patch them later. Reserving in row order keeps the pool
    // contiguous, which is what lets parentCountOf() recover the exact parent
    // count from consecutive offsets even for a large octopus merge.
    for (std::size_t i = 0; i < parents.size(); ++i) {
        snapshot_.parentPool.push_back(kRowBoundary);
    }

    if (parents.empty()) {
        // A root commit ends its column.
        if (!LaneAllocator::isOverflow(lane) && laneRefCount_[lane] == 0) {
            lanes_.release(lane);
        }
        snapshot_.laneCount = lanes_.highWater();
        return;
    }

    // --- 2a. The first parent inherits this lane and colour. ----------------
    // This single line is what makes chains straight.
    {
        const EdgeId id = createEdge(row, lane, lane, color, EdgeKind::FirstParent);
        PendingEdge pendingEdge;
        pendingEdge.edgeId = id;
        pendingEdge.parentPoolIndex = meta.parentOffset;
        pendingEdge.lane = lane;
        pendingEdge.childRow = row;
        pendingEdge.color = color;
        pendingEdge.firstParent = true;
        pending_[parents[0]].push_back(pendingEdge);
        if (!LaneAllocator::isOverflow(lane)) {
            ++laneRefCount_[lane];
        }
    }

    // --- 2b. Parents 2..n branch out strictly to the right. -----------------
    for (std::size_t i = 1; i < parents.size(); ++i) {
        const ObjectId& parent = parents[i];
        const EdgeKind kind = parents.size() > 2 ? EdgeKind::Octopus : EdgeKind::MergeParent;

        LaneId targetLane;
        std::uint8_t targetColor;

        auto existing = pending_.find(parent);
        if (existing != pending_.end() && !existing->second.empty()) {
            // This parent already has a column reserved by another child. Route
            // into it instead of allocating a second column for the same commit,
            // which would render as two parallel lines that merge for no reason.
            targetLane = existing->second.front().lane;
            for (const PendingEdge& candidate : existing->second) {
                targetLane = std::min(targetLane, candidate.lane);
            }
            targetColor = lanes_.colorOf(targetLane);
        } else {
            targetLane = lanes_.allocateAfter(lane);
            lanes_.seed(targetLane, parent);
            targetColor = lanes_.colorOf(targetLane);
        }

        const EdgeId id = createEdge(row, lane, targetLane, targetColor, kind);
        PendingEdge pendingEdge;
        pendingEdge.edgeId = id;
        pendingEdge.parentPoolIndex = static_cast<std::uint32_t>(meta.parentOffset + i);
        pendingEdge.lane = targetLane;
        pendingEdge.childRow = row;
        pendingEdge.color = targetColor;
        pendingEdge.firstParent = false;
        pending_[parent].push_back(pendingEdge);
        if (!LaneAllocator::isOverflow(targetLane)) {
            ++laneRefCount_[targetLane];
        }
    }

    snapshot_.laneCount = lanes_.highWater();
}

void GraphBuilder::setRowFlags(RowId row, std::uint8_t flagsToSet) {
    if (row < snapshot_.rows.size()) {
        snapshot_.rows[row].flags |= flagsToSet;
    }
}

void GraphBuilder::finish() {
    // Anything still pending has a parent outside the walk: a shallow clone
    // boundary, or history excluded by a filter. Those edges become short stubs
    // and the child row is flagged, so the UI can say "history continues here"
    // rather than implying the commit is a root.
    for (const auto& [parentOid, edges] : pending_) {
        (void)parentOid;
        for (const PendingEdge& edge : edges) {
            snapshot_.edges[edge.edgeId].parentRow = kRowBoundary;
            if (edge.childRow < snapshot_.rows.size()) {
                snapshot_.rows[edge.childRow].flags |= RowMeta::FlagBoundary;
            }
        }
    }
    snapshot_.complete = true;
    snapshot_.laneCount = lanes_.highWater();
    finished_ = true;
}

GraphSnapshotPtr GraphBuilder::snapshot() const {
    // A copy, so the published snapshot can never be mutated by continued
    // building. This is the only allocation-heavy step, and it happens once per
    // streamed chunk rather than per row.
    auto copy = std::make_shared<GraphSnapshot>(snapshot_);
    copy->complete = finished_;

    if (!finished_) {
        // Mid-stream, edges to not-yet-emitted parents must render as open ends
        // rather than pointing at row 0.
        for (const auto& [parentOid, edges] : pending_) {
            (void)parentOid;
            for (const PendingEdge& edge : edges) {
                copy->edges[edge.edgeId].parentRow = kRowBoundary;
            }
        }
    }

    copy->finalizeIndices();
    return copy;
}

}  // namespace gbm
