#include "core/git/OperationLogScope.h"

#include "core/base/FsUtil.h"

#include <algorithm>

namespace gbm {

bool recordBelongsToSession(const std::string& recordRepoDir,
                            std::span<const std::filesystem::path> sessionDirs) {
    if (recordRepoDir.empty()) {
        return false;
    }
    const std::string key = fsutil::canonicalKey(fsutil::pathFromUtf8(recordRepoDir));
    return std::any_of(
        sessionDirs.begin(), sessionDirs.end(), [&](const std::filesystem::path& dir) {
            return fsutil::canonicalKey(dir) == key;
        });
}

}  // namespace gbm
