#include "core/git/PreparedCommitMessage.h"

#include "core/base/FsUtil.h"

namespace gbm {

std::string readPreparedCommitMessage(const RepoPaths& paths) {
    // git's own order (`git commit` reads SQUASH_MSG, then appends MERGE_MSG).
    std::string message;
    if (auto squashMsg = fsutil::readSmallFile(paths.squashMsgFile())) {
        message += *squashMsg;
    }
    if (auto mergeMsg = fsutil::readSmallFile(paths.mergeMsgFile())) {
        message += *mergeMsg;
    }
    return message;
}

}  // namespace gbm
