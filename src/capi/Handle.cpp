#include "capi/Handle.h"

#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>

namespace gbm::capi {

namespace {
thread_local std::string g_stagingBuffer;
}  // namespace

void setStagingBuffer(std::string json) {
    g_stagingBuffer = std::move(json);
}

const std::string& stagingBuffer() {
    return g_stagingBuffer;
}

}  // namespace gbm::capi

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_free_event_payload(const uint8_t* payload) {
    // NOLINTNEXTLINE(cppcoreguidelines-owning-memory) -- allocated with
    // std::malloc in CallbackRegistry::emit(); see gbm_capi.h's ownership note.
    std::free(const_cast<uint8_t*>(payload));
}

GBM_API int32_t gbm_last_result_json_len(void) {
    return static_cast<int32_t>(stagingBuffer().size());
}

GBM_API void gbm_last_result_json_copy(uint8_t* out, int32_t outLen) {
    const std::string& buffer = stagingBuffer();
    const std::size_t n = std::min(static_cast<std::size_t>(outLen), buffer.size());
    std::memcpy(out, buffer.data(), n);
}

GBM_API GbmSessionHandle gbm_session_open(const char* workDir,
                                          const char* gitDir,
                                          const char* commonDir) {
    GitError error;
    std::unique_ptr<Session> session = Session::open(workDir != nullptr ? workDir : "",
                                                     gitDir != nullptr ? gitDir : "",
                                                     commonDir != nullptr ? commonDir : "",
                                                     &error);
    if (!session) {
        setStagingBuffer(toJson(error));
        return nullptr;
    }
    return toHandle(session.release());
}

GBM_API void gbm_session_close(GbmSessionHandle session) {
    delete toSession(session);
}

GBM_API void gbm_register_callback(GbmSessionHandle session,
                                   GbmEventCallback callback,
                                   void* userData) {
    toSession(session)->registerCallback(callback, userData);
}

GBM_API int32_t gbm_repo_state_json(GbmSessionHandle session) {
    setStagingBuffer(toJson(toSession(session)->repoState()));
    return 0;
}
