#include "capi/Handle.h"
#include "capi/gbm_capi.h"
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
