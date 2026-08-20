import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Spec page 01 puts the window title bar in the "platform-specific" list --
/// 「標題列按鈕位置與號誌燈樣式沿用系統原生」-- so this app deliberately keeps
/// each OS's native decorations rather than drawing its own chrome. What the
/// spec's three page-01 mockup cards *do* agree on is the title *text*:
/// `git-branch-manager` on macOS, Windows and Linux alike.
///
/// Each platform sets that string in native runner code, which no widget or
/// integration test can reach -- `MaterialApp.title` (`lib/app.dart`) does not
/// propagate to the OS window title on desktop. Without these assertions
/// nothing would notice the string regressing: a `flutter create` re-scaffold
/// or a copy-pasted runner file would silently restore the `gbm_flutter`
/// default, and only the Linux file is even compiled by PR CI (`ci.yml`'s
/// Flutter job is ubuntu-only; Windows builds exist solely in `release.yml`,
/// on tag).
///
/// Asserting on source text rather than on behaviour has a precedent in this
/// repo: `cq.yml`'s pin-check step greps the workflow files themselves for the
/// same class of "nothing else can see this regress" reason.
void main() {
  const String expectedTitle = 'git-branch-manager';
  const String scaffoldDefault = 'gbm_flutter';

  /// Reads a path relative to the Flutter package root. `flutter test` runs
  /// with the package root as its working directory; the explicit existence
  /// check turns a wrong cwd into a legible failure instead of an empty-string
  /// mismatch further down.
  String readRunnerSource(String relativePath) {
    final File file = File(relativePath);
    expect(
      file.existsSync(),
      isTrue,
      reason:
          'Expected to find $relativePath relative to the current directory '
          '(${Directory.current.path}). Run `flutter test` from app_flutter/.',
    );
    return file.readAsStringSync();
  }

  group('native window title matches spec page 01', () {
    test('Windows runner titles the window git-branch-manager', () {
      final String source = readRunnerSource('windows/runner/main.cpp');

      // The first argument to Win32Window::Create is the window title. It is
      // unrelated to CMakeLists.txt's BINARY_NAME, so changing it does not
      // rename gbm_flutter.exe (which release.yml hardcodes).
      expect(
        source,
        contains('window.Create(L"$expectedTitle"'),
        reason:
            'windows/runner/main.cpp should pass the spec title to '
            'Win32Window::Create.',
      );
      expect(
        source,
        isNot(contains('L"$scaffoldDefault"')),
        reason:
            'The scaffold-default window title should be gone, not just '
            'shadowed by a second Create call.',
      );
    });

    test('Linux runner titles both the header bar and the plain title', () {
      final String source = readRunnerSource('linux/runner/my_application.cc');

      // my_application.cc branches on the desktop environment: GNOME gets a
      // GtkHeaderBar, X11-without-GNOME gets a traditional title bar. Missing
      // either one leaves half of Linux showing the wrong title.
      expect(
        source,
        contains('gtk_header_bar_set_title(header_bar, "$expectedTitle")'),
        reason: 'The GNOME header-bar branch should use the spec title.',
      );
      expect(
        source,
        contains('gtk_window_set_title(window, "$expectedTitle")'),
        reason:
            'The X11 traditional-title-bar branch should use the spec title.',
      );
      expect(
        source,
        isNot(contains('"$scaffoldDefault"')),
        reason: 'Neither Linux branch should still carry the scaffold default.',
      );
    });

    test('macOS runner sets the NSWindow title in code', () {
      final String source = readRunnerSource(
        'macos/Runner/MainFlutterWindow.swift',
      );

      // Set in Swift rather than via PRODUCT_NAME: AppInfo.xcconfig's
      // PRODUCT_NAME is also the *artifact* name, and release.yml hardcodes
      // gbm_flutter.app paths. `awakeFromNib` runs after the nib loads, so an
      // assignment there wins over MainMenu.xib's own title attribute.
      expect(
        source,
        contains('self.title = "$expectedTitle"'),
        reason:
            'MainFlutterWindow.awakeFromNib should set the NSWindow title '
            'explicitly.',
      );

      // The deferred re-assignment is what actually survives: measured on
      // macOS, a synchronous set here (and in MainMenu.xib, and in
      // AppDelegate.applicationDidFinishLaunching) is reverted to
      // CFBundleName -- `gbm_flutter` -- before the window is on screen.
      // It reads as redundant next to the line above, so assert it or it
      // gets "cleaned up" and the title silently regresses.
      expect(
        source,
        contains('DispatchQueue.main.async { self.title = "$expectedTitle" }'),
        reason:
            'The synchronous assignment alone does not stick; the next-turn '
            're-assignment is the one that survives startup.',
      );
    });
  });
}
