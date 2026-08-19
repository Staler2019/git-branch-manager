#include "capi/Handle.h"
#include "capi/JsonCodec.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/base/CancellationToken.h"
#include "core/discovery/Scanner.h"

#include <string>

using namespace gbm;
using namespace gbm::capi;

namespace {

/// -(1 + code-ordinal), matching gbm_capi.h's GbmErrorCode mapping.
int32_t errorCodeOrdinal(const GitError& error) {
    return -(1 + static_cast<int32_t>(error.code));
}

}  // namespace

GBM_API GbmDiscoveryHandle gbm_discovery_open(const char* dbPath) {
    auto* state = new DiscoveryState();
    const std::string path = dbPath != nullptr ? dbPath : "";

    const GitResult<void> openResult =
        path.empty() ? state->db.openInMemory() : state->db.open(path);
    if (!openResult) {
        setStagingBuffer(toJson(openResult.error()));
        delete state;
        return nullptr;
    }

    const GitResult<void> migrateResult = state->db.migrate();
    if (!migrateResult) {
        setStagingBuffer(toJson(migrateResult.error()));
        delete state;
        return nullptr;
    }

    return toHandle(state);
}

GBM_API void gbm_discovery_close(GbmDiscoveryHandle discovery) {
    delete toDiscovery(discovery);
}

GBM_API int64_t gbm_discovery_add_base_folder(GbmDiscoveryHandle discovery,
                                              const char* path,
                                              int32_t maxDepth,
                                              int32_t followLinks) {
    DiscoveryState* state = toDiscovery(discovery);
    const GitResult<std::int64_t> result =
        state->db.addBaseFolder(path != nullptr ? path : "", maxDepth, followLinks != 0);
    if (!result) {
        setStagingBuffer(toJson(result.error()));
        return errorCodeOrdinal(result.error());
    }
    return result.value();
}

GBM_API int32_t gbm_discovery_scan_all(GbmDiscoveryHandle discovery) {
    DiscoveryState* state = toDiscovery(discovery);

    const GitResult<std::vector<BaseFolderRecord>> folders = state->db.baseFolders();
    if (!folders) {
        setStagingBuffer(toJson(folders.error()));
        return errorCodeOrdinal(folders.error());
    }

    Scanner scanner(state->db);
    const CancellationSource cancel;  // Synchronous scan: never actually cancelled.
    for (const BaseFolderRecord& folder : folders.value()) {
        if (!folder.enabled) {
            continue;
        }
        const GitResult<ScanResult> result =
            scanner.scan(folder, ScanMode::Incremental, cancel.token());
        if (!result) {
            setStagingBuffer(toJson(result.error()));
            return errorCodeOrdinal(result.error());
        }
    }
    return 0;
}

GBM_API int32_t gbm_discovery_list_repos_json(GbmDiscoveryHandle discovery) {
    DiscoveryState* state = toDiscovery(discovery);
    const GitResult<std::vector<RepoRecord>> records = state->db.repos(/*includeMissing=*/true);
    if (!records) {
        setStagingBuffer(toJson(records.error()));
        return errorCodeOrdinal(records.error());
    }
    setStagingBuffer(toJson(records.value()));
    return 0;
}

GBM_API int32_t gbm_discovery_base_folders_json(GbmDiscoveryHandle discovery) {
    DiscoveryState* state = toDiscovery(discovery);
    const GitResult<std::vector<BaseFolderRecord>> folders = state->db.baseFolders();
    if (!folders) {
        setStagingBuffer(toJson(folders.error()));
        return errorCodeOrdinal(folders.error());
    }
    setStagingBuffer(toJson(folders.value()));
    return 0;
}

GBM_API int32_t gbm_discovery_remove_base_folder(GbmDiscoveryHandle discovery,
                                                 int64_t baseFolderId) {
    DiscoveryState* state = toDiscovery(discovery);
    const GitResult<void> result = state->db.removeBaseFolder(baseFolderId);
    if (!result) {
        setStagingBuffer(toJson(result.error()));
        return errorCodeOrdinal(result.error());
    }
    return 0;
}

GBM_API int32_t gbm_discovery_set_base_folder_enabled(GbmDiscoveryHandle discovery,
                                                      int64_t baseFolderId,
                                                      int32_t enabled) {
    DiscoveryState* state = toDiscovery(discovery);
    const GitResult<void> result = state->db.setBaseFolderEnabled(baseFolderId, enabled != 0);
    if (!result) {
        setStagingBuffer(toJson(result.error()));
        return errorCodeOrdinal(result.error());
    }
    return 0;
}

GBM_API int32_t gbm_discovery_set_base_folder_depth(GbmDiscoveryHandle discovery,
                                                     int64_t baseFolderId,
                                                     int32_t maxDepth) {
    DiscoveryState* state = toDiscovery(discovery);
    const GitResult<void> result = state->db.setBaseFolderMaxDepth(baseFolderId, maxDepth);
    if (!result) {
        setStagingBuffer(toJson(result.error()));
        return errorCodeOrdinal(result.error());
    }
    return 0;
}
