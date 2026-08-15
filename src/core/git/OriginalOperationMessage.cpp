#include "core/git/OriginalOperationMessage.h"

#include "core/base/FsUtil.h"

#include <filesystem>
#include <fstream>

namespace gbm {

namespace {

void writeSmallFile(const std::filesystem::path& path, const std::string& contents) {
    std::filesystem::create_directories(path.parent_path());
    std::ofstream out(path, std::ios::binary | std::ios::trunc);
    out << contents;
}

}  // namespace

std::string readOriginalOperationMessage(const RepoPaths& paths) {
    if (auto rebaseMsg = fsutil::readSmallFile(paths.rebaseMergeMessageFile())) {
        return *rebaseMsg;
    }
    if (auto mergeMsg = fsutil::readSmallFile(paths.mergeMsgFile())) {
        return *mergeMsg;
    }
    return std::string();
}

void writeCherryPickContinueMessage(const RepoPaths& paths, const std::string& message) {
    writeSmallFile(paths.mergeMsgFile(), message);
}

void writeRebaseContinueMessage(const RepoPaths& paths, const std::string& message) {
    writeSmallFile(paths.rebaseMergeMessageFile(), message);
}

}  // namespace gbm
