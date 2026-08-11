#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm::capi;

GBM_API void gbm_history_refresh(GbmSessionHandle session) {
    toSession(session)->refreshHistory();
}
