// The Windows crash filter as the app gets it: gbm_crash_now loads the real gbm_capi.dll,
// whose load-time initializer installs the filter, and then crashes. Nothing here installs a
// filter itself, so this goes red if the library stops installing one.
#include "core/base/ExceptionDiagnostic.h"

#include <gtest/gtest.h>

#if defined(_WIN32)
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <windows.h>

namespace gbm {
namespace {

std::string readFile(const std::filesystem::path& path) {
    std::ifstream in(path, std::ios::binary);
    std::ostringstream text;
    text << in.rdbuf();
    return text.str();
}

std::size_t countOf(const std::string& text, const std::string& needle) {
    std::size_t count = 0;
    for (std::size_t at = text.find(needle); at != std::string::npos;
         at = text.find(needle, at + 1)) {
        ++count;
    }
    return count;
}

TEST(CrashFilterApiTest, ACrashIsLoggedOnceByNameAndHandedOnToTheEarlierFilter) {
    const std::filesystem::path log = nativeErrorLogPath();
    const std::filesystem::path marker = std::filesystem::temp_directory_path() / "crash-marker";
    std::error_code ec;
    std::filesystem::remove(log, ec);
    std::filesystem::remove(marker, ec);
    ASSERT_TRUE(::SetEnvironmentVariableW(L"GBM_CRASH_MARKER", marker.c_str()));
    ASSERT_TRUE(::SetEnvironmentVariableW(L"GBM_CRASH_LOG", log.c_str()));
    ASSERT_TRUE(::SetEnvironmentVariableW(L"GBM_CAPI_LIBRARY_PATH",
                                          std::filesystem::path(GBM_CAPI_LIBRARY_FILE).c_str()));

    std::wstring command = L"\"" + std::filesystem::path(GBM_CRASH_NOW_EXE).wstring() + L"\"";
    STARTUPINFOW startup{};
    startup.cb = sizeof startup;
    PROCESS_INFORMATION child{};
    ASSERT_TRUE(::CreateProcessW(
        nullptr, command.data(), nullptr, nullptr, FALSE, 0, nullptr, nullptr, &startup, &child));
    // A box nobody can click would hold it here.
    const DWORD waited = ::WaitForSingleObject(child.hProcess, 30000);
    if (waited != WAIT_OBJECT_0) {
        ::TerminateProcess(child.hProcess, 1);
    }
    DWORD exitCode = 0;
    ::GetExitCodeProcess(child.hProcess, &exitCode);
    ::CloseHandle(child.hThread);
    ::CloseHandle(child.hProcess);
    ASSERT_EQ(waited, WAIT_OBJECT_0) << "the child is still running after 30 s";

    const std::string text = readFile(log);
    EXPECT_EQ(countOf(text, "unhandled SEH exception"), 1u) << text;
    EXPECT_NE(text.find("code=0xc0000005"), std::string::npos) << text;
    const std::size_t module = text.find("module=");
    ASSERT_NE(module, std::string::npos) << text;
    const std::size_t plus = text.find('+', module);
    ASSERT_NE(plus, std::string::npos) << text;
    EXPECT_EQ(text.substr(module + 7, plus - module - 7), "gbm_crash_now.exe") << text;
    EXPECT_EQ(readFile(marker), "after") << "the earlier filter ran, after the line was written";
    // A sanity check only: the process dies with the crash code whether or not the filter
    // hands on, so this cannot tell chaining apart.
    EXPECT_EQ(exitCode, 0xC0000005u);
}

}  // namespace
}  // namespace gbm
#endif
