#include "capi/Handle.h"
#include "capi/gbm_capi.h"

#include <string>

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_request_compare_refs(GbmSessionHandle session,
                                      const char* leftRef,
                                      const char* rightRef,
                                      int32_t threeDot) {
    toSession(session)->requestCompareRefs(leftRef != nullptr ? std::string(leftRef) : "",
                                           rightRef != nullptr ? std::string(rightRef) : "",
                                           threeDot != 0);
}

GBM_API void gbm_request_compare_file_diff(GbmSessionHandle session,
                                           const char* leftRef,
                                           const char* rightRef,
                                           int32_t threeDot,
                                           const char* path) {
    toSession(session)->requestCompareFileDiff(leftRef != nullptr ? std::string(leftRef) : "",
                                               rightRef != nullptr ? std::string(rightRef) : "",
                                               threeDot != 0,
                                               path != nullptr ? std::string(path) : "");
}
