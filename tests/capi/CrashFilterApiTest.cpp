// The Windows crash filter as the app gets it: gbm_crash_now loads the real gbm_capi.dll,
// whose load-time initializer installs the filter, and then crashes. Nothing here installs a
// filter itself, so this goes red if the library stops installing one.
#include "core/base/ExceptionDiagnostic.h"

#include <gtest/gtest.h>

#if defined(_WIN32)
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <initializer_list>
#include <optional>
#include <sstream>
#include <string>
#include <utility>
#include <vector>
#include <windows.h>

namespace gbm {
namespace {

using EnvOverride = std::pair<const wchar_t*, const wchar_t*>;

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

/// Sets variables for the child, which inherits this process's block, and puts them back.
class EnvScope {
public:
    explicit EnvScope(std::initializer_list<EnvOverride> overrides) {
        for (const auto& [name, value] : overrides) {
            std::optional<std::wstring> previous;
            const DWORD length = ::GetEnvironmentVariableW(name, nullptr, 0);
            if (length > 0) {
                std::wstring text(length, L'\0');
                text.resize(::GetEnvironmentVariableW(name, text.data(), length));
                previous = text;
            }
            saved_.emplace_back(name, previous);
            ::SetEnvironmentVariableW(name, value);
        }
    }
    ~EnvScope() {
        for (const auto& [name, previous] : saved_) {
            ::SetEnvironmentVariableW(name, previous ? previous->c_str() : nullptr);
        }
    }
    EnvScope(const EnvScope&) = delete;
    EnvScope& operator=(const EnvScope&) = delete;

private:
    std::vector<std::pair<const wchar_t*, std::optional<std::wstring>>> saved_;
};

/// One crash of gbm_crash_now against a fresh log and marker.
class CrashRun {
public:
    CrashRun(const wchar_t* mode, std::initializer_list<EnvOverride> env)
        : log_(nativeErrorLogPath()),
          marker_(std::filesystem::temp_directory_path() / "crash-marker") {
        std::error_code ec;
        std::filesystem::remove(log_, ec);
        std::filesystem::remove(marker_, ec);
        std::filesystem::remove(stackLeftPath(), ec);
        const std::wstring library = std::filesystem::path(GBM_CAPI_LIBRARY_FILE).wstring();
        const EnvScope scope{{L"GBM_CRASH_MARKER", marker_.c_str()},
                             {L"GBM_CRASH_LOG", log_.c_str()},
                             {L"GBM_CAPI_LIBRARY_PATH", library.c_str()}};
        const EnvScope extra(env);
        std::wstring command = L"\"" + std::filesystem::path(GBM_CRASH_NOW_EXE).wstring() + L"\"";
        if (mode != nullptr) {
            command += L" ";
            command += mode;
        }
        STARTUPINFOW startup{};
        startup.cb = sizeof startup;
        started_ = ::CreateProcessW(nullptr,
                                    command.data(),
                                    nullptr,
                                    nullptr,
                                    FALSE,
                                    0,
                                    nullptr,
                                    nullptr,
                                    &startup,
                                    &child_) != FALSE;
    }
    ~CrashRun() {
        if (!started_) {
            return;
        }
        if (::WaitForSingleObject(child_.hProcess, 0) != WAIT_OBJECT_0) {
            ::TerminateProcess(child_.hProcess, 1);
            ::WaitForSingleObject(child_.hProcess, 5000);
        }
        ::CloseHandle(child_.hThread);
        ::CloseHandle(child_.hProcess);
    }
    CrashRun(const CrashRun&) = delete;
    CrashRun& operator=(const CrashRun&) = delete;

    bool started() const { return started_; }
    bool exitsWithin(DWORD milliseconds) const {
        return ::WaitForSingleObject(child_.hProcess, milliseconds) == WAIT_OBJECT_0;
    }
    std::string log() const { return readFile(log_); }
    std::string marker() const { return readFile(marker_); }
    bool markerExists() const { return std::filesystem::exists(marker_); }
    std::wstring logPath() const { return log_.wstring(); }

    /// What a failure needs to say which fault ended the child: 0xC00000FD alone is the
    /// overflow; anything else is a fault while handling it. `stack left` is what the
    /// earlier filter still had, empty when it never ran.
    std::string describeExit() const {
        DWORD code = 0;
        ::GetExitCodeProcess(child_.hProcess, &code);
        char hex[16];
        std::snprintf(hex, sizeof hex, "0x%08lX", code);
        return std::string("exit code ") + hex + ", marker " +
               (markerExists() ? "\"" + marker() + "\"" : std::string("missing")) +
               ", stack left " + readFile(stackLeftPath());
    }

    /// The child's visible message box, polled for up to `milliseconds`.
    HWND waitForDialog(DWORD milliseconds) const {
        for (DWORD waited = 0; waited < milliseconds; waited += 100) {
            if (const HWND dialog = findDialog(); dialog != nullptr) {
                return dialog;
            }
            if (exitsWithin(100)) {
                return findDialog();
            }
        }
        return findDialog();
    }

private:
    struct Search {
        DWORD process;
        HWND found;
    };

    static BOOL CALLBACK matchDialog(HWND window, LPARAM search) {
        auto& wanted = *reinterpret_cast<Search*>(search);
        DWORD process = 0;
        ::GetWindowThreadProcessId(window, &process);
        wchar_t type[16] = {};
        ::GetClassNameW(window, type, 16);
        if (process == wanted.process && std::wstring(type) == L"#32770" &&
            ::IsWindowVisible(window)) {
            wanted.found = window;
            return FALSE;
        }
        return TRUE;
    }

    HWND findDialog() const {
        Search search{child_.dwProcessId, nullptr};
        ::EnumWindows(&matchDialog, reinterpret_cast<LPARAM>(&search));
        return search.found;
    }

    std::filesystem::path stackLeftPath() const {
        std::filesystem::path path = marker_;
        path += ".left";
        return path;
    }

    std::filesystem::path log_;
    std::filesystem::path marker_;
    PROCESS_INFORMATION child_{};
    bool started_ = false;
};

std::wstring windowText(HWND window) {
    wchar_t text[4096] = {};
    ::GetWindowTextW(window, text, 4096);
    return text;
}

/// A message box's body is its static control, whose id is 0xFFFF.
std::wstring dialogBody(HWND dialog) {
    wchar_t text[4096] = {};
    ::GetDlgItemTextW(dialog, 0xFFFF, text, 4096);
    return text;
}

TEST(CrashFilterApiTest, ACrashIsLoggedOnceByNameAndHandedOnToTheEarlierFilter) {
    const CrashRun run(nullptr, {});
    ASSERT_TRUE(run.started());
    // A box nobody can click would hold it here.
    ASSERT_TRUE(run.exitsWithin(30000)) << "the child is still running after 30 s";

    const std::string text = run.log();
    EXPECT_EQ(countOf(text, "unhandled SEH exception"), 1u) << text;
    EXPECT_NE(text.find("code=0xc0000005"), std::string::npos) << text;
    const std::size_t module = text.find("module=");
    ASSERT_NE(module, std::string::npos) << text;
    const std::size_t plus = text.find('+', module);
    ASSERT_NE(plus, std::string::npos) << text;
    EXPECT_EQ(text.substr(module + 7, plus - module - 7), "gbm_crash_now.exe") << text;
    EXPECT_EQ(run.marker(), "after") << "the earlier filter ran, after the line was written";
}

TEST(CrashFilterApiTest, WithNoWindowABoxNamesTheCodeAndTheLogAndOkLetsTheProcessGo) {
    const CrashRun run(nullptr, {{L"GBM_CRASH_NO_DIALOG", nullptr}});
    ASSERT_TRUE(run.started());

    const HWND dialog = run.waitForDialog(15000);
    ASSERT_NE(dialog, nullptr) << "no box within 15 s; log: " << run.log();
    EXPECT_EQ(windowText(dialog), L"git-branch-manager");
    const std::wstring body = dialogBody(dialog);
    EXPECT_NE(body.find(L"stopped unexpectedly (0xC0000005)"), std::wstring::npos);
    EXPECT_NE(body.find(run.logPath()), std::wstring::npos) << "the box names the log file";
    EXPECT_EQ(countOf(run.log(), "unhandled SEH exception"), 1u) << "written before the box";
    EXPECT_FALSE(run.markerExists()) << "the earlier filter runs only after the box closes";
    EXPECT_FALSE(run.exitsWithin(500)) << "the box holds the process until it is answered";

    const HWND ok = ::FindWindowExW(dialog, nullptr, L"Button", nullptr);
    ASSERT_NE(ok, nullptr);
    // The caption follows the system's UI language (「確定」 on zh-TW); the button's count and
    // id do not. MB_OK's lone button is IDCANCEL (2), measured, so Esc closes the box too;
    // MB_OKCANCEL would show two buttons and MB_YESNO would start at IDYES.
    EXPECT_EQ(::FindWindowExW(dialog, ok, L"Button", nullptr), nullptr) << "MB_OK: one button";
    const int id = ::GetDlgCtrlID(ok);
    EXPECT_EQ(id, IDCANCEL);
    ::PostMessageW(dialog, WM_COMMAND, MAKEWPARAM(id, BN_CLICKED), reinterpret_cast<LPARAM>(ok));
    ASSERT_TRUE(run.exitsWithin(15000))
        << "OK (id " << id
        << ") did not let the process go; box still there: " << (::IsWindow(dialog) != FALSE)
        << ", marker: " << run.markerExists();
    EXPECT_EQ(run.marker(), "after");
}

TEST(CrashFilterApiTest, ABoxStillAppearsWhenTheCrashComesBeforeItsThreadHasRun) {
    const CrashRun run(L"--at-once", {{L"GBM_CRASH_NO_DIALOG", nullptr}});
    ASSERT_TRUE(run.started());

    const HWND dialog = run.waitForDialog(15000);
    ASSERT_NE(dialog, nullptr) << "no box within 15 s; log: " << run.log();
    const HWND ok = ::FindWindowExW(dialog, nullptr, L"Button", nullptr);
    ASSERT_NE(ok, nullptr);
    ::PostMessageW(dialog,
                   WM_COMMAND,
                   MAKEWPARAM(::GetDlgCtrlID(ok), BN_CLICKED),
                   reinterpret_cast<LPARAM>(ok));
    EXPECT_TRUE(run.exitsWithin(15000));
}

TEST(CrashFilterApiTest, ABoxThatNeverAppearsHoldsTheProcessForSecondsNotForever) {
    const ULONGLONG start = ::GetTickCount64();
    const CrashRun run(L"--box-thread-stalled", {{L"GBM_CRASH_NO_DIALOG", nullptr}});
    ASSERT_TRUE(run.started());

    ASSERT_TRUE(run.exitsWithin(15000)) << "still waiting on a box that cannot appear";
    EXPECT_GE(::GetTickCount64() - start, 4000u) << "it gave the box its 5 s";
    EXPECT_EQ(countOf(run.log(), "unhandled SEH exception"), 1u) << run.log();
    EXPECT_EQ(run.marker(), "after");
}

TEST(CrashFilterApiTest, NoBoxWhenTheProcessAlreadyShowsAWindow) {
    const CrashRun run(L"--window", {{L"GBM_CRASH_NO_DIALOG", nullptr}});
    ASSERT_TRUE(run.started());

    ASSERT_TRUE(run.exitsWithin(15000)) << "a box held the process";
    EXPECT_EQ(countOf(run.log(), "unhandled SEH exception"), 1u) << run.log();
    EXPECT_EQ(run.marker(), "after");
}

TEST(CrashFilterApiTest, NoBoxInTheAskpassHelperAndItsLineSaysSo) {
    const CrashRun run(nullptr, {{L"GBM_CRASH_NO_DIALOG", nullptr}, {L"GBM_ASKPASS_MODE", L"1"}});
    ASSERT_TRUE(run.started());

    ASSERT_TRUE(run.exitsWithin(15000)) << "a box held the process";
    const std::string text = run.log();
    EXPECT_EQ(countOf(text, "askpass: unhandled SEH exception"), 1u) << text;
}

TEST(CrashFilterApiTest, AStackOverflowIsLoggedWithNoBox) {
    const CrashRun run(L"--stack-overflow", {{L"GBM_CRASH_NO_DIALOG", nullptr}});
    ASSERT_TRUE(run.started());

    ASSERT_TRUE(run.exitsWithin(15000)) << "a box held the process";
    const std::string text = run.log();
    EXPECT_EQ(countOf(text, "unhandled SEH exception"), 1u) << text << "\n" << run.describeExit();
    EXPECT_NE(text.find("code=0xc00000fd"), std::string::npos) << text << "\n"
                                                               << run.describeExit();
    EXPECT_EQ(run.marker(), "after") << run.describeExit();
}

}  // namespace
}  // namespace gbm
#endif
