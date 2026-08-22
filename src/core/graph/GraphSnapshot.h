#pragma once

#include "core/base/ObjectId.h"

#include <cstdint>
#include <memory>
#include <vector>

namespace gbm {

using RowId = std::uint32_t;
using LaneId = std::uint16_t;
using EdgeId = std::uint32_t;

/// Sentinel parent row for an edge whose parent lies outside the walk (a shallow
/// clone boundary, or a history limited by a filter). Drawn as a short stub.
constexpr RowId kRowBoundary = 0xFFFFFFFFu;

/// Rendered lane ceiling. A 10-year repository can easily have thousands of live
/// refs; without a cap the graph gutter grows to several hundred pixels and paint
/// time collapses. Edges beyond this collapse into a single overflow column, and
/// the UI says so rather than silently hiding them.
constexpr LaneId kMaxLanes = 48;

constexpr std::uint8_t kPaletteSize = 12;

enum class EdgeKind : std::uint8_t {
    FirstParent = 0,  ///< Continues a straight chain; inherits the child's lane.
    MergeParent = 1,  ///< Second parent of a two-parent merge.
    Octopus = 2,      ///< Third or later parent.
};

/// Per-row record. Exactly 16 bytes: at 500k commits every extra byte is another
/// half-megabyte resident, and the paint path walks this array linearly, so
/// keeping four rows per cache line matters more than convenience.
struct RowMeta {
    std::uint32_t parentOffset = 0;  ///< Index into GraphSnapshot::parentPool.
    std::uint32_t edgeOffset = 0;    ///< Index of the first edge starting at this row.
    std::uint32_t commitTime = 0;    ///< Unix seconds; u32 is valid past 2100.
    LaneId lane = 0;
    std::uint8_t color = 0;
    std::uint8_t flags = 0;

    enum Flags : std::uint8_t {
        FlagParentCountMask = 0x07,  ///< 0-6 parents; 7 means "7 or more".
        FlagIsMerge = 0x08,
        FlagHasRefs = 0x10,
        FlagIsHead = 0x20,
        FlagBoundary = 0x40,      ///< Parents exist but lie outside the walk.
        FlagLaneOverflow = 0x80,  ///< Lane exceeded kMaxLanes; drawn in the overflow gutter.
    };

    std::uint8_t parentCount() const noexcept { return flags & FlagParentCountMask; }

    bool isMerge() const noexcept { return (flags & FlagIsMerge) != 0; }

    bool isBoundary() const noexcept { return (flags & FlagBoundary) != 0; }

    bool isOverflow() const noexcept { return (flags & FlagLaneOverflow) != 0; }
};

static_assert(sizeof(RowMeta) == 16, "RowMeta must stay 16 bytes; see the memory budget");

/// A connection from a child row down to a parent row.
///
/// `lane` is the column the edge occupies while descending; `childLane` is where
/// it starts. When they differ the renderer draws a bend at the child row.
///
/// A second bend belongs at the *parent* row, and it is the renderer's job too:
/// `lane` is fixed when the edge is created and `GraphBuilder::patchIncoming()`
/// only fills in `parentRow`, so where several edges converge on one commit,
/// only the one `chooseLane()` picked shares that row's lane. Every other
/// arriving edge must bend from its own `lane` into `rows[parentRow].lane`, or
/// it renders as a line stopping beside the commit dot rather than touching it.
/// `GraphAsciiRenderer` does exactly that comparison; see also
/// app_flutter/lib/features/history_graph/widgets/graph_edge_geometry.dart.
///
/// There are deliberately no per-row pass-through records: reconstructing
/// straight segments at paint time via an interval query keeps memory at O(N+E)
/// rather than O(N x lanes).
struct Edge {
    RowId childRow = 0;
    RowId parentRow = kRowBoundary;
    LaneId lane = 0;
    LaneId childLane = 0;
    std::uint8_t color = 0;
    EdgeKind kind = EdgeKind::FirstParent;
    std::uint16_t reserved = 0;

    bool spans(RowId row) const noexcept {
        const RowId end = parentRow == kRowBoundary ? childRow + 1 : parentRow;
        return childRow <= row && row <= end;
    }
};

static_assert(sizeof(Edge) == 16, "Edge must stay 16 bytes; see the memory budget");

/// Immutable result of a graph build.
///
/// Published to the UI as shared_ptr<const GraphSnapshot>. The UI never locks and
/// never mutates: a newer snapshot simply replaces the pointer, and the old one
/// dies when the last frame that referenced it finishes painting.
class GraphSnapshot {
public:
    /// Row-parallel arrays.
    std::vector<ObjectId> oids;
    std::vector<RowMeta> rows;

    /// Parents in compressed-row form: row r's parents are
    /// parentPool[rows[r].parentOffset .. +rows[r].parentCount()].
    /// Values are row indices, or kRowBoundary when outside the walk.
    std::vector<RowId> parentPool;

    /// Sorted by childRow. Edges starting at row r begin at rows[r].edgeOffset.
    std::vector<Edge> edges;

    LaneId laneCount = 0;
    bool complete = false;              ///< False while the walk is still streaming.
    bool truncated = false;             ///< Hit the row cap; history shown is partial.
    std::uint32_t overflowedEdges = 0;  ///< Edges collapsed into the overflow gutter.

    std::size_t rowCount() const noexcept { return rows.size(); }

    /// Row index for an object id, found by binary search. Backed by a sorted
    /// row-index array rebuilt during finalisation; used for "select this
    /// commit" and ref decoration.
    bool findRow(const ObjectId& oid, RowId* out) const;

    /// Exact parent count, including octopus merges with more than 7 parents.
    /// RowMeta::parentCount() saturates at 7 to fit the flag byte, so the real
    /// count comes from the gap between consecutive parentOffsets — which is
    /// valid because the pool is filled strictly in row order.
    std::uint32_t parentCountOf(RowId row) const;

    std::vector<RowId> parentsOf(RowId row) const;

    /// Every edge overlapping rows [firstRow, lastRow]. This is the paint-path
    /// query, and it must stay proportional to the viewport rather than to
    /// history size, which is what the bucket index below provides.
    void edgesInRange(RowId firstRow, RowId lastRow, std::vector<const Edge*>& out) const;

    /// Widest lane in use across a row range, so the gutter can shrink when
    /// ancient history is linear instead of being sized for the busiest era.
    LaneId maxLaneInRange(RowId firstRow, RowId lastRow) const;

    /// Approximate resident size, for the memory budget assertions in tests.
    std::size_t approximateBytes() const;

    /// Builds the derived indices. Called once by GraphBuilder after the final
    /// row; also called on each streamed chunk so a partial snapshot is usable.
    void finalizeIndices();

private:
    static constexpr std::uint32_t kBucketRows = 64;

    /// For bucket k, the smallest edge index whose parentRow >= k * kBucketRows.
    /// Scanning forward from there yields every still-open edge without touching
    /// the earlier history.
    std::vector<std::uint32_t> edgeBucket_;

    /// Widest lane per bucket, for maxLaneInRange.
    std::vector<LaneId> bucketMaxLane_;

    /// Row indices sorted by oids[row], rebuilt by finalizeIndices(). findRow()
    /// binary searches this rather than hashing, which is both smaller (4 bytes
    /// per row vs. a hash-map node) and cheaper to rebuild on every streamed
    /// chunk (no per-entry allocation).
    ///
    /// Every entry is a row index into `oids`, valid only as long as `oids`
    /// isn't shrunk or reordered out from under it. Unlike the old hash map
    /// (which stored oids by value and needed no such assumption), this index
    /// is safe today only because GraphBuilder never does either -- rows are
    /// exclusively appended (see GraphBuilder.cpp) and finalizeIndices() fully
    /// rebuilds oidOrder_ from oids on every call. A future change that
    /// shrinks or reorders `oids` without also rebuilding oidOrder_ first
    /// would silently invalidate it.
    std::vector<RowId> oidOrder_;
};

using GraphSnapshotPtr = std::shared_ptr<const GraphSnapshot>;

}  // namespace gbm
