#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API int32_t gbm_request_file_history(GbmSessionHandle session,
                                         const char* path,
                                         const char* startRevision) try {
    toSession(session)->requestFileHistory(path != nullptr ? path : "",
                                           startRevision != nullptr ? startRevision : "");
    return 1;
} catch (...) {
    reportNativeException(__func__);
    return 0;
}

GBM_API int32_t gbm_request_line_history(GbmSessionHandle session,
                                         const char* path,
                                         int32_t startLine,
                                         int32_t endLine,
                                         const char* startRevision) try {
    toSession(session)->requestLineHistory(path != nullptr ? path : "",
                                           startLine,
                                           endLine,
                                           startRevision != nullptr ? startRevision : "");
    return 1;
} catch (...) {
    reportNativeException(__func__);
    return 0;
}
