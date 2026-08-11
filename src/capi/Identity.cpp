#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/base/Error.h"
#include "core/git/ops/ConfigOps.h"
#include "core/git/ops/MaintenanceOps.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_local_identity_refresh(GbmSessionHandle session) {
    toSession(session)->refreshLocalIdentity();
}

GBM_API int32_t gbm_local_identity_json(GbmSessionHandle session) {
    const LocalIdentityPtr identity = toSession(session)->currentLocalIdentity();
    if (!identity) {
        setStagingBuffer(toJson(GitError(GitError::Code::NotFound, "no local identity published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*identity));
    return 0;
}

GBM_API void gbm_effective_identity_refresh(GbmSessionHandle session) {
    toSession(session)->refreshEffectiveIdentity();
}

GBM_API int32_t gbm_effective_identity_json(GbmSessionHandle session) {
    const EffectiveIdentityPtr identity = toSession(session)->currentEffectiveIdentity();
    if (!identity) {
        setStagingBuffer(toJson(GitError(GitError::Code::NotFound, "no effective identity published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*identity));
    return 0;
}

GBM_API void gbm_set_local_identity(GbmSessionHandle session, const char* name, const char* email) {
    SetLocalIdentityRequest request;
    request.name = name != nullptr ? name : "";
    request.email = email != nullptr ? email : "";
    toSession(session)->setLocalIdentityOverride(std::move(request));
}

GBM_API void gbm_clear_local_identity(GbmSessionHandle session) {
    toSession(session)->clearLocalIdentityOverride();
}

GBM_API int32_t gbm_has_commit_graph(GbmSessionHandle session) {
    return toSession(session)->hasCommitGraph() ? 1 : 0;
}

GBM_API void gbm_write_commit_graph(GbmSessionHandle session) {
    toSession(session)->writeCommitGraph();
}
