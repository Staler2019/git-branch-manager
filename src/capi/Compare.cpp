#include "capi/Handle.h"
#include "capi/gbm_capi.h"

#include <string>

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_request_compare_refs(GbmSessionHandle session,
                                      const char* leftRef,
                                      const char* rightRef,
                                      int32_t threeDot) try {
    toSession(session)->requestCompareRefs(leftRef != nullptr ? std::string(leftRef) : "",
                                           rightRef != nullptr ? std::string(rightRef) : "",
                                           threeDot != 0);
} catch (...) {
    reportCurrentException(__func__);
}

GBM_API void gbm_request_compare_file_diff(GbmSessionHandle session,
                                           const char* leftRef,
                                           const char* rightRef,
                                           int32_t threeDot,
                                           const char* path,
                                           const char* oldPath) try {
    toSession(session)->requestCompareFileDiff(leftRef != nullptr ? std::string(leftRef) : "",
                                               rightRef != nullptr ? std::string(rightRef) : "",
                                               threeDot != 0,
                                               path != nullptr ? std::string(path) : "",
                                               oldPath != nullptr ? std::string(oldPath) : "");
} catch (...) {
    reportCurrentException(__func__);
}

GBM_API void gbm_request_compare_with_working_copy(GbmSessionHandle session, const char* ref) try {
    toSession(session)->requestCompareWithWorkingCopy(ref != nullptr ? std::string(ref) : "");
} catch (...) {
    reportCurrentException(__func__);
}
