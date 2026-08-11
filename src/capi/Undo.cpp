#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"

using namespace gbm;
using namespace gbm::capi;

GBM_API int32_t gbm_undo_journal_json(GbmSessionHandle session) {
    setStagingBuffer(toJson(toSession(session)->undoJournal()));
    return 0;
}

GBM_API void gbm_undo_last(GbmSessionHandle session) {
    toSession(session)->undoLastOperation();
}
