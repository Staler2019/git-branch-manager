#include "capi/Handle.h"
#include "capi/gbm_capi.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

namespace {

std::vector<std::string> toOidVector(const char* const* oids, int32_t oidCount) {
    std::vector<std::string> out;
    out.reserve(static_cast<std::size_t>(oidCount > 0 ? oidCount : 0));
    for (int32_t i = 0; i < oidCount; ++i) {
        out.emplace_back(oids[i] != nullptr ? oids[i] : "");
    }
    return out;
}

}  // namespace

GBM_API void gbm_request_commit_meta(GbmSessionHandle session,
                                     const char* const* oids,
                                     int32_t oidCount) {
    toSession(session)->requestCommitMeta(toOidVector(oids, oidCount));
}

GBM_API void gbm_request_commit_file_counts(GbmSessionHandle session,
                                            const char* const* oids,
                                            int32_t oidCount) {
    toSession(session)->requestCommitFileCounts(toOidVector(oids, oidCount));
}
