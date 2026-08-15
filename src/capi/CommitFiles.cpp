#include "capi/Handle.h"
#include "capi/gbm_capi.h"

#include <string>

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_request_commit_files(GbmSessionHandle session, const char* oid) {
    toSession(session)->requestCommitFiles(oid != nullptr ? std::string(oid) : "");
}

GBM_API void gbm_request_commit_file_diff(GbmSessionHandle session,
                                          const char* oid,
                                          const char* path) {
    toSession(session)->requestCommitFileDiff(oid != nullptr ? std::string(oid) : "",
                                              path != nullptr ? std::string(path) : "");
}
