#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/base/ObjectId.h"
#include "core/git/ops/RevertOps.h"

#include <vector>

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_revert(GbmSessionHandle session,
                        const char* const* commitHexes,
                        int32_t commitCount,
                        int32_t noCommit,
                        int32_t stashFirst) {
    RevertRequest request;
    request.commits.reserve(static_cast<std::size_t>(commitCount > 0 ? commitCount : 0));
    for (int32_t i = 0; i < commitCount; ++i) {
        if (commitHexes[i] != nullptr) {
            request.commits.push_back(ObjectId::fromHex(commitHexes[i]));
        }
    }
    request.noCommit = noCommit != 0;
    request.stashFirst = stashFirst != 0;
    toSession(session)->revertCommit(std::move(request));
}
