#pragma once

// GbmSessionHandle/GbmDiscoveryHandle are opaque `void*` in gbm_capi.h; these
// helpers are the one place that casts them back to the real C++ type, so a
// mismatch shows up here instead of at every call site.

#include "capi/Session.h"
#include "capi/gbm_capi.h"
#include "core/cache/RepoIndexDb.h"

namespace gbm::capi {

inline Session* toSession(GbmSessionHandle handle) {
    return static_cast<Session*>(handle);
}

inline GbmSessionHandle toHandle(Session* session) {
    return static_cast<GbmSessionHandle>(session);
}

/// Owns the RepoIndexDb a GbmDiscoveryHandle points at. A thin wrapper
/// rather than exposing RepoIndexDb* directly so Discovery.cpp has one place
/// to grow shared discovery-session state later (e.g. a scan cancellation
/// token) without changing the handle's identity.
struct DiscoveryState {
    RepoIndexDb db;
};

inline DiscoveryState* toDiscovery(GbmDiscoveryHandle handle) {
    return static_cast<DiscoveryState*>(handle);
}

inline GbmDiscoveryHandle toHandle(DiscoveryState* state) {
    return static_cast<GbmDiscoveryHandle>(state);
}

}  // namespace gbm::capi
