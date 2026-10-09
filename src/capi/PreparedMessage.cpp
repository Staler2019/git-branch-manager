#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_request_prepared_message(GbmSessionHandle session) {
    toSession(session)->requestPreparedMessage();
}
