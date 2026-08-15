#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/base/ObjectId.h"
#include "core/git/ops/CherryPickOps.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

namespace {

std::vector<ObjectId> toObjectIds(const char* const* commitHexes, int32_t commitCount) {
    std::vector<ObjectId> out;
    out.reserve(static_cast<std::size_t>(commitCount > 0 ? commitCount : 0));
    for (int32_t i = 0; i < commitCount; ++i) {
        if (commitHexes[i] != nullptr) {
            out.push_back(ObjectId::fromHex(commitHexes[i]));
        }
    }
    return out;
}

}  // namespace

GBM_API void gbm_cherry_pick(GbmSessionHandle session,
                             const char* const* commitHexes,
                             int32_t commitCount,
                             int32_t mainline,
                             int32_t noCommit,
                             int32_t stashFirst) {
    CherryPickRequest request;
    request.commits = toObjectIds(commitHexes, commitCount);
    request.mainline = mainline;
    request.noCommit = noCommit != 0;
    request.stashFirst = stashFirst != 0;
    toSession(session)->cherryPick(std::move(request));
}

GBM_API void gbm_cherry_pick_continue(GbmSessionHandle session) {
    toSession(session)->continueCherryPick();
}

GBM_API void gbm_cherry_pick_continue_with_message(GbmSessionHandle session, const char* message) {
    toSession(session)->continueCherryPickWithMessage(message != nullptr ? std::string(message) : "");
}

GBM_API void gbm_cherry_pick_skip(GbmSessionHandle session) {
    toSession(session)->skipCherryPick();
}

GBM_API void gbm_cherry_pick_abort(GbmSessionHandle session) {
    toSession(session)->abortCherryPick();
}
