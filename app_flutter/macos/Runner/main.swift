import Cocoa
import Darwin

/// git starts this app as its GIT_ASKPASS / SSH_ASKPASS program to ask the
/// user for a credential (core's askpass::wire() points both at this very
/// executable and sets GBM_ASKPASS_MODE=1). git then waits on our stdout, so
/// that has to be answered here, before NSApplicationMain: starting the GUI
/// would leave git blocked on a second window that never writes.
///
/// gbm_capi is not linked into the runner -- Dart opens it at run time -- so
/// it is opened the same way here: GBM_CAPI_LIBRARY_PATH, else next to this
/// executable, where the "Build gbm_capi" phase copies it
/// (native_library.dart's candidates 1 and 2). Returns nil when this is an
/// ordinary launch.
private func runAskpassIfRequested() -> Int32? {
  let environment = ProcessInfo.processInfo.environment
  guard environment["GBM_ASKPASS_MODE"] == "1" else { return nil }

  let libraryPath: String
  if let override = environment["GBM_CAPI_LIBRARY_PATH"], !override.isEmpty {
    libraryPath = override
  } else if let executable = Bundle.main.executableURL {
    libraryPath =
      executable.deletingLastPathComponent().appendingPathComponent("libgbm_capi.dylib").path
  } else {
    return 1
  }
  // A credential git cannot get fails cleanly; it never falls through to
  // starting the GUI.
  guard let library = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL),
    let symbol = dlsym(library, "gbm_askpass_main")
  else { return 1 }

  typealias AskpassMain = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>?>?) -> Int32
  let askpassMain = unsafeBitCast(symbol, to: AskpassMain.self)
  let argv = UnsafeRawPointer(CommandLine.unsafeArgv).assumingMemoryBound(
    to: UnsafePointer<CChar>?.self)
  let code = askpassMain(CommandLine.argc, argv)
  return code >= 0 ? code : 1
}

if let code = runAskpassIfRequested() {
  exit(code)
}
_ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
