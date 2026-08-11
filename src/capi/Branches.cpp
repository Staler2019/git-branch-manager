#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/git/ops/BranchOps.h"
#include "core/git/ops/CheckoutOp.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

namespace {

std::vector<std::string> toStringVector(const char* const* items, int32_t count) {
    std::vector<std::string> out;
    out.reserve(static_cast<std::size_t>(count > 0 ? count : 0));
    for (int32_t i = 0; i < count; ++i) {
        if (items[i] != nullptr) {
            out.emplace_back(items[i]);
        }
    }
    return out;
}

}  // namespace

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
                               int32_t force) {
    RenameBranchRequest request;
    request.from = from != nullptr ? from : "";
    request.to = to != nullptr ? to : "";
    request.force = force != 0;

    toSession(session)->renameBranch(std::move(request));
}

GBM_API void gbm_branch_delete(GbmSessionHandle session,
                               const char* const* names,
                               int32_t nameCount,
                               int32_t force,
                               int32_t isRemote,
                               const char* remoteName) {
    DeleteBranchRequest request;
    request.names = toStringVector(names, nameCount);
    request.force = force != 0;
    request.isRemote = isRemote != 0;
    request.remoteName = remoteName != nullptr ? remoteName : "";

    toSession(session)->deleteBranch(std::move(request));
}
