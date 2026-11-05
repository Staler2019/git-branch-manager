#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm::capi;

GBM_API uint64_t gbm_history_refresh(GbmSessionHandle session) try {
    return toSession(session)->refreshHistory();
} catch (...) {
    reportNativeException(__func__);
    return 0;
}

GBM_API void gbm_history_set_filter(GbmSessionHandle session,
                                    const char* const* includeRefs,
                                    int32_t includeRefCount,
                                    int32_t firstParentOnly,
                                    int32_t noMerges) try {
    toSession(session)->setHistoryFilter(
        toStringVector(includeRefs, includeRefCount), firstParentOnly != 0, noMerges != 0);
} catch (...) {
    gbm::reportCurrentException(__func__);
}
