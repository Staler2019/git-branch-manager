#include "capi/CallbackRegistry.h"

#include <cstdlib>
#include <cstring>

namespace gbm::capi {

void CallbackRegistry::set(GbmSessionHandle session, GbmEventCallback callback, void* userData) {
    std::lock_guard<std::mutex> lock(mutex_);
    session_ = session;
    callback_ = callback;
    userData_ = userData;
}

void CallbackRegistry::emit(int32_t eventType, const std::string& json) const {
    GbmSessionHandle session;
    GbmEventCallback callback;
    void* userData;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        session = session_;
        callback = callback_;
        userData = userData_;
    }
    if (callback == nullptr) {
        return;
    }
    // Freed by the receiver via gbm_free_event_payload() -- see gbm_capi.h.
    auto* buffer = static_cast<uint8_t*>(std::malloc(json.size()));
    if (buffer == nullptr && !json.empty()) {
        return;  // Out of memory: drop the event rather than crash.
    }
    if (!json.empty()) {
        std::memcpy(buffer, json.data(), json.size());
    }
    callback(session, eventType, buffer, static_cast<int32_t>(json.size()), userData);
}

void CallbackRegistry::emitEmpty(int32_t eventType) const {
    GbmSessionHandle session;
    GbmEventCallback callback;
    void* userData;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        session = session_;
        callback = callback_;
        userData = userData_;
    }
    if (callback == nullptr) {
        return;
    }
    callback(session, eventType, nullptr, 0, userData);
}

}  // namespace gbm::capi
