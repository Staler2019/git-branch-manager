#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API int32_t gbm_refs_json(GbmSessionHandle session) {
    const RefSnapshotPtr refs = toSession(session)->currentRefs();
    if (!refs) {
        setStagingBuffer(toJson(GitError(GitError::Code::NotFound, "no refs published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*refs));
    return 0;
}
