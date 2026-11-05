import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The manifest is read by the Windows loader, which no test tier here reaches,
/// and a `flutter create` re-scaffold would silently restore the default. Same
/// source-text assertion as `window_title_test.dart`, for the same reason.
void main() {
  // Every narrow Win32 and CRT call in the process then takes UTF-8, which is what
  // the app hands them: without it a path that reaches the active code page by
  // accident throws under CP950 (#207). Ignored before Windows 10 1903.
  test('the Windows process runs with a UTF-8 active code page', () {
    expect(
      File('windows/runner/runner.exe.manifest').readAsStringSync(),
      contains(
        '<activeCodePage xmlns="http://schemas.microsoft.com/SMI/2019/WindowsSettings">'
        'UTF-8</activeCodePage>',
      ),
    );
  });
}
