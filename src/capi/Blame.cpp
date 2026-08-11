#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_request_blame(GbmSessionHandle session,
                               const char* path,
                               const char* revision,
                               int32_t startLine,
                               int32_t endLine) {
    toSession(session)->requestBlame(
        path != nullptr ? path : "", revision != nullptr ? revision : "", startLine, endLine);
}
