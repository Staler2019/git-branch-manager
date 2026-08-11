#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/git/ops/ResetOps.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_reset_to(GbmSessionHandle session, const char* target, int32_t mode) {
    ResetRequest request;
    request.target = target != nullptr ? target : "";
    request.mode = static_cast<ResetMode>(mode);
    toSession(session)->resetTo(std::move(request));
}
