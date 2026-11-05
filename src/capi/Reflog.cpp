#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_request_reflog(GbmSessionHandle session, const char* ref) try {
    toSession(session)->requestReflog(ref != nullptr ? ref : "");
} catch (...) {
    reportCurrentException(__func__);
}
