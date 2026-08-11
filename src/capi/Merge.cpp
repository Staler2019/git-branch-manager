#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/git/ops/MergeOps.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_merge_branch(GbmSessionHandle session,
                              const char* target,
                              int32_t mode,
                              const char* message,
                              int32_t stashFirst) {
    MergeRequest request;
    request.target = target != nullptr ? target : "";
    request.mode = static_cast<MergeMode>(mode);
    request.message = message != nullptr ? message : "";
    request.stashFirst = stashFirst != 0;
    toSession(session)->mergeBranch(std::move(request));
}

GBM_API void gbm_merge_abort(GbmSessionHandle session) {
    toSession(session)->abortMerge();
}
