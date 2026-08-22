#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/base/Error.h"
#include "core/git/ops/SubmoduleOps.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

namespace {}  // namespace

GBM_API void gbm_submodule_refresh(GbmSessionHandle session) {
    toSession(session)->refreshSubmodules();
}

GBM_API int32_t gbm_submodules_json(GbmSessionHandle session) {
    const SubmoduleListPtr submodules = toSession(session)->currentSubmodules();
    if (!submodules) {
        setStagingBuffer(
            toJson(GitError(GitError::Code::NotFound, "no submodule list published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*submodules));
    return 0;
}

GBM_API void gbm_submodule_add(GbmSessionHandle session,
                               const char* url,
                               const char* path,
                               const char* branch) {
    AddSubmoduleRequest request;
    request.url = url != nullptr ? url : "";
    request.path = path != nullptr ? path : "";
    request.branch = branch != nullptr ? branch : "";
    toSession(session)->addSubmodule(std::move(request));
}

GBM_API void gbm_submodule_init(GbmSessionHandle session,
                                const char* const* paths,
                                int32_t pathCount,
                                int32_t recursive) {
    SubmodulePathsRequest request;
    request.paths = toStringVector(paths, pathCount);
    request.recursive = recursive != 0;
    toSession(session)->initSubmodules(std::move(request));
}

GBM_API void gbm_submodule_update(GbmSessionHandle session,
                                  const char* const* paths,
                                  int32_t pathCount,
                                  int32_t recursive,
                                  int32_t init,
                                  int32_t remote) {
    UpdateSubmodulesRequest request;
    request.paths = toStringVector(paths, pathCount);
    request.recursive = recursive != 0;
    request.init = init != 0;
    request.remote = remote != 0;
    toSession(session)->updateSubmodules(std::move(request));
}

GBM_API void gbm_submodule_sync(GbmSessionHandle session,
                                const char* const* paths,
                                int32_t pathCount,
                                int32_t recursive) {
    SubmodulePathsRequest request;
    request.paths = toStringVector(paths, pathCount);
    request.recursive = recursive != 0;
    toSession(session)->syncSubmodules(std::move(request));
}

GBM_API void gbm_submodule_deinit(GbmSessionHandle session,
                                  const char* const* paths,
                                  int32_t pathCount,
                                  int32_t force) {
    DeinitSubmodulesRequest request;
    request.paths = toStringVector(paths, pathCount);
    request.force = force != 0;
    toSession(session)->deinitSubmodules(std::move(request));
}
