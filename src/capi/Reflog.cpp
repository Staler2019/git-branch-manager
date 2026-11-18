#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API int32_t gbm_request_reflog(GbmSessionHandle session, const char* ref) try {
    toSession(session)->requestReflog(ref != nullptr ? ref : "");
    return 1;
} catch (...) {
    reportNativeException(__func__);
    return 0;
}
