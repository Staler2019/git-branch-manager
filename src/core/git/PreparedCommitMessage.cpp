#include "core/git/PreparedCommitMessage.h"

#include "core/base/FsUtil.h"

namespace gbm {

std::string readPreparedCommitMessage(const RepoPaths& paths) {
    if (auto mergeMsg = fsutil::readSmallFile(paths.mergeMsgFile())) {
        return *mergeMsg;
    }
    if (auto squashMsg = fsutil::readSmallFile(paths.squashMsgFile())) {
        return *squashMsg;
    }
    return std::string();
}

bool shouldApplyPreparedCommitMessage(const std::string& currentMessageBoxText,
                                       const std::string& lastAutofilledMessage) {
    return currentMessageBoxText.empty() || currentMessageBoxText == lastAutofilledMessage;
}

}  // namespace gbm
