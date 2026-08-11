import 'dart:ffi';
import 'dart:io';

/// Resolves the `gbm_capi` shared library built from `src/capi/` (see the
/// implementation plan, section 2.2 "Phase A"). Checked in order:
///
///  1. `GBM_CAPI_LIBRARY_PATH` env var -- an explicit override.
///  2. Next to the running executable -- where a packaged release build
///     bundles it (Phase B will make `flutter build` do this automatically).
///  3. `build/native/` under the current working directory -- where
///     `scripts/build_capi.sh`/`.ps1` copies it for `flutter run`/`flutter
///     test`, whose working directory is the `app_flutter/` project root.
///
/// Throws a [StateError] with all three candidate paths if none exist, since
/// a silent fallback here would surface as a much more confusing
/// "symbol not found" error later.
DynamicLibrary openGbmCapiLibrary() {
  final String libraryName = _platformLibraryName();
  final List<String> candidates = <String>[
    if (Platform.environment['GBM_CAPI_LIBRARY_PATH'] case final String path) path,
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
  throw UnsupportedError('gbm_capi has no desktop build for ${Platform.operatingSystem}');
}

String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
