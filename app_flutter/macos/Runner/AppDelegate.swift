import Cocoa
import FlutterMacOS

// Not `@main`: main.swift is the entry point, so a launch by git as its
// askpass program can answer and exit before the application starts.
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
