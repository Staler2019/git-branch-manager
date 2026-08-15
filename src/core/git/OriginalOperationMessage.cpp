#include "core/git/OriginalOperationMessage.h"

#include "core/base/FsUtil.h"

namespace gbm {

std::string readOriginalOperationMessage(const RepoPaths& paths) {
    if (auto rebaseMsg = fsutil::readSmallFile(paths.rebaseMergeMessageFile())) {
        return *rebaseMsg;
    }
    if (auto mergeMsg = fsutil::readSmallFile(paths.mergeMsgFile())) {
        return *mergeMsg;
    }
    return std::string();
}

}  // namespace gbm
