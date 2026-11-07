import 'package:ffi/ffi.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'data/ffi/gbm_bindings.dart';
import 'data/repositories/auto_reopen_marker_repository.dart';
import 'data/repositories/gbm_bindings_provider.dart';
import 'data/repositories/recents_repository.dart';
import 'features/app_lifecycle/dart_error_handlers.dart';
import 'routing/startup_target.dart';
import 'theme/theme_mode_provider.dart';

/// Everything `main()` does before `runApp`, so a test can see it done.
///
/// The library is opened here, once, so that the error handlers and every provider share
/// one [GbmBindings]. If it cannot be opened nothing is installed and
/// [gbmBindingsProvider] is left to open it itself, so the app fails where it failed
/// before this existed.
///
/// Where the launch starts is decided here too, because the auto-reopen marker has to be on
/// disk before the session it guards opens: set and awaited when reopening, cleared when a
/// marker left behind sends this launch to the welcome screen instead (#207).
///
/// [extraOverrides] is for tests: appended to this scope's own, so it stays the only
/// container and every provider sees both.
Future<Widget> bootstrapApp({
  required GbmBindings Function() openBindings,
  required Future<SharedPreferences> Function() loadPrefs,
  InstallDartErrorHandlers install = installDartErrorHandlers,
  Widget child = const GbmApp(),
  List<Override> extraOverrides = const <Override>[],
}) async {
  final SharedPreferences prefs = await loadPrefs();
  final AutoReopenMarkerRepository marker = AutoReopenMarkerRepository(prefs);
  final StartupTarget target = decideStartupTarget(
    marker: marker.read(),
    recents: RecentsRepository(prefs).read(),
  );
  switch (target) {
    case OpenRecent(:final String workDir):
      await marker.set(workDir);
    case Welcome(:final String? skipped):
      if (skipped != null) await marker.clear();
  }
  GbmBindings? bindings;
  try {
    bindings = openBindings();
    // DynamicLibrary.open reports a missing library as an ArgumentError.
  } catch (_) {
    bindings = null;
  }
  if (bindings != null) {
    install(report: reportThroughBindings(bindings));
  }
  return ProviderScope(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      if (bindings != null) gbmBindingsProvider.overrideWithValue(bindings),
      startupTargetProvider.overrideWithValue(target),
      if (target case OpenRecent(:final String workDir))
        pendingAutoReopenProvider.overrideWithValue(workDir),
      if (target case Welcome(:final String skipped?))
        skippedAutoReopenProvider.overrideWithValue(skipped),
      ...extraOverrides,
    ],
    child: child,
  );
}

/// [ExternalErrorReport] over `gbm_report_external_error`.
ExternalErrorReport reportThroughBindings(GbmBindings bindings) =>
    (String where, String summary, String detail) => using((Arena arena) {
      bindings.reportExternalError(
        where.toNativeUtf8(allocator: arena),
        summary.toNativeUtf8(allocator: arena),
        detail.toNativeUtf8(allocator: arena),
      );
    });
