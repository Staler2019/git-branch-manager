#pragma once

// Where core results become GbmEventCallback invocations -- the FFI analog
// of RepositorySession's `signals:` block. One instance per open Session.
//
// emit() may be called from any thread (a ThreadPool worker, the
// OperationRunner serial thread, ...): it heap-copies the payload and hands
// the callback a plain pointer + length, matching the ownership contract in
// gbm_capi.h (receiver frees via gbm_free_event_payload). This is what lets
// the Dart side register the callback as a NativeCallable.listener, which is
// the only NativeCallable variant safe to invoke from a thread other than
// the one that created it.

#include "capi/gbm_capi.h"

#include <mutex>
#include <string>

namespace gbm::capi {

class CallbackRegistry {
public:
    void set(GbmSessionHandle session, GbmEventCallback callback, void* userData);

    /// Invokes the registered callback (if any) with a heap copy of `json`.
    void emit(int32_t eventType, const std::string& json) const;

    /// Invokes the registered callback (if any) with no payload.
    void emitEmpty(int32_t eventType) const;

private:
    mutable std::mutex mutex_;
    GbmSessionHandle session_ = nullptr;
    GbmEventCallback callback_ = nullptr;
    void* userData_ = nullptr;
};

}  // namespace gbm::capi
