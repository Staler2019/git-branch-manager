#include <dlfcn.h>
#include <unistd.h>

#include <climits>
#include <cstdlib>
#include <cstring>
#include <string>

#include "my_application.h"

namespace {

// git starts this app as its GIT_ASKPASS / SSH_ASKPASS program to ask the
// user for a credential (core's askpass::wire() points both at this very
// executable and sets GBM_ASKPASS_MODE=1). git then waits on our stdout, so
// that is answered here, before GTK starts: starting the GUI would leave git
// blocked on a second window that never writes. gbm_capi is not linked into
// the runner -- Dart opens it at run time -- so it is opened the same way:
// GBM_CAPI_LIBRARY_PATH, else next to this executable, where
// linux/CMakeLists.txt installs it (native_library.dart's candidates 1 and
// 2). Returns -1 for an ordinary launch.
int RunAskpassIfRequested(int argc, char** argv) {
  const char* mode = std::getenv("GBM_ASKPASS_MODE");
  if (mode == nullptr || std::strcmp(mode, "1") != 0) {
    return -1;
  }

  // No `if` initializers here: linux/CMakeLists.txt builds the runner as
  // C++14 (cxx_std_14), and CI's -Werror makes that extension an error.
  std::string library_path;
  const char* override_path = std::getenv("GBM_CAPI_LIBRARY_PATH");
  if (override_path != nullptr && *override_path != '\0') {
    library_path = override_path;
  } else {
    char executable[PATH_MAX];
    const ssize_t length =
        ::readlink("/proc/self/exe", executable, sizeof(executable) - 1);
    if (length <= 0) {
      return 1;
    }
    const std::string path(executable, static_cast<size_t>(length));
    library_path = path.substr(0, path.find_last_of('/') + 1) + "libgbm_capi.so";
  }

  // A credential git cannot get fails cleanly; it never falls through to
  // starting the GUI.
  void* library = ::dlopen(library_path.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (library == nullptr) {
    return 1;
  }
  using AskpassMain = int (*)(int, const char* const*);
  const auto askpass_main =
      reinterpret_cast<AskpassMain>(::dlsym(library, "gbm_askpass_main"));
  if (askpass_main == nullptr) {
    return 1;
  }
  const int code = askpass_main(argc, argv);
  return code >= 0 ? code : 1;
}

}  // namespace

int main(int argc, char** argv) {
  const int askpass_code = RunAskpassIfRequested(argc, argv);
  if (askpass_code >= 0) {
    return askpass_code;
  }

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
