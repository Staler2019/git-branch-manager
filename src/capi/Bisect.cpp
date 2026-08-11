#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/base/Error.h"
#include "core/git/ops/BisectOps.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

namespace {

std::vector<std::string> toStringVector(const char* const* items, int32_t count) {
    std::vector<std::string> out;
    out.reserve(static_cast<std::size_t>(count > 0 ? count : 0));
    for (int32_t i = 0; i < count; ++i) {
        if (items[i] != nullptr) {
            out.emplace_back(items[i]);
        }
    }
    return out;
}

}  // namespace

GBM_API void gbm_bisect_refresh(GbmSessionHandle session) {
    toSession(session)->refreshBisectStatus();
}

GBM_API int32_t gbm_bisect_status_json(GbmSessionHandle session) {
    const BisectStatusPtr status = toSession(session)->currentBisectStatus();
    if (!status) {
        setStagingBuffer(
            toJson(GitError(GitError::Code::NotFound, "no bisect status published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*status));
    return 0;
}

GBM_API void gbm_bisect_start(GbmSessionHandle session,
                              const char* badRef,
                              const char* const* goodRefs,
                              int32_t goodCount,
                              const char* const* paths,
                              int32_t pathCount,
                              int32_t noCheckout) {
    BisectStartRequest request;
    request.badRef = badRef != nullptr ? badRef : "";
    request.goodRefs = toStringVector(goodRefs, goodCount);
    request.paths = toStringVector(paths, pathCount);
    request.noCheckout = noCheckout != 0;
    toSession(session)->startBisect(std::move(request));
}

GBM_API void gbm_bisect_mark(GbmSessionHandle session, int32_t good, const char* ref) {
    BisectMarkRequest request;
    request.good = good != 0;
    request.ref = ref != nullptr ? ref : "";
    toSession(session)->markBisect(request);
}

GBM_API void gbm_bisect_skip(GbmSessionHandle session, const char* const* refs, int32_t refCount) {
    BisectSkipRequest request;
    request.refs = toStringVector(refs, refCount);
    toSession(session)->skipBisect(std::move(request));
}

GBM_API void gbm_bisect_reset(GbmSessionHandle session, const char* target) {
    BisectResetRequest request;
    request.target = target != nullptr ? target : "";
    toSession(session)->resetBisect(std::move(request));
}
