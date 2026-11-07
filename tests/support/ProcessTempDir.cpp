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
    // An environment variable because gbm_capi holds its own copy of gbm_core on
    // Windows, and only this reaches that copy. Keeps tests out of the real home.
    const std::string logDir = (own_ / "native-error-logs").string();
#ifdef _WIN32
    _putenv_s("GBM_NATIVE_ERROR_LOG_DIR", logDir.c_str());
    // Read at crash time, by the library's filter too: a box nobody clicks would hold a
    // crashed test until its deadline.
    _putenv_s("GBM_CRASH_NO_DIALOG", "1");
#else
    setenv("GBM_NATIVE_ERROR_LOG_DIR", logDir.c_str(), 1);
#endif
}

ProcessTempDir::~ProcessTempDir() {
    pointTempAt(previous_);
    std::error_code ec;
    std::filesystem::remove_all(own_, ec);
}

}  // namespace gbm::testing
