#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/git/ops/CommitOps.h"
#include "core/git/ops/StageOps.h"

#include <string>
#include <vector>

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_working_copy_refresh(GbmSessionHandle session) try {
    toSession(session)->refreshWorkingCopy();
} catch (...) {
    reportNativeException(__func__);
}

GBM_API int32_t gbm_working_copy_status_json(GbmSessionHandle session) try {
    const WorkingCopyStatusPtr status = toSession(session)->currentWorkingCopyStatus();
    if (!status) {
        setStagingBuffer(
            toJson(GitError(GitError::Code::NotFound, "no working copy status published yet")));
        return -(1 + static_cast<int32_t>(GitError::Code::NotFound));
    }
    setStagingBuffer(toJson(*status));
    return 0;
} catch (...) {
    reportNativeException(__func__);
    return -1;
}

GBM_API void gbm_working_copy_diff(GbmSessionHandle session,
                                   const char* path,
                                   const char* oldPath,
                                   int32_t staged) try {
    toSession(session)->requestWorkingCopyDiff(
        path != nullptr ? path : "", oldPath != nullptr ? oldPath : "", staged != 0);
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_working_copy_full_diff(GbmSessionHandle session,
                                        const char* path,
                                        const char* oldPath,
                                        int32_t staged) try {
    toSession(session)->requestWorkingCopyFullDiff(
        path != nullptr ? path : "", oldPath != nullptr ? oldPath : "", staged != 0);
} catch (...) {
    reportNativeException(__func__);
}

namespace {

std::vector<std::string> toPathVector(const char* const* paths, int32_t pathCount) {
    std::vector<std::string> out;
    out.reserve(static_cast<std::size_t>(pathCount > 0 ? pathCount : 0));
    for (int32_t i = 0; i < pathCount; ++i) {
        out.emplace_back(paths[i] != nullptr ? paths[i] : "");
    }
    return out;
}

}  // namespace

GBM_API void gbm_stage_files(GbmSessionHandle session,
                             const char* const* paths,
                             int32_t pathCount) try {
    toSession(session)->stageFiles(toPathVector(paths, pathCount));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_unstage_files(GbmSessionHandle session,
                               const char* const* paths,
                               int32_t pathCount) try {
    toSession(session)->unstageFiles(toPathVector(paths, pathCount));
} catch (...) {
    reportNativeException(__func__);
}

namespace {

std::vector<std::size_t> toIndexVector(const int32_t* indices, int32_t indexCount) {
    std::vector<std::size_t> out;
    out.reserve(static_cast<std::size_t>(indexCount > 0 ? indexCount : 0));
    for (int32_t i = 0; i < indexCount; ++i) {
        if (indices[i] >= 0) {
            out.push_back(static_cast<std::size_t>(indices[i]));
        }
    }
    return out;
}

}  // namespace

GBM_API void gbm_stage_hunk(GbmSessionHandle session, const char* path, int32_t hunkIndex) try {
    toSession(session)->stageHunk(path != nullptr ? path : "", static_cast<std::size_t>(hunkIndex));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_unstage_hunk(GbmSessionHandle session,
                              const char* path,
                              const char* oldPath,
                              int32_t hunkIndex) try {
    toSession(session)->unstageHunk(path != nullptr ? path : "",
                                    oldPath != nullptr ? oldPath : "",
                                    static_cast<std::size_t>(hunkIndex));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_stage_lines(GbmSessionHandle session,
                             const char* path,
                             int32_t hunkIndex,
                             const int32_t* lineIndices,
                             int32_t lineIndexCount) try {
    toSession(session)->stageLines(path != nullptr ? path : "",
                                   static_cast<std::size_t>(hunkIndex),
                                   toIndexVector(lineIndices, lineIndexCount));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_unstage_lines(GbmSessionHandle session,
                               const char* path,
                               const char* oldPath,
                               int32_t hunkIndex,
                               const int32_t* lineIndices,
                               int32_t lineIndexCount) try {
    toSession(session)->unstageLines(path != nullptr ? path : "",
                                     oldPath != nullptr ? oldPath : "",
                                     static_cast<std::size_t>(hunkIndex),
                                     toIndexVector(lineIndices, lineIndexCount));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_discard_lines(GbmSessionHandle session,
                               const char* path,
                               int32_t hunkIndex,
                               const int32_t* lineIndices,
                               int32_t lineIndexCount) try {
    toSession(session)->discardLines(path != nullptr ? path : "",
                                     static_cast<std::size_t>(hunkIndex),
                                     toIndexVector(lineIndices, lineIndexCount));
} catch (...) {
    reportNativeException(__func__);
}

GBM_API void gbm_commit_changes(GbmSessionHandle session,
                                const char* message,
                                int32_t amend,
                                int32_t signOff) try {
    CommitRequest request;
    request.message = message != nullptr ? message : "";
    request.amend = amend != 0;
    request.signOff = signOff != 0;
    toSession(session)->commitChanges(std::move(request));
} catch (...) {
    reportNativeException(__func__);
}
