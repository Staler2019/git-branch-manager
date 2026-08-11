#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/git/ConflictMarkerParser.h"
#include "core/git/ops/ConflictOps.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_resolve_conflict(GbmSessionHandle session,
                                  const char* path,
                                  int32_t resolution,
                                  int32_t oursBlobMissing,
                                  int32_t theirsBlobMissing,
                                  const char* resolvedContent) {
    ResolveConflictRequest request;
    request.path = path != nullptr ? path : "";
    request.resolution = static_cast<ConflictResolution>(resolution);
    request.oursBlobMissing = oursBlobMissing != 0;
    request.theirsBlobMissing = theirsBlobMissing != 0;
    request.resolvedContent = resolvedContent != nullptr ? resolvedContent : "";
    toSession(session)->resolveConflict(std::move(request));
}

GBM_API void gbm_request_working_tree_content(GbmSessionHandle session, const char* path) {
    toSession(session)->requestWorkingTreeContent(path != nullptr ? path : "");
}

GBM_API int32_t gbm_parse_conflict_markers(const char* content) {
    const ParsedConflictFile parsed =
        ConflictMarkerParser{}.parse(content != nullptr ? content : "");
    setStagingBuffer(toJson(parsed));
    return 0;
}
