#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/git/ops/BranchOps.h"
#include "core/git/ops/CheckoutOp.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

namespace {}  // namespace

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

GBM_API void gbm_branch_create(GbmSessionHandle session,
                               const char* name,
                               const char* startPoint,
                               int32_t checkoutAfter,
                               int32_t setUpstream,
                               const char* upstream) {
    CreateBranchRequest request;
    request.name = name != nullptr ? name : "";
    request.startPoint = startPoint != nullptr ? startPoint : "";
    request.checkoutAfter = checkoutAfter != 0;
    request.setUpstream = setUpstream != 0;
    request.upstream = upstream != nullptr ? upstream : "";

    toSession(session)->createBranch(std::move(request));
}

GBM_API void gbm_branch_rename(GbmSessionHandle session,
                               const char* from,
                               const char* to,
                               int32_t force,
                               int32_t renameRemote,
                               const char* remoteName) {
    RenameBranchRequest request;
    request.from = from != nullptr ? from : "";
    request.to = to != nullptr ? to : "";
    request.force = force != 0;
    request.renameRemote = renameRemote != 0;
    request.remoteName = remoteName != nullptr ? remoteName : "";

    toSession(session)->renameBranch(std::move(request));
}

GBM_API void gbm_branch_delete(GbmSessionHandle session,
                               const char* const* names,
                               int32_t nameCount,
                               int32_t force,
                               int32_t isRemote,
                               const char* remoteName) {
    DeleteBranchRequest request;
    for (std::string& name : toStringVector(names, nameCount)) {
        // No tip crosses this signature yet, so a forced entry is refused with
        // MissingBranchTip until the caller sends one.
        request.entries.push_back(force != 0 ? DeleteBranchEntry::forced(std::move(name), {})
                                             : DeleteBranchEntry::plain(std::move(name)));
    }
    request.isRemote = isRemote != 0;
    request.remoteName = remoteName != nullptr ? remoteName : "";

    toSession(session)->deleteBranch(std::move(request));
}
