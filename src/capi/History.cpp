#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm::capi;

GBM_API void gbm_history_refresh(GbmSessionHandle session) {
    toSession(session)->refreshHistory();
}

GBM_API void gbm_history_set_filter(GbmSessionHandle session,
                                    const char* const* includeRefs,
                                    int32_t includeRefCount,
                                    int32_t firstParentOnly,
                                    int32_t noMerges) {
    toSession(session)->setHistoryFilter(
        toStringVector(includeRefs, includeRefCount), firstParentOnly != 0, noMerges != 0);
}
