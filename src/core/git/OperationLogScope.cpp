#include "core/git/OperationLogScope.h"

#include "core/base/FsUtil.h"

#include <algorithm>
#include <optional>

namespace gbm {

bool recordBelongsToSession(const std::string& recordRepoDir,
                            std::span<const std::filesystem::path> sessionDirs) {
    if (recordRepoDir.empty()) {
        return false;
    }
    const std::filesystem::path recordDir = fsutil::pathFromUtf8(recordRepoDir);
    const std::string key = fsutil::canonicalKey(recordDir);
    if (std::any_of(sessionDirs.begin(), sessionDirs.end(), [&](const std::filesystem::path& dir) {
            return fsutil::canonicalKey(dir) == key;
        })) {
        return true;
    }
    // Same directory, different bytes: git reports a worktree by its resolved
    // path, while a session holds the one it was opened with (/var vs
    // /private/var on macOS, an 8.3 alias on Windows, a session opened through
    // a link to the repository itself). Only reached when no
    // string matched, so the common case costs no filesystem call.
    const std::optional<fsutil::FileId> recordId = fsutil::resolvedDirId(recordDir);
    if (!recordId) {
        return false;
    }
    return std::any_of(
        sessionDirs.begin(), sessionDirs.end(), [&](const std::filesystem::path& dir) {
            return fsutil::resolvedDirId(dir) == recordId;
        });
}

}  // namespace gbm
