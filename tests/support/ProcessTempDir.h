#pragma once

#include <filesystem>
#include <string>

namespace gbm::testing {

/// The directory name that holds this process's temporary files.
std::string processTempDirName();

/// Points the system temp directory at a directory private to this process, for
/// its lifetime and for every child it spawns, then removes it.
///
/// Done here rather than at the ~60 `temp_directory_path()` call sites so a new
/// fixture cannot forget it.
class ProcessTempDir {
public:
    ProcessTempDir();
    ~ProcessTempDir();

    ProcessTempDir(const ProcessTempDir&) = delete;
    ProcessTempDir& operator=(const ProcessTempDir&) = delete;

private:
    std::filesystem::path previous_;
    std::filesystem::path own_;
};

}  // namespace gbm::testing
