#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/base/Error.h"
#include "core/base/FsUtil.h"
#include "core/git/ops/WorktreeOps.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_worktree_refresh(GbmSessionHandle session) try {
    toSession(session)->refreshWorktrees();
} catch (...) {
    reportCurrentException(__func__);
}

GBM_API void gbm_worktree_request_pending_counts(GbmSessionHandle session) try {
    toSession(session)->requestWorktreePendingCounts();
} catch (...) {
    reportCurrentException(__func__);
}

GBM_API int32_t gbm_worktrees_json(GbmSessionHandle session) try {
    const WorktreeListPtr worktrees = toSession(session)->currentWorktrees();
    if (!worktrees) {
        setStagingBuffer(
            toJson(GitError(GitError::Code::NotFound, "no worktree list published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*worktrees));
    return 0;
} catch (...) {
    reportNativeException(__func__);
    return -1;
}

GBM_API void gbm_worktree_add(GbmSessionHandle session,
                              const char* path,
                              const char* branch,
                              int32_t createBranch,
                              const char* newBranchName,
                              int32_t detach,
                              int32_t force,
                              int32_t track) try {
    AddWorktreeRequest request;
    request.path = fsutil::pathFromUtf8(path != nullptr ? path : "");
    request.branch = branch != nullptr ? branch : "";
    request.createBranch = createBranch != 0;
    request.newBranchName = newBranchName != nullptr ? newBranchName : "";
    request.detach = detach != 0;
    request.force = force != 0;
    request.track = track != 0;
    toSession(session)->addWorktree(std::move(request));
} catch (...) {
    reportCurrentException(__func__);
}

GBM_API void gbm_worktree_remove(GbmSessionHandle session, const char* path, int32_t force) try {
    RemoveWorktreeRequest request;
    request.path = fsutil::pathFromUtf8(path != nullptr ? path : "");
    request.force = force != 0;
    toSession(session)->removeWorktree(request);
} catch (...) {
    reportCurrentException(__func__);
}

GBM_API void gbm_worktree_prune(GbmSessionHandle session) try {
    toSession(session)->pruneWorktrees();
} catch (...) {
    reportCurrentException(__func__);
}

GBM_API void gbm_worktree_lock(GbmSessionHandle session, const char* path, const char* reason) try {
    LockWorktreeRequest request;
    request.path = fsutil::pathFromUtf8(path != nullptr ? path : "");
    request.reason = reason != nullptr ? reason : "";
    toSession(session)->lockWorktree(std::move(request));
} catch (...) {
    reportCurrentException(__func__);
}

GBM_API void gbm_worktree_unlock(GbmSessionHandle session, const char* path) try {
    UnlockWorktreeRequest request;
    request.path = fsutil::pathFromUtf8(path != nullptr ? path : "");
    toSession(session)->unlockWorktree(request);
} catch (...) {
    reportCurrentException(__func__);
}
