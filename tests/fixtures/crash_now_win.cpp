// Not a test: the subject of CrashFilterApiTest. It installs no crash filter of its own. It
// puts a sentinel filter in place, loads gbm_capi as the runner's Dart side does, which
// installs the library's filter over the sentinel, and then writes through a null pointer.
// The sentinel runs only if the library's filter hands on to it, and it records whether the
// library's line was already in the log by then.
//
// `--window` shows a window of its own first; `--stack-overflow` overflows the stack instead
// of writing through a null pointer.
#include <cstring>
#include <cwchar>
#include <windows.h>

namespace {

wchar_t g_marker[32768];
wchar_t g_log[32768];
char g_logText[1 << 16];

LONG WINAPI sentinel(EXCEPTION_POINTERS*) {
    bool lineWritten = false;
    const HANDLE log = ::CreateFileW(g_log,
                                     GENERIC_READ,
                                     FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                                     nullptr,
                                     OPEN_EXISTING,
                                     FILE_ATTRIBUTE_NORMAL,
                                     nullptr);
    if (log != INVALID_HANDLE_VALUE) {
        DWORD read = 0;
        ::ReadFile(log, g_logText, sizeof g_logText - 1, &read, nullptr);
        g_logText[read] = '\0';
        lineWritten = std::strstr(g_logText, "unhandled SEH exception") != nullptr;
        ::CloseHandle(log);
    }
    const HANDLE marker = ::CreateFileW(
        g_marker, GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (marker != INVALID_HANDLE_VALUE) {
        const char* text = lineWritten ? "after" : "before";
        DWORD written = 0;
        ::WriteFile(marker, text, static_cast<DWORD>(std::strlen(text)), &written, nullptr);
        ::CloseHandle(marker);
    }
    return EXCEPTION_CONTINUE_SEARCH;
}

volatile bool g_keepGoing = true;

__declspec(noinline) int recurse(int depth) {
    volatile char pad[4096];
    pad[0] = static_cast<char>(depth);
    return g_keepGoing ? recurse(depth + 1) + pad[0] : pad[0];
}

void showWindow() {
    WNDCLASSW type{};
    type.lpfnWndProc = &::DefWindowProcW;
    type.hInstance = ::GetModuleHandleW(nullptr);
    type.lpszClassName = L"gbm_crash_now";
    ::RegisterClassW(&type);
    const HWND window = ::CreateWindowExW(0,
                                          type.lpszClassName,
                                          L"gbm_crash_now",
                                          WS_OVERLAPPEDWINDOW,
                                          0,
                                          0,
                                          200,
                                          100,
                                          nullptr,
                                          nullptr,
                                          type.hInstance,
                                          nullptr);
    ::ShowWindow(window, SW_SHOWNOACTIVATE);
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
    const bool window = argc > 1 && std::wcscmp(argv[1], L"--window") == 0;
    const bool overflow = argc > 1 && std::wcscmp(argv[1], L"--stack-overflow") == 0;
    // No Windows Error Reporting dialog to sit on the CI machine.
    ::SetErrorMode(SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX);
    wchar_t library[32768];
    if (::GetEnvironmentVariableW(L"GBM_CRASH_MARKER", g_marker, 32768) == 0 ||
        ::GetEnvironmentVariableW(L"GBM_CRASH_LOG", g_log, 32768) == 0 ||
        ::GetEnvironmentVariableW(L"GBM_CAPI_LIBRARY_PATH", library, 32768) == 0) {
        return 2;
    }
    ::SetUnhandledExceptionFilter(&sentinel);
    if (::LoadLibraryExW(library, nullptr, LOAD_WITH_ALTERED_SEARCH_PATH) == nullptr) {
        return 3;
    }
    if (window) {
        showWindow();
    }
    if (overflow) {
        return recurse(0);
    }
    volatile int* nowhere = nullptr;
    *nowhere = 1;
    return 0;
}
