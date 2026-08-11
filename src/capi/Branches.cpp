#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/git/ops/CheckoutOp.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_branch_checkout(GbmSessionHandle session,
                                 const char* target,
                                 int32_t detach,
                                 int32_t createBranch,
                                 const char* newBranchName,
                                 int32_t force,
                                 int32_t stashFirst,
                                 int32_t recurseSubmodules) {
    CheckoutRequest request;
    request.target = target != nullptr ? target : "";
    request.detach = detach != 0;
    request.createBranch = createBranch != 0;
    request.newBranchName = newBranchName != nullptr ? newBranchName : "";
    request.force = force != 0;
    request.stashFirst = stashFirst != 0;
    request.recurseSubmodules = recurseSubmodules != 0;

    toSession(session)->checkout(std::move(request));
}
