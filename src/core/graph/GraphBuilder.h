#pragma once

#include "core/base/ObjectId.h"
#include "core/graph/GraphSnapshot.h"
#include "core/graph/LaneAllocator.h"

#include <cstdint>
#include <memory>
#include <span>
#include <unordered_map>
#include <vector>

namespace gbm {

struct GraphOptions {
    /// Rows past this point are dropped and `truncated` is set. A 2M-commit walk
    /// is beyond any repository we target; the cap exists so a pathological or
    /// corrupt repository cannot exhaust memory.
    std::uint32_t maxRows = 2'000'000;
};

/// Builds a Fork-style commit graph incrementally, one row at a time, in the
/// order `git rev-list --topo-order` produces them.
///
/// Streaming is not an optimisation here, it is the design: rows become
/// paintable within milliseconds of the walk starting, so time-to-first-paint is
/// independent of how much history exists. `snapshot()` may be called at any
/// point to publish what has been built so far.
///
/// The layout obeys three invariants, in this order of precedence:
///   1. A first-parent chain occupies one unbroken column.
///   2. The trunk (whatever the walk was seeded with first) owns lane 0 forever.
///   3. Merged-in parents occupy columns strictly to the right, and rejoin with
///      a single bend.
class GraphBuilder {
public:
    explicit GraphBuilder(GraphOptions options = {});

    /// Feeds one commit. `parents` is in git's order, so parents[0] is the first
    /// parent — the ordering the straightness rule depends on.
    void add(const ObjectId& oid, std::span<const ObjectId> parents, std::uint32_t commitTime);

    /// Marks edges whose parents never arrived as boundary stubs. Idempotent, so
    /// it is safe to call on each streamed chunk and again at the end.
    void finish();

    /// Publishes an immutable copy of the current state. Building in chunks and
    /// building in one pass yield byte-identical snapshots, which the chunk
    /// invariance test pins down.
    GraphSnapshotPtr snapshot() const;

    std::size_t rowCount() const noexcept { return snapshot_.rows.size(); }

    bool truncated() const noexcept { return snapshot_.truncated; }

    /// Marks the snapshot as partial for a reason external to the row cap above
    /// -- e.g. the walk itself was capped with `--max-count`. Kept separate from
    /// the internal row-cap path so callers can flag "the query stopped early"
    /// without pretending it was this builder's own limit that did it.
    void markTruncated() noexcept { snapshot_.truncated = true; }

    /// Marks a row as carrying refs / being HEAD, for renderer decoration.
    void setRowFlags(RowId row, std::uint8_t flagsToSet);

private:
    /// An edge created for a child whose parent has not been emitted yet. Carries
    /// the patch sites to fill in once the parent's row number is known.
    struct PendingEdge {
        EdgeId edgeId = 0;
        std::uint32_t parentPoolIndex = 0;  ///< Slot in parentPool to patch.
        LaneId lane = 0;                    ///< Column this edge descends in.
        RowId childRow = 0;
        std::uint8_t color = 0;
        bool firstParent = false;
    };

    void patchIncoming(const std::vector<PendingEdge>& incoming, RowId row);
    LaneId chooseLane(const std::vector<PendingEdge>& incoming) const;
    EdgeId createEdge(
        RowId childRow, LaneId childLane, LaneId descendLane, std::uint8_t color, EdgeKind kind);

    GraphOptions options_;
    LaneAllocator lanes_;

    /// Parent oid -> edges waiting for it. Only ever holds the walk's frontier
    /// (the number of simultaneously open branches), so it stays small even for
    /// half a million commits.
    std::unordered_map<ObjectId, std::vector<PendingEdge>> pending_;

    /// Number of pending edges currently descending in each lane. A lane is only
    /// returned to the free list once this reaches zero, otherwise a still-open
    /// branch would have its column stolen by an unrelated commit.
    std::array<std::uint32_t, kMaxLanes> laneRefCount_{};

    GraphSnapshot snapshot_;
    bool finished_ = false;
};

}  // namespace gbm
