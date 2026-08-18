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

GBM_API void gbm_remote_refresh(GbmSessionHandle session) {
    toSession(session)->refreshRemotes();
}

GBM_API int32_t gbm_remotes_json(GbmSessionHandle session) {
    const RemoteListPtr remotes = toSession(session)->currentRemotes();
    if (!remotes) {
        setStagingBuffer(
            toJson(GitError(GitError::Code::NotFound, "no remote list published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*remotes));
    return 0;
}

GBM_API void gbm_remote_fetch(GbmSessionHandle session,
                              const char* remoteName,
                              const char* const* refs,
                              int32_t refCount,
                              int32_t prune,
                              int32_t tags) {
    FetchRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    request.refs = toStringVector(refs, refCount);
    request.prune = prune != 0;
    request.tags = tags != 0;
    toSession(session)->fetchRemote(std::move(request));
}

GBM_API void gbm_pull(GbmSessionHandle session,
                      const char* remoteName,
                      const char* branch,
                      int32_t rebase,
                      int32_t stashFirst) {
    PullRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    request.branch = branch != nullptr ? branch : "";
    request.rebase = rebase != 0;
    request.stashFirst = stashFirst != 0;
    toSession(session)->pullChanges(std::move(request));
}

GBM_API void gbm_push(GbmSessionHandle session,
                      const char* remoteName,
                      const char* branch,
                      int32_t setUpstream,
                      int32_t pushTags,
                      int32_t forceWithLease) {
    PushRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    request.branch = branch != nullptr ? branch : "";
    request.setUpstream = setUpstream != 0;
    request.pushTags = pushTags != 0;
    request.force = forceWithLease != 0 ? PushForceMode::ForceWithLease : PushForceMode::None;
    toSession(session)->pushChanges(std::move(request));
}

GBM_API void gbm_request_remote_prune_preview(GbmSessionHandle session, const char* remoteName) {
    toSession(session)->requestRemotePrunePreview(remoteName != nullptr ? remoteName : "");
}

GBM_API void gbm_remote_prune(GbmSessionHandle session,
                              const char* remoteName,
                              const char* const* refs,
                              int32_t refCount) {
    PruneRemoteRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    request.refs = toStringVector(refs, refCount);
    toSession(session)->pruneRemote(std::move(request));
}

GBM_API void gbm_remote_add(GbmSessionHandle session, const char* name, const char* url) {
    AddRemoteRequest request;
    request.name = name != nullptr ? name : "";
    request.url = url != nullptr ? url : "";
    toSession(session)->addRemote(std::move(request));
}

GBM_API void gbm_remote_remove(GbmSessionHandle session, const char* name) {
    RemoveRemoteRequest request;
    request.name = name != nullptr ? name : "";
    toSession(session)->removeRemote(std::move(request));
}

GBM_API void gbm_provide_credential(GbmSessionHandle session, const char* secret) {
    toSession(session)->provideCredential(secret != nullptr ? secret : "");
}

GBM_API void gbm_cancel_credential(GbmSessionHandle session) {
    toSession(session)->cancelCredential();
}
