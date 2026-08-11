#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/graph/GraphSnapshot.h"

using namespace gbm;
using namespace gbm::capi;

namespace {

/// static_assert-checked at compile time via GraphSnapshot.h's own asserts
/// (RowMeta/Edge == 16 bytes, ObjectId == 33 bytes); no separate check
/// needed here since we reinterpret_cast their arrays directly rather than
/// re-declaring the layout.

}  // namespace

GBM_API const uint8_t* gbm_graph_snapshot_rows(GbmSessionHandle session,
                                               int32_t* rowCount,
                                               int32_t* rowStride) {
    GraphSnapshotPtr snapshot = toSession(session)->exportGraph();
    if (!snapshot) {
        if (rowCount != nullptr) *rowCount = 0;
        if (rowStride != nullptr) *rowStride = static_cast<int32_t>(sizeof(RowMeta));
        return nullptr;
    }
    if (rowCount != nullptr) *rowCount = static_cast<int32_t>(snapshot->rows.size());
    if (rowStride != nullptr) *rowStride = static_cast<int32_t>(sizeof(RowMeta));
    return reinterpret_cast<const uint8_t*>(snapshot->rows.data());
}

GBM_API const uint8_t* gbm_graph_snapshot_oids(GbmSessionHandle session,
                                               int32_t* oidCount,
                                               int32_t* oidStride) {
    GraphSnapshotPtr snapshot = toSession(session)->exportGraph();
    if (!snapshot) {
        if (oidCount != nullptr) *oidCount = 0;
        if (oidStride != nullptr) *oidStride = static_cast<int32_t>(sizeof(ObjectId));
        return nullptr;
    }
    if (oidCount != nullptr) *oidCount = static_cast<int32_t>(snapshot->oids.size());
    if (oidStride != nullptr) *oidStride = static_cast<int32_t>(sizeof(ObjectId));
    return reinterpret_cast<const uint8_t*>(snapshot->oids.data());
}

GBM_API const uint32_t* gbm_graph_snapshot_parents(GbmSessionHandle session, int32_t* parentCount) {
    GraphSnapshotPtr snapshot = toSession(session)->exportGraph();
    if (!snapshot) {
        if (parentCount != nullptr) *parentCount = 0;
        return nullptr;
    }
    if (parentCount != nullptr) *parentCount = static_cast<int32_t>(snapshot->parentPool.size());
    static_assert(sizeof(RowId) == sizeof(uint32_t),
                  "RowId must stay uint32_t-sized for the FFI view");
    return reinterpret_cast<const uint32_t*>(snapshot->parentPool.data());
}

GBM_API const uint8_t* gbm_graph_snapshot_edges(GbmSessionHandle session,
                                                int32_t* edgeCount,
                                                int32_t* edgeStride) {
    GraphSnapshotPtr snapshot = toSession(session)->exportGraph();
    if (!snapshot) {
        if (edgeCount != nullptr) *edgeCount = 0;
        if (edgeStride != nullptr) *edgeStride = static_cast<int32_t>(sizeof(Edge));
        return nullptr;
    }
    if (edgeCount != nullptr) *edgeCount = static_cast<int32_t>(snapshot->edges.size());
    if (edgeStride != nullptr) *edgeStride = static_cast<int32_t>(sizeof(Edge));
    return reinterpret_cast<const uint8_t*>(snapshot->edges.data());
}

GBM_API int32_t gbm_graph_snapshot_lane_count(GbmSessionHandle session) {
    GraphSnapshotPtr snapshot = toSession(session)->currentGraph();
    return snapshot ? static_cast<int32_t>(snapshot->laneCount) : 0;
}

GBM_API int32_t gbm_graph_snapshot_complete(GbmSessionHandle session) {
    GraphSnapshotPtr snapshot = toSession(session)->currentGraph();
    return snapshot && snapshot->complete ? 1 : 0;
}

GBM_API int32_t gbm_graph_snapshot_truncated(GbmSessionHandle session) {
    GraphSnapshotPtr snapshot = toSession(session)->currentGraph();
    return snapshot && snapshot->truncated ? 1 : 0;
}

GBM_API void gbm_graph_snapshot_release(GbmSessionHandle session) {
    toSession(session)->releaseExportedGraph();
}
