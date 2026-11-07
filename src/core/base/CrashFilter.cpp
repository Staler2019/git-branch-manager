#include "core/base/CrashFilter.h"

#if defined(_WIN32)
#include "core/base/ExceptionDiagnostic.h"

#include <atomic>
#include <cstdio>
#include <cwchar>
#include <filesystem>
#include <string>
#include <thread>
#include <windows.h>
#endif

namespace gbm {

namespace {
constexpr std::uint32_t kStackOverflow = 0xC00000FDu;
}  // namespace

bool shouldShowCrashDialog(std::uint32_t code,
                           bool askpass,
                           bool noDialog,
                           bool anyVisibleWindow) noexcept {
    return !askpass && !noDialog && !anyVisibleWindow && code != kStackOverflow;
}

#if defined(_WIN32)

namespace {

// Every buffer the filter touches is static: it may run on an overflowed stack and must
// not allocate, since the faulting thread can hold the heap lock.
constexpr DWORD kPathChars = 32768;
wchar_t g_logPath[kPathChars];
wchar_t g_logDirectory[kPathChars];
wchar_t g_logDirectoryParent[kPathChars];
wchar_t g_modulePath[kPathChars];
wchar_t g_message[kPathChars + 256];
wchar_t g_env[8];
char g_module[MAX_PATH * 3];
char g_line[MAX_PATH * 3 + 256];

LPTOP_LEVEL_EXCEPTION_FILTER g_previous = nullptr;
std::atomic<bool> g_entered{false};
HANDLE g_showRequest = nullptr;
HANDLE g_closed = nullptr;
std::atomic<DWORD> g_dialogThreadId{0};

bool copyPath(const std::filesystem::path& path, wchar_t* out) {
    const std::wstring& text = path.native();
    if (text.empty() || text.size() >= kPathChars) {
        out[0] = L'\0';
        return false;
    }
    std::wmemcpy(out, text.c_str(), text.size() + 1);
    return true;
}

bool envIs(const wchar_t* name, wchar_t value) {
    const DWORD length = ::GetEnvironmentVariableW(name, g_env, 8);
    return length == 1 && g_env[0] == value;
}

BOOL CALLBACK findVisibleWindow(HWND window, LPARAM found) {
    DWORD process = 0;
    ::GetWindowThreadProcessId(window, &process);
    if (process == ::GetCurrentProcessId() && ::IsWindowVisible(window)) {
        *reinterpret_cast<bool*>(found) = true;
        return FALSE;
    }
    return TRUE;
}

bool anyVisibleWindow() {
    bool found = false;
    ::EnumWindows(&findVisibleWindow, reinterpret_cast<LPARAM>(&found));
    return found;
}

BOOL CALLBACK findDialogWindow(HWND window, LPARAM found) {
    if (::IsWindowVisible(window)) {
        *reinterpret_cast<bool*>(found) = true;
        return FALSE;
    }
    return TRUE;
}

bool dialogIsOnScreen() {
    bool found = false;
    ::EnumThreadWindows(g_dialogThreadId, &findDialogWindow, reinterpret_cast<LPARAM>(&found));
    return found;
}

/// The faulting module's file name and offset, never its directory: that names the user.
void describeModule(const void* address, std::uintptr_t& offset) {
    HMODULE module = nullptr;
    offset = 0;
    g_module[0] = '\0';
    if (!::GetModuleHandleExW(
            GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
            static_cast<LPCWSTR>(address),
            &module) ||
        ::GetModuleFileNameW(module, g_modulePath, kPathChars) == 0) {
        std::snprintf(g_module, sizeof g_module, "unknown");
        return;
    }
    const wchar_t* name = g_modulePath;
    for (const wchar_t* c = g_modulePath; *c != L'\0'; ++c) {
        if (*c == L'\\' || *c == L'/') {
            name = c + 1;
        }
    }
    const int written = ::WideCharToMultiByte(
        CP_UTF8, 0, name, -1, g_module, static_cast<int>(sizeof g_module), nullptr, nullptr);
    if (written <= 0) {
        std::snprintf(g_module, sizeof g_module, "unknown");
        return;
    }
    for (char* c = g_module; *c != '\0'; ++c) {
        if (static_cast<unsigned char>(*c) < 0x20 || *c == 0x7F) {
            *c = '?';
        }
    }
    offset = reinterpret_cast<std::uintptr_t>(address) - reinterpret_cast<std::uintptr_t>(module);
}

void writeLine(DWORD code, const void* address) {
    if (g_logPath[0] == L'\0') {
        return;
    }
    ::CreateDirectoryW(g_logDirectoryParent, nullptr);
    ::CreateDirectoryW(g_logDirectory, nullptr);
    std::uintptr_t offset = 0;
    describeModule(address, offset);
    SYSTEMTIME now{};
    ::GetSystemTime(&now);
    const char* where = envIs(L"GBM_ASKPASS_MODE", L'1') ? "askpass: unhandled SEH exception"
                                                         : "unhandled SEH exception";
    const int length = std::snprintf(g_line,
                                     sizeof g_line,
                                     "%04u-%02u-%02uT%02u:%02u:%02u.%03uZ thread %lu %s: "
                                     "code=0x%08lx module=%s+0x%llx\n",
                                     now.wYear,
                                     now.wMonth,
                                     now.wDay,
                                     now.wHour,
                                     now.wMinute,
                                     now.wSecond,
                                     now.wMilliseconds,
                                     ::GetCurrentThreadId(),
                                     where,
                                     code,
                                     g_module,
                                     static_cast<unsigned long long>(offset));
    if (length <= 0) {
        return;
    }
    // Append-only, shared with an ordinary report the main or askpass process is writing.
    const HANDLE file = ::CreateFileW(g_logPath,
                                      FILE_APPEND_DATA,
                                      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                      nullptr,
                                      OPEN_ALWAYS,
                                      FILE_ATTRIBUTE_NORMAL,
                                      nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        return;
    }
    DWORD written = 0;
    const DWORD bytes =
        static_cast<DWORD>(length < static_cast<int>(sizeof g_line) ? length : sizeof g_line - 1);
    ::WriteFile(file, g_line, bytes, &written, nullptr);
    ::CloseHandle(file);
}

/// Shown from its own thread: MessageBoxW pumps messages, and on the faulting thread that
/// would re-enter whatever crashed.
void showDialog(DWORD code) {
    // The helper may not have run yet when the crash follows the load at once; the request
    // waits for it, and the loop below gives it the same 5 s.
    if (g_showRequest == nullptr) {
        return;
    }
    std::swprintf(g_message,
                  sizeof g_message / sizeof g_message[0],
                  L"git-branch-manager stopped unexpectedly (0x%08lX).\n\nDetails were saved "
                  L"to:\n%ls",
                  code,
                  g_logPath[0] != L'\0' ? g_logPath : L"(no log location)");
    ::SetEvent(g_showRequest);
    // A box that never appears (the faulting thread holds a lock it needs) must not keep a
    // dead process alive; one that did appear waits for the user.
    for (int waited = 0; waited < 50; ++waited) {
        if (dialogIsOnScreen()) {
            ::WaitForSingleObject(g_closed, INFINITE);
            return;
        }
        if (::WaitForSingleObject(g_closed, 100) == WAIT_OBJECT_0) {
            return;
        }
    }
}

LONG WINAPI crashFilter(EXCEPTION_POINTERS* pointers) {
    if (!g_entered.exchange(true)) {
        const DWORD code = pointers != nullptr && pointers->ExceptionRecord != nullptr
                               ? pointers->ExceptionRecord->ExceptionCode
                               : 0;
        const void* address = pointers != nullptr && pointers->ExceptionRecord != nullptr
                                  ? pointers->ExceptionRecord->ExceptionAddress
                                  : nullptr;
        writeLine(code, address);
        if (shouldShowCrashDialog(code,
                                  envIs(L"GBM_ASKPASS_MODE", L'1'),
                                  envIs(L"GBM_CRASH_NO_DIALOG", L'1'),
                                  code == kStackOverflow || anyVisibleWindow())) {
            showDialog(code);
        }
    }
    return g_previous != nullptr ? g_previous(pointers) : EXCEPTION_CONTINUE_SEARCH;
}

}  // namespace

void installCrashFilter() noexcept {
    try {
        const std::filesystem::path log = nativeErrorLogPath();
        if (copyPath(log, g_logPath)) {
            copyPath(log.parent_path(), g_logDirectory);
            copyPath(log.parent_path().parent_path(), g_logDirectoryParent);
        }
        g_showRequest = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
        g_closed = ::CreateEventW(nullptr, TRUE, FALSE, nullptr);
        if (g_showRequest != nullptr && g_closed != nullptr) {
            // Started now, while nothing is wrong; under the loader lock it only begins
            // running once the library has finished loading.
            guardedThread(
                "crash dialog",
                [] {
                    g_dialogThreadId = ::GetCurrentThreadId();
                    ::WaitForSingleObject(g_showRequest, INFINITE);
                    ::MessageBoxW(nullptr,
                                  g_message,
                                  L"git-branch-manager",
                                  MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
                    ::SetEvent(g_closed);
                },
                [] {})
                .detach();
        }
    } catch (...) {
        reportCurrentException("installCrashFilter");
    }
    g_previous = ::SetUnhandledExceptionFilter(&crashFilter);
}

#else

void installCrashFilter() noexcept {}

#endif

}  // namespace gbm
