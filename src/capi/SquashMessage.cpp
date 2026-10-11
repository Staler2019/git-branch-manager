#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_request_squash_message(GbmSessionHandle session, const char* source) {
    toSession(session)->requestSquashMessage(source != nullptr ? source : "");
}
