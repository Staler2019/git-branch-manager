#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <optional>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

// git starts this app as its GIT_ASKPASS / SSH_ASKPASS program to ask the
// user for a credential (core's askpass::wire() points both at this very
// executable and sets GBM_ASKPASS_MODE=1). git then waits on our stdout, so
// that is answered here, before the console, COM or any window exists:
// starting the GUI would leave git blocked on a second window that never
// writes. gbm_capi is not linked into the runner -- Dart opens it at run time
// -- so it is loaded the same way: GBM_CAPI_LIBRARY_PATH, else next to this
// executable (native_library.dart's candidates 1 and 2). std::nullopt means an
// ordinary launch.
std::optional<int> RunAskpassIfRequested() {
  wchar_t mode[4] = {};
  if (::GetEnvironmentVariableW(L"GBM_ASKPASS_MODE", mode, 4) != 1 ||
      mode[0] != L'1') {
    return std::nullopt;
  }

  std::vector<wchar_t> buffer(32768);
  std::wstring library_path;
  const DWORD override_length = ::GetEnvironmentVariableW(
      L"GBM_CAPI_LIBRARY_PATH", buffer.data(),
      static_cast<DWORD>(buffer.size()));
  if (override_length > 0 && override_length < buffer.size()) {
    library_path.assign(buffer.data(), override_length);
  } else {
    const DWORD length = ::GetModuleFileNameW(
        nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
    std::wstring executable(buffer.data(), length);
    library_path =
        executable.substr(0, executable.find_last_of(L"\\/") + 1) +
        L"gbm_capi.dll";
  }

  // A credential git cannot get fails cleanly; it never falls through to
  // starting the GUI.
  const HMODULE library = ::LoadLibraryExW(library_path.c_str(), nullptr,
                                           LOAD_WITH_ALTERED_SEARCH_PATH);
  if (library == nullptr) {
    return 1;
  }
  using AskpassMain = int(__cdecl*)(int, const char* const*);
  const auto askpass_main = reinterpret_cast<AskpassMain>(
      ::GetProcAddress(library, "gbm_askpass_main"));
  if (askpass_main == nullptr) {
    return 1;
  }

  // GetCommandLineArguments() leaves out the binary name; the entry point
  // expects a conventional argv with git's prompt at [1].
  std::vector<std::string> arguments{"git-branch-manager"};
  for (std::string& argument : GetCommandLineArguments()) {
    arguments.push_back(std::move(argument));
  }
  std::vector<const char*> argv;
  for (const std::string& argument : arguments) {
    argv.push_back(argument.c_str());
  }
  const int code = askpass_main(static_cast<int>(argv.size()), argv.data());
  return code >= 0 ? code : 1;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  if (const std::optional<int> askpass_code = RunAskpassIfRequested()) {
    return *askpass_code;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"git-branch-manager", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
