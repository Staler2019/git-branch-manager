#pragma once

// GbmSessionHandle/GbmDiscoveryHandle are opaque `void*` in gbm_capi.h; these
// helpers are the one place that casts them back to the real C++ type, so a
// mismatch shows up here instead of at every call site.

#include "capi/Session.h"
#include "capi/gbm_capi.h"
#include "core/cache/RepoIndexDb.h"

#include <cstdint>
#include <string>
#include <vector>

namespace gbm::capi {

/// The `const char* const*` + count convention every batch entry point uses
/// (gbm_branch_delete's names, gbm_remote_fetch's refs, gbm_push's branches,
/// gbm_history_set_filter's includeRefs, ...). A null element is skipped
/// rather than turned into an empty string, so one bad slot in the caller's
/// array narrows the batch instead of handing git an empty argument.
inline std::vector<std::string> toStringVector(const char* const* items, std::int32_t count) {
    std::vector<std::string> out;
    out.reserve(static_cast<std::size_t>(count > 0 ? count : 0));
    for (std::int32_t i = 0; i < count; ++i) {
        if (items[i] != nullptr) {
            out.emplace_back(items[i]);
        }
    }
    return out;
}

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
