#include "capi/JsonCodec.h"
#include "capi/Session.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/base/CancellationToken.h"
#include "core/git/ops/InitCloneOps.h"

using namespace gbm;
using namespace gbm::capi;

namespace {

/// -(1 + code-ordinal), matching gbm_capi.h's GbmErrorCode mapping -- same
/// helper as Discovery.cpp's, duplicated rather than shared since these
/// session-less capi files have no common base to hang it from.
int32_t errorCodeOrdinal(const GitError& error) {
    return -(1 + static_cast<int32_t>(error.code));
}

}  // namespace

GBM_API int32_t gbm_repo_init(const char* path) {
    const GitResult<GitInstallation> installation = sharedGitInstallation();
    if (!installation) {
        setStagingBuffer(toJson(installation.error()));
        return errorCodeOrdinal(installation.error());
    }
    std::unique_ptr<IProcessRunner> runner = makeProcessRunner(installation.value().executable);

    InitRepoRequest request;
    request.path = path != nullptr ? path : "";

    const CancellationSource cancel;  // Synchronous, like gbm_discovery_scan_all.
    const GitResult<void> result = runInitRepo(*runner, request, cancel.token());
    if (!result) {
        setStagingBuffer(toJson(result.error()));
        return errorCodeOrdinal(result.error());
    }
    return 0;
}

GBM_API int32_t gbm_repo_clone(const char* url, const char* destPath) {
    const GitResult<GitInstallation> installation = sharedGitInstallation();
    if (!installation) {
        setStagingBuffer(toJson(installation.error()));
        return errorCodeOrdinal(installation.error());
    }
    std::unique_ptr<IProcessRunner> runner = makeProcessRunner(installation.value().executable);

    CloneRepoRequest request;
    request.url = url != nullptr ? url : "";
    request.destPath = destPath != nullptr ? destPath : "";

    const CancellationSource cancel;  // Synchronous, like gbm_discovery_scan_all.
    const GitResult<void> result = runCloneRepo(*runner, request, cancel.token());
    if (!result) {
        setStagingBuffer(toJson(result.error()));
        return errorCodeOrdinal(result.error());
    }
    return 0;
}
