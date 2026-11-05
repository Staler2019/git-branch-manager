#include "capi/Handle.h"
#include "capi/gbm_capi.h"

#include <string>

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_request_commit_files(GbmSessionHandle session, const char* oid) try {
    toSession(session)->requestCommitFiles(oid != nullptr ? std::string(oid) : "");
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_request_commit_file_diff(GbmSessionHandle session,
                                          const char* oid,
                                          const char* path,
                                          const char* oldPath) try {
    toSession(session)->requestCommitFileDiff(oid != nullptr ? std::string(oid) : "",
                                              path != nullptr ? std::string(path) : "",
                                              oldPath != nullptr ? std::string(oldPath) : "");
} catch (...) {
    reportNativeException(__func__);
}
