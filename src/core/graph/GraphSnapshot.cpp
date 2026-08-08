#include "core/graph/GraphSnapshot.h"

#include <algorithm>

namespace gbm {

bool GraphSnapshot::findRow(const ObjectId& oid, RowId* out) const {
    const auto it = std::lower_bound(
        oidOrder_.begin(), oidOrder_.end(), oid, [this](RowId row, const ObjectId& key) {
            return oids[row] < key;
        });
    if (it == oidOrder_.end() || !(oids[*it] == oid)) {
        return false;
    }
    if (out != nullptr) {
        *out = *it;
    }
    return true;
}

std::uint32_t GraphSnapshot::parentCountOf(RowId row) const {
    if (row >= rows.size()) {
        return 0;
    }
    const std::uint32_t begin = rows[row].parentOffset;
    const std::uint32_t end = (row + 1 < rows.size())
                                  ? rows[row + 1].parentOffset
                                  : static_cast<std::uint32_t>(parentPool.size());
    return end > begin ? end - begin : 0;
}

std::vector<RowId> GraphSnapshot::parentsOf(RowId row) const {
    std::vector<RowId> result;
    if (row >= rows.size()) {
        return result;
    }
    const std::uint32_t offset = rows[row].parentOffset;
    const std::uint32_t count = parentCountOf(row);
    result.reserve(count);
    for (std::uint32_t i = 0; i < count; ++i) {
        const std::size_t index = offset + i;
        if (index < parentPool.size()) {
            result.push_back(parentPool[index]);
        }
    }
    return result;
}

void GraphSnapshot::finalizeIndices() {
    // Every call rebuilds from scratch rather than reusing a previous
    // oidOrder_: GraphBuilder::snapshot() (see GraphBuilder.cpp) publishes each
    // streamed chunk as a fresh copy of the builder's running snapshot and
    // calls finalizeIndices() on that copy, never on the builder's own state,
    // so there is no prior sorted state in `copy` to merge with -- an
    // incremental sort would just be a from-scratch sort with extra steps.
    oidOrder_.resize(oids.size());
    for (RowId row = 0; row < oids.size(); ++row) {
        oidOrder_[row] = row;
    }
    // stable_sort, not sort: git commits never produce duplicate ObjectIds in
    // practice, but the old unordered_map this replaced resolved a duplicate
    // deterministically (first insert wins). Keeping that same first-row-wins
    // tie-break costs nothing measurable at this size and avoids leaving
    // findRow()'s result for a duplicate oid unspecified.
    std::stable_sort(
        oidOrder_.begin(), oidOrder_.end(), [this](RowId a, RowId b) { return oids[a] < oids[b]; });

    // Bucket k records the first edge that could still be open at row
    // k * kBucketRows. Because `edges` is sorted by childRow and an edge always
    // ends below where it starts, a forward scan from that index sees every edge
    // overlapping the bucket without ever scanning from row 0.
    const std::size_t bucketCount = rows.empty() ? 1 : (rows.size() / kBucketRows) + 1;
    edgeBucket_.assign(bucketCount, 0);
    bucketMaxLane_.assign(bucketCount, 0);

    std::size_t edgeIndex = 0;
    for (std::size_t bucket = 0; bucket < bucketCount; ++bucket) {
        const RowId bucketStart = static_cast<RowId>(bucket * kBucketRows);

        // Advance past edges that have already closed above this bucket.
        while (edgeIndex < edges.size()) {
            const Edge& edge = edges[edgeIndex];
            const RowId end = edge.parentRow == kRowBoundary ? edge.childRow + 1 : edge.parentRow;
            if (end >= bucketStart) {
                break;
            }
            ++edgeIndex;
        }
        edgeBucket_[bucket] = static_cast<std::uint32_t>(edgeIndex);

        const RowId bucketEnd =
            std::min<RowId>(bucketStart + kBucketRows, static_cast<RowId>(rows.size()));
        LaneId widest = 0;
        for (RowId row = bucketStart; row < bucketEnd; ++row) {
            widest = std::max(widest, rows[row].lane);
        }
        bucketMaxLane_[bucket] = widest;
    }
}

void GraphSnapshot::edgesInRange(RowId firstRow,
                                 RowId lastRow,
                                 std::vector<const Edge*>& out) const {
    out.clear();
    if (edges.empty() || rows.empty() || firstRow > lastRow) {
        return;
    }

    const std::size_t bucket = std::min<std::size_t>(
        firstRow / kBucketRows, edgeBucket_.empty() ? 0 : edgeBucket_.size() - 1);
    std::size_t index = edgeBucket_.empty() ? 0 : edgeBucket_[bucket];

    for (; index < edges.size(); ++index) {
        const Edge& edge = edges[index];
        if (edge.childRow > lastRow) {
            break;  // Sorted by childRow, so nothing later can overlap.
        }
        const RowId end = edge.parentRow == kRowBoundary ? edge.childRow + 1 : edge.parentRow;
        if (end >= firstRow) {
            out.push_back(&edge);
        }
    }
}

LaneId GraphSnapshot::maxLaneInRange(RowId firstRow, RowId lastRow) const {
    if (rows.empty()) {
        return 0;
    }
    lastRow = std::min<RowId>(lastRow, static_cast<RowId>(rows.size()) - 1);
    if (firstRow > lastRow) {
        return 0;
    }

    LaneId widest = 0;
    const std::size_t firstBucket = firstRow / kBucketRows;
    const std::size_t lastBucket = lastRow / kBucketRows;

    // Whole buckets come from the precomputed maxima; only the two partial
    // buckets at the ends are scanned row by row.
    for (std::size_t bucket = firstBucket; bucket <= lastBucket && bucket < bucketMaxLane_.size();
         ++bucket) {
        const RowId bucketStart = static_cast<RowId>(bucket * kBucketRows);
        const RowId bucketEnd = bucketStart + kBucketRows - 1;
        if (bucketStart >= firstRow && bucketEnd <= lastRow) {
            widest = std::max(widest, bucketMaxLane_[bucket]);
            continue;
        }
        const RowId scanFrom = std::max(bucketStart, firstRow);
        const RowId scanTo = std::min(bucketEnd, lastRow);
        for (RowId row = scanFrom; row <= scanTo && row < rows.size(); ++row) {
            widest = std::max(widest, rows[row].lane);
        }
    }

    // An edge can occupy a lane to the right of any node in the range.
    std::vector<const Edge*> spanning;
    edgesInRange(firstRow, lastRow, spanning);
    for (const Edge* edge : spanning) {
        widest = std::max({widest, edge->lane, edge->childLane});
    }
    return widest;
}

std::size_t GraphSnapshot::approximateBytes() const {
    std::size_t total = 0;
    total += oids.capacity() * sizeof(ObjectId);
    total += rows.capacity() * sizeof(RowMeta);
    total += parentPool.capacity() * sizeof(RowId);
    total += edges.capacity() * sizeof(Edge);
    total += edgeBucket_.capacity() * sizeof(std::uint32_t);
    total += bucketMaxLane_.capacity() * sizeof(LaneId);
    // Exact, unlike the hash-map estimate this replaced: a vector's capacity()
    // is the real allocation, with no per-node allocator overhead to guess at.
    total += oidOrder_.capacity() * sizeof(RowId);
    return total;
}

}  // namespace gbm
