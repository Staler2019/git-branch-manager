// A stand-in for the three desktop runners' start-up interception: when git
// launches the app as its GIT_ASKPASS / SSH_ASKPASS program, the runner must
// answer through stdout and exit *before* any GUI starts -- otherwise git
// waits on a second app window that never writes.
//
// Not a test. It does exactly what app_flutter/{macos,windows,linux}'s
// runners do -- check GBM_ASKPASS_MODE, load gbm_capi at run time (it is not
// linked, on purpose: the runners are not), call gbm_askpass_main -- and
// otherwise prints kGuiSentinel and exits 0, where a runner would start its
// engine. On Windows it is a GUI-subsystem program (WIN32 in CMake, entry
// wWinMain), because whether such a process can write to the stdout pipe git
// hands it is precisely what the Windows runner depends on.
//
// gbm_capi is looked for at GBM_CAPI_LIBRARY_PATH, else next to this
// executable -- the runners' own order (native_library.dart's candidates 1
// and 2).

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#ifdef _WIN32
#include <shellapi.h>
#include <windows.h>
#else
#include <climits>
#include <dlfcn.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <mach-o/dyld.h>
#endif
#endif

namespace {

constexpr const char* kGuiSentinel = "GBM-LAUNCHER-GUI-STARTED";

using AskpassMain = int (*)(int, const char* const*);

int startGui() {
    std::fputs(kGuiSentinel, stdout);
    std::fputc('\n', stdout);
    std::fflush(stdout);
    return 0;
}

#ifdef _WIN32

std::string utf8(const wchar_t* wide) {
    const int size = ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, nullptr, 0, nullptr, nullptr);
    std::string out(size > 0 ? size - 1 : 0, '\0');
    if (size > 1) {
        ::WideCharToMultiByte(CP_UTF8, 0, wide, -1, out.data(), size, nullptr, nullptr);
    }
    return out;
}

bool askpassMode() {
    wchar_t value[4] = {};
    const DWORD n = ::GetEnvironmentVariableW(L"GBM_ASKPASS_MODE", value, 4);
    return n == 1 && value[0] == L'1';
}

std::wstring libraryPath() {
    wchar_t buffer[32768];
    const DWORD n = ::GetEnvironmentVariableW(L"GBM_CAPI_LIBRARY_PATH", buffer, 32768);
    if (n > 0 && n < 32768) {
        return std::wstring(buffer, n);
    }
    const DWORD len = ::GetModuleFileNameW(nullptr, buffer, 32768);
    std::wstring exe(buffer, len);
    return exe.substr(0, exe.find_last_of(L"\\/") + 1) + L"gbm_capi.dll";
}

}  // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int) {
    if (!askpassMode()) {
        return startGui();
    }
    int argc = 0;
    wchar_t** wargv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
    std::vector<std::string> args;
    for (int i = 0; i < argc; ++i) {
        args.push_back(utf8(wargv[i]));
    }
    ::LocalFree(wargv);
    std::vector<const char*> argv;
    for (const auto& arg : args) {
        argv.push_back(arg.c_str());
    }
    const HMODULE lib =
        ::LoadLibraryExW(libraryPath().c_str(), nullptr, LOAD_WITH_ALTERED_SEARCH_PATH);
    if (lib == nullptr) {
        return 1;
    }
    const auto entry = reinterpret_cast<AskpassMain>(::GetProcAddress(lib, "gbm_askpass_main"));
    if (entry == nullptr) {
        return 1;
    }
    const int code = entry(static_cast<int>(argv.size()), argv.data());
    return code >= 0 ? code : 1;
}

#else

bool askpassMode() {
    const char* value = std::getenv("GBM_ASKPASS_MODE");
    return value != nullptr && std::strcmp(value, "1") == 0;
}

std::string libraryPath() {
    if (const char* override = std::getenv("GBM_CAPI_LIBRARY_PATH"); override && *override) {
        return override;
    }
    std::string exe;
#if defined(__APPLE__)
    char buffer[PATH_MAX];
    uint32_t size = sizeof(buffer);
    if (_NSGetExecutablePath(buffer, &size) == 0) {
        exe = buffer;
    }
    const char* name = "libgbm_capi.dylib";
#else
    char buffer[PATH_MAX];
    const ssize_t n = ::readlink("/proc/self/exe", buffer, sizeof(buffer) - 1);
    if (n > 0) {
        exe.assign(buffer, static_cast<std::size_t>(n));
    }
    const char* name = "libgbm_capi.so";
#endif
    return exe.substr(0, exe.find_last_of('/') + 1) + name;
}

}  // namespace

int main(int argc, char** argv) {
    if (!askpassMode()) {
        return startGui();
    }
    void* lib = ::dlopen(libraryPath().c_str(), RTLD_NOW | RTLD_LOCAL);
    if (lib == nullptr) {
        return 1;
    }
    const auto entry = reinterpret_cast<AskpassMain>(::dlsym(lib, "gbm_askpass_main"));
    if (entry == nullptr) {
        return 1;
    }
    const int code = entry(argc, argv);
    return code >= 0 ? code : 1;
}

#endif
