#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API int32_t gbm_request_blame(GbmSessionHandle session,
                                  const char* path,
                                  const char* revision,
                                  int32_t startLine,
                                  int32_t endLine) try {
    toSession(session)->requestBlame(
        path != nullptr ? path : "", revision != nullptr ? revision : "", startLine, endLine);
    return 1;
} catch (...) {
    reportNativeException(__func__);
    return 0;
}
