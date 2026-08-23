#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/git/ops/ResetOps.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

namespace {}  // namespace

GBM_API void gbm_reset_to(GbmSessionHandle session, const char* target, int32_t mode) {
    ResetRequest request;
    request.target = target != nullptr ? target : "";
    request.mode = static_cast<ResetMode>(mode);
    toSession(session)->resetTo(std::move(request));
}

GBM_API void gbm_restore_paths(GbmSessionHandle session,
                               const char* const* paths,
                               int32_t pathCount,
                               int32_t staged,
                               const char* source) {
    RestoreRequest request;
    request.paths = toStringVector(paths, pathCount);
    request.staged = staged != 0;
    request.source = source != nullptr ? source : "";
    toSession(session)->restorePaths(std::move(request));
}

GBM_API void gbm_clean_preview(GbmSessionHandle session, int32_t includeIgnored) {
    toSession(session)->requestCleanPreview(includeIgnored != 0);
}

GBM_API void gbm_clean_untracked(GbmSessionHandle session,
                                 const char* const* paths,
                                 int32_t pathCount,
                                 int32_t includeIgnored) {
    CleanRequest request;
    request.paths = toStringVector(paths, pathCount);
    request.includeIgnored = includeIgnored != 0;
    toSession(session)->cleanUntracked(std::move(request));
}
