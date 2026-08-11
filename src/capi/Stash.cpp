#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/base/Error.h"
#include "core/git/ops/StashOps.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_stash_refresh(GbmSessionHandle session) {
    toSession(session)->refreshStashes();
}

GBM_API int32_t gbm_stashes_json(GbmSessionHandle session) {
    const StashListPtr stashes = toSession(session)->currentStashes();
    if (!stashes) {
        setStagingBuffer(toJson(GitError(GitError::Code::NotFound, "no stash list published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*stashes));
    return 0;
}

GBM_API void gbm_stash_save(GbmSessionHandle session,
                            const char* message,
                            int32_t includeUntracked,
                            int32_t keepIndex,
                            const char* const* paths,
                            int32_t pathCount) {
    StashSaveRequest request;
    request.message = message != nullptr ? message : "";
    request.includeUntracked = includeUntracked != 0;
    request.keepIndex = keepIndex != 0;
    request.paths.reserve(static_cast<std::size_t>(pathCount > 0 ? pathCount : 0));
    for (int32_t i = 0; i < pathCount; ++i) {
        if (paths[i] != nullptr) {
            request.paths.emplace_back(paths[i]);
        }
    }
    toSession(session)->saveStash(std::move(request));
}

GBM_API void gbm_stash_apply(GbmSessionHandle session, int32_t index, int32_t pop) {
    StashApplyRequest request;
    request.index = index;
    request.pop = pop != 0;
    toSession(session)->applyStash(request);
}

GBM_API void gbm_stash_drop(GbmSessionHandle session, int32_t index) {
    StashDropRequest request;
    request.index = index;
    toSession(session)->dropStash(request);
}

GBM_API void gbm_stash_branch(GbmSessionHandle session, int32_t index, const char* branchName) {
    StashBranchRequest request;
    request.index = index;
    request.branchName = branchName != nullptr ? branchName : "";
    toSession(session)->branchFromStash(std::move(request));
}

GBM_API void gbm_stash_request_diff(GbmSessionHandle session, int32_t index) {
    toSession(session)->requestStashDiff(index);
}
