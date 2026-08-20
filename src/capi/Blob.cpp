// FFI surface for reading a file as it was at a given revision. One file per
// FFI domain, like the rest of src/capi -- each function transliterates a
// Session call and nothing else.
#include "capi/Handle.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_export_file_at_revision(GbmSessionHandle session,
                                         const char* revision,
                                         const char* path,
                                         const char* destPath) {
    toSession(session)->exportFileAtRevision(revision != nullptr ? revision : "",
                                             path != nullptr ? path : "",
                                             destPath != nullptr ? destPath : "");
}
