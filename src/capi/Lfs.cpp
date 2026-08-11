#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/base/Error.h"
#include "core/git/ops/LfsOps.h"

#include <optional>

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_lfs_refresh(GbmSessionHandle session) {
    toSession(session)->refreshLfs();
}

GBM_API int32_t gbm_lfs_installation_json(GbmSessionHandle session) {
    const std::optional<LfsInstallation> installation =
        toSession(session)->currentLfsInstallation();
    if (!installation.has_value()) {
        setStagingBuffer(
            toJson(GitError(GitError::Code::NotFound, "gbm_lfs_refresh has not run yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*installation));
    return 0;
}

GBM_API int32_t gbm_lfs_patterns_json(GbmSessionHandle session) {
    const LfsPatternListPtr patterns = toSession(session)->currentLfsPatterns();
    if (!patterns) {
        setStagingBuffer(
            toJson(GitError(GitError::Code::NotFound, "no LFS pattern list published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*patterns));
    return 0;
}

GBM_API int32_t gbm_lfs_files_json(GbmSessionHandle session) {
    const LfsFileListPtr files = toSession(session)->currentLfsFiles();
    if (!files) {
        setStagingBuffer(
            toJson(GitError(GitError::Code::NotFound, "no LFS file list published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*files));
    return 0;
}

GBM_API void gbm_lfs_install(GbmSessionHandle session) {
    toSession(session)->installLfs();
}

GBM_API void gbm_lfs_track(GbmSessionHandle session, const char* pattern) {
    LfsTrackRequest request;
    request.pattern = pattern != nullptr ? pattern : "";
    toSession(session)->trackLfsPattern(std::move(request));
}

GBM_API void gbm_lfs_untrack(GbmSessionHandle session, const char* pattern) {
    LfsUntrackRequest request;
    request.pattern = pattern != nullptr ? pattern : "";
    toSession(session)->untrackLfsPattern(std::move(request));
}

GBM_API void gbm_lfs_pull(GbmSessionHandle session, const char* remoteName) {
    LfsTransferRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    toSession(session)->pullLfs(std::move(request));
}

GBM_API void gbm_lfs_fetch(GbmSessionHandle session, const char* remoteName) {
    LfsTransferRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    toSession(session)->fetchLfs(std::move(request));
}

GBM_API void gbm_lfs_prune(GbmSessionHandle session, int32_t dryRun) {
    LfsPruneRequest request;
    request.dryRun = dryRun != 0;
    toSession(session)->pruneLfs(request);
}
