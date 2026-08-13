import 'dart:ffi';
import 'dart:io';

/// Resolves the `gbm_capi` shared library built from `src/capi/` (see the
/// implementation plan, section 2.2). Checked in order:
///
///  1. `GBM_CAPI_LIBRARY_PATH` env var -- an explicit override.
///  2. Next to the running executable -- where a packaged release build
///     bundles it. On Linux and Windows this happens automatically: `flutter
///     build`/`flutter run` now compiles gbm_capi as part of the same CMake
///     invocation (see linux/CMakeLists.txt's and windows/CMakeLists.txt's
///     Phase B block) and installs it here. macOS gets there a different
///     way -- its Xcode-based runner has no CMake build to hook a target
///     dependency into, so `macos/Runner.xcodeproj`'s Runner target instead
///     carries a "Build gbm_capi" Run Script build phase that shells out to
///     `cmake --preset capi-only` and copies the result next to the
///     executable. That phase runs for every build of the Runner target,
///     whether triggered by `flutter run`/`flutter build`, Xcode directly,
///     or an IDE (e.g. IntelliJ/Android Studio) driving either one -- so a
///     packaged macOS build no longer needs scripts/build_capi.sh's manual
///     step either.
///  3. `build/native/` under the current working directory -- where
///     `scripts/build_capi.sh`/`.ps1` copies it for `flutter run`/`flutter
///     test` on any platform (including Linux/Windows during day-to-day
///     development, where candidate #2 only exists after a real `flutter
///     build`), whose working directory is the `app_flutter/` project root.
///
/// Throws a [StateError] with all three candidate paths if none exist, since
/// a silent fallback here would surface as a much more confusing
/// "symbol not found" error later.
DynamicLibrary openGbmCapiLibrary() {
  final String libraryName = _platformLibraryName();
  final List<String> candidates = <String>[
    if (Platform.environment['GBM_CAPI_LIBRARY_PATH'] case final String path)
      path,
    _join(File(Platform.resolvedExecutable).parent.path, libraryName),
    _join(_join(Directory.current.path, 'build'), _join('native', libraryName)),
  ];

  for (final String candidate in candidates) {
    if (File(candidate).existsSync()) {
      return DynamicLibrary.open(candidate);
    }
  }

  throw StateError(
    'Could not find $libraryName. Looked in:\n'
    '${candidates.map((c) => '  - $c').join('\n')}\n'
    'Run scripts/build_capi.sh (or build_capi.ps1 on Windows) first.',
  );
}

String _platformLibraryName() {
  if (Platform.isLinux) return 'libgbm_capi.so';
  if (Platform.isMacOS) return 'libgbm_capi.dylib';
  if (Platform.isWindows) return 'gbm_capi.dll';
  throw UnsupportedError(
    'gbm_capi has no desktop build for ${Platform.operatingSystem}',
  );
}

String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
