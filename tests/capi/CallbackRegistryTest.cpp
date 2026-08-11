#include "capi/CallbackRegistry.h"

#include <cstdlib>
#include <cstring>
#include <gtest/gtest.h>
#include <string>

namespace gbm::capi {
namespace {

struct CapturedEvent {
    GbmSessionHandle session = nullptr;
    int32_t eventType = -1;
    std::string payload;
    bool hadPayload = false;
};

void captureCallback(GbmSessionHandle session,
                     int32_t eventType,
                     const uint8_t* payload,
                     int32_t payloadLen,
                     void* userData) {
    auto* out = static_cast<CapturedEvent*>(userData);
    out->session = session;
    out->eventType = eventType;
    out->hadPayload = payload != nullptr;
    if (payload != nullptr) {
        out->payload.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        // Mirrors the receiver contract documented in gbm_capi.h.
        std::free(const_cast<uint8_t*>(payload));
    }
}

TEST(CallbackRegistryTest, EmitDeliversHeapCopyOfPayload) {
    CallbackRegistry registry;
    CapturedEvent captured;
    void* fakeSession = reinterpret_cast<void*>(0x1234);
    registry.set(fakeSession, &captureCallback, &captured);

    registry.emit(7, "{\"complete\":true}");

    EXPECT_EQ(captured.session, fakeSession);
    EXPECT_EQ(captured.eventType, 7);
    EXPECT_TRUE(captured.hadPayload);
    EXPECT_EQ(captured.payload, "{\"complete\":true}");
}

TEST(CallbackRegistryTest, EmitEmptySendsNullPayload) {
    CallbackRegistry registry;
    CapturedEvent captured;
    registry.set(reinterpret_cast<void*>(0x1), &captureCallback, &captured);

    registry.emitEmpty(1);

    EXPECT_EQ(captured.eventType, 1);
    EXPECT_FALSE(captured.hadPayload);
}

TEST(CallbackRegistryTest, EmitWithNoRegisteredCallbackIsANoop) {
    CallbackRegistry registry;
    // No crash, nothing to assert beyond "this returns".
    registry.emit(0, "{}");
    registry.emitEmpty(0);
}

}  // namespace
}  // namespace gbm::capi
