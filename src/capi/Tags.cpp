#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/git/ops/TagOps.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_tag_create(GbmSessionHandle session,
                            const char* name,
                            const char* target,
                            const char* message,
                            int32_t force) {
    CreateTagRequest request;
    request.name = name != nullptr ? name : "";
    request.target = target != nullptr ? target : "";
    request.message = message != nullptr ? message : "";
    request.force = force != 0;
    toSession(session)->createTag(std::move(request));
}

GBM_API void gbm_tag_delete(GbmSessionHandle session, const char* name, int32_t alsoRemote, const char* remoteName) {
    DeleteTagRequest request;
    request.name = name != nullptr ? name : "";
    request.alsoRemote = alsoRemote != 0;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    toSession(session)->deleteTag(std::move(request));
}

GBM_API void gbm_tag_push(GbmSessionHandle session, const char* remoteName, const char* name) {
    PushTagRequest request;
    request.remoteName = remoteName != nullptr ? remoteName : "";
    request.name = name != nullptr ? name : "";
    toSession(session)->pushTag(std::move(request));
}
