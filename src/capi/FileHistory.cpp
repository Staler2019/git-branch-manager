#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_request_file_history(GbmSessionHandle session,
                                      const char* path,
                                      const char* startRevision) {
    toSession(session)->requestFileHistory(path != nullptr ? path : "",
                                           startRevision != nullptr ? startRevision : "");
}

GBM_API void gbm_request_line_history(GbmSessionHandle session,
                                      const char* path,
                                      int32_t startLine,
                                      int32_t endLine,
                                      const char* startRevision) {
    toSession(session)->requestLineHistory(path != nullptr ? path : "",
                                           startLine,
                                           endLine,
                                           startRevision != nullptr ? startRevision : "");
}
