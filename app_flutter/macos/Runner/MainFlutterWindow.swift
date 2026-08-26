import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Spec page 01 keeps the native title bar on every platform (「標題列按鈕
    // 位置與號誌燈樣式沿用系統原生」) and all three of its mockup cards title
    // the window `git-branch-manager`.
    //
    // Set here rather than through PRODUCT_NAME: that xcconfig value is also
    // the built artifact's name, and release.yml hardcodes `gbm_flutter.app`
    // paths, so renaming it would break packaging.
    //
    // The deferred assignment is not cargo cult -- it was measured. Setting
    // the title synchronously here (and in MainMenu.xib, and in
    // AppDelegate.applicationDidFinishLaunching) is silently reverted to
    // CFBundleName by the time the window is on screen; only an assignment
    // on the next main-queue turn survives. The xib below carries the same
    // string so the two sources can never disagree, but the xib alone is
    // not enough.
    //
    // That revert used to land on `gbm_flutter` and is now harmless on its
    // own: #67 made Info.plist's CFBundleName the literal
    // `git-branch-manager` too, so the two strings currently agree. They
    // agree by coincidence, not by construction -- CFBundleName is the
    // *application* name (Apple menu, About panel, Dock) and this is the
    // *window* title, and nothing keeps them in step. Deleting the line
    // below because "the revert lands on the right value anyway" would
    // silently couple them.
    self.title = "git-branch-manager"
    DispatchQueue.main.async { self.title = "git-branch-manager" }

    super.awakeFromNib()
  }
}
