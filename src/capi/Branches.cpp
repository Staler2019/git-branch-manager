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
                               const int32_t* forces,
                               const char* const* expectedTips,
                               int32_t isRemote,
                               const char* remoteName) {
    DeleteBranchRequest request;
    std::vector<std::string> list = toStringVector(names, nameCount);
    for (std::size_t i = 0; i < list.size(); ++i) {
        if (forces == nullptr || forces[i] == 0) {
            request.entries.push_back(DeleteBranchEntry::plain(std::move(list[i])));
            continue;
        }
        // A missing tip stays empty, and core refuses it (MissingBranchTip).
        const char* tip = expectedTips != nullptr ? expectedTips[i] : nullptr;
        request.entries.push_back(
            DeleteBranchEntry::forced(std::move(list[i]), tip != nullptr ? tip : ""));
    }
    request.isRemote = isRemote != 0;
    request.remoteName = remoteName != nullptr ? remoteName : "";

    toSession(session)->deleteBranch(std::move(request));
}

GBM_API void gbm_request_branch_deletion_probe(GbmSessionHandle session,
                                               uint64_t requestId,
                                               const char* const* names,
                                               int32_t nameCount) {
    toSession(session)->requestBranchDeletionProbe(requestId, toStringVector(names, nameCount));
}
