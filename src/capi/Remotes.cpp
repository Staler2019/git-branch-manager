#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/base/Error.h"
#include "core/git/ops/RemoteOps.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

namespace {}  // namespace

GBM_API void gbm_remote_refresh(GbmSessionHandle session) try {
    toSession(session)->refreshRemotes();
} catch (...) {
    reportNativeException(__func__);
}

GBM_API int32_t gbm_remotes_json(GbmSessionHandle session) try {
    const RemoteListPtr remotes = toSession(session)->currentRemotes();
    if (!remotes) {
        setStagingBuffer(
            toJson(GitError(GitError::Code::NotFound, "no remote list published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*remotes));
    return 0;
} catch (...) {
    reportNativeException(__func__);
    return -1;
}

GBM_API void gbm_remote_fetch(GbmSessionHandle session,
                              const char* remoteName,
                              const char* const* refs,
                              int32_t refCount,
                              int32_t prune,
                              int32_t tags,
                              int32_t background) try {
    FetchRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    request.refs = toStringVector(refs, refCount);
    request.prune = prune != 0;
    request.tags = tags != 0;
    request.background = background != 0;
    toSession(session)->fetchRemote(std::move(request));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_pull(GbmSessionHandle session,
                      const char* remoteName,
                      const char* branch,
                      int32_t rebase,
                      int32_t stashFirst) try {
    PullRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    request.branch = branch != nullptr ? branch : "";
    request.rebase = rebase != 0;
    request.stashFirst = stashFirst != 0;
    toSession(session)->pullChanges(std::move(request));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_push(GbmSessionHandle session,
                      const char* remoteName,
                      const char* const* branches,
                      int32_t branchCount,
                      int32_t setUpstream,
                      int32_t pushTags,
                      int32_t forceWithLease) try {
    PushRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    request.branches = toStringVector(branches, branchCount);
    request.setUpstream = setUpstream != 0;
    request.pushTags = pushTags != 0;
    request.force = forceWithLease != 0 ? PushForceMode::ForceWithLease : PushForceMode::None;
    toSession(session)->pushChanges(std::move(request));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_request_remote_prune_preview(GbmSessionHandle session,
                                              const char* remoteName) try {
    toSession(session)->requestRemotePrunePreview(remoteName != nullptr ? remoteName : "");
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_remote_prune(GbmSessionHandle session,
                              const char* remoteName,
                              const char* const* refs,
                              int32_t refCount) try {
    PruneRemoteRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    request.refs = toStringVector(refs, refCount);
    toSession(session)->pruneRemote(std::move(request));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_remote_add(GbmSessionHandle session, const char* name, const char* url) try {
    AddRemoteRequest request;
    request.name = name != nullptr ? name : "";
    request.url = url != nullptr ? url : "";
    toSession(session)->addRemote(std::move(request));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_remote_remove(GbmSessionHandle session, const char* name) try {
    RemoveRemoteRequest request;
    request.name = name != nullptr ? name : "";
    toSession(session)->removeRemote(std::move(request));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_provide_credential(GbmSessionHandle session, const char* secret) try {
    toSession(session)->provideCredential(secret != nullptr ? secret : "");
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_cancel_credential(GbmSessionHandle session) try {
    toSession(session)->cancelCredential();
} catch (...) {
    reportNativeException(__func__);
}
