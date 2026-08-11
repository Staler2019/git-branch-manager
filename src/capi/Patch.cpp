#include "capi/Handle.h"
#include "capi/gbm_capi.h"
#include "core/base/ObjectId.h"
#include "core/git/ops/PatchOps.h"

#include <filesystem>
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

std::vector<std::filesystem::path> toPaths(const char* const* files, int32_t fileCount) {
    std::vector<std::filesystem::path> out;
    out.reserve(static_cast<std::size_t>(fileCount > 0 ? fileCount : 0));
    for (int32_t i = 0; i < fileCount; ++i) {
        if (files[i] != nullptr) {
            out.emplace_back(files[i]);
        }
    }
    return out;
}

}  // namespace

GBM_API void gbm_patch_export(GbmSessionHandle session,
                              const char* const* commitHexes,
                              int32_t commitCount,
                              const char* outputDir) {
    ExportPatchesRequest request;
    request.commits = toObjectIds(commitHexes, commitCount);
    request.outputDir = outputDir != nullptr ? outputDir : "";
    toSession(session)->exportPatches(std::move(request));
}

GBM_API void gbm_patch_apply_files(GbmSessionHandle session,
                                   const char* const* patchFiles,
                                   int32_t fileCount,
                                   int32_t threeWay,
                                   int32_t updateIndex) {
    ApplyPatchFilesRequest request;
    request.patchFiles = toPaths(patchFiles, fileCount);
    request.threeWay = threeWay != 0;
    request.updateIndex = updateIndex != 0;
    toSession(session)->applyPatchFiles(std::move(request));
}

GBM_API void gbm_patch_import(GbmSessionHandle session, const char* const* patchFiles, int32_t fileCount, int32_t threeWay) {
    ImportPatchesRequest request;
    request.patchFiles = toPaths(patchFiles, fileCount);
    request.threeWay = threeWay != 0;
    toSession(session)->importPatches(std::move(request));
}

GBM_API void gbm_patch_import_continue(GbmSessionHandle session) {
    toSession(session)->continueImport();
}

GBM_API void gbm_patch_import_skip(GbmSessionHandle session) {
    toSession(session)->skipImport();
}

GBM_API void gbm_patch_import_abort(GbmSessionHandle session) {
    toSession(session)->abortImport();
}
