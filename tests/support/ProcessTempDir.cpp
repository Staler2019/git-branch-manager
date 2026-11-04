#include "support/ProcessTempDir.h"

#include <cstdlib>
#include <system_error>

#ifdef _WIN32
#include <process.h>
#else
#include <unistd.h>
#endif

namespace gbm::testing {
namespace {

void pointTempAt(const std::filesystem::path& directory) {
#ifdef _WIN32
    // GetTempPath2 reads TMP first, then TEMP.
    _putenv_s("TMP", directory.string().c_str());
    _putenv_s("TEMP", directory.string().c_str());
#else
    setenv("TMPDIR", directory.string().c_str(), 1);
#endif
}

}  // namespace

std::string processTempDirName() {
#ifdef _WIN32
    return "gbm-proc-" + std::to_string(_getpid());
#else
    return "gbm-proc-" + std::to_string(getpid());
#endif
}

ProcessTempDir::ProcessTempDir()
    : previous_(std::filesystem::temp_directory_path()), own_(previous_ / processTempDirName()) {
    // A pid can come back after a crashed run left its directory behind.
    std::error_code ec;
    std::filesystem::remove_all(own_, ec);
    std::filesystem::create_directories(own_);
    pointTempAt(own_);
}

ProcessTempDir::~ProcessTempDir() {
    pointTempAt(previous_);
    std::error_code ec;
    std::filesystem::remove_all(own_, ec);
}

}  // namespace gbm::testing
