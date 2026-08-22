// Device-tier E2E support: drives a real gbm_capi.dylib/.so against a real
// temporary git repository, and boots the real GbmApp (not a fake session,
// unlike test/support/pump_workspace.dart's widget-tier harness).
//
// Precondition: `scripts/build_capi.sh` (or `.ps1`) must have already put
// the native library where `native_library.dart`'s candidate #3 looks --
// `app_flutter/build/native/` -- since `flutter test integration_test/`
// does not go through either of the packaged-build paths (#1/#2).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/app.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Runs `git` synchronously against [repoPath] and throws with the process's
/// stderr if it exits non-zero -- a silent failure here would otherwise
/// surface much later as a confusing widget-finder mismatch.
ProcessResult runGit(String repoPath, List<String> args) {
  final ProcessResult result = Process.runSync(
    'git',
    args,
    workingDirectory: repoPath,
  );
  if (result.exitCode != 0) {
    throw ProcessException(
      'git',
      args,
      'exit ${result.exitCode} in $repoPath:\n${result.stderr}',
      result.exitCode,
    );
  }
  return result;
}

/// Creates a throwaway git repository under [Directory.systemTemp] with one
/// commit on `main`, and returns its work-directory path (symlink-resolved,
/// since git itself resolves `.git`/worktree paths canonically and a
/// mismatch here would make later `RepoIdentity` equality checks flaky on
/// macOS, where `/tmp` is a symlink to `/private/tmp`).
String createTempGitRepo({String prefix = 'gbm_e2e_'}) {
  final Directory dir = Directory.systemTemp.createTempSync(prefix);
  final String path = dir.resolveSymbolicLinksSync();

  runGit(path, <String>['init', '--initial-branch=main']);
  runGit(path, <String>['config', 'user.name', 'GBM E2E']);
  runGit(path, <String>['config', 'user.email', 'gbm-e2e@example.com']);
  File('$path/README.md').writeAsStringSync('# gbm e2e fixture\n');
  runGit(path, <String>['add', 'README.md']);
  runGit(path, <String>['commit', '-m', 'Initial commit']);

  return path;
}

/// Boots the real [GbmApp] (real FFI bindings, real router) with
/// [workDir] seeded as the sole, most-recent entry in [RecentsRepository]'s
/// storage -- `appRouterProvider` reads that at construction time to decide
/// its `initialLocation`, so this lands the cold-started app directly on
/// `/repo/<workDir>/history`, exactly as a real "reopen last repository"
/// launch would.
///
/// Uses the platform's real `shared_preferences` backend (there is no
/// in-memory fake on a live device/desktop binding), scoped to this test's
/// own temp value -- callers should not assume any other key is clean.
/// [extraOverrides] is for the handful of seams a device-tier test must not
/// leave real: `desktopLauncherProvider` in particular would otherwise
/// spawn `open`/Finder/Terminal windows on the machine running the suite.
/// Everything else -- FFI bindings, router, session -- stays real; keep this
/// list as short as the test can tolerate, and say in the test why each
/// entry is there.
Future<SharedPreferences> pumpRealAppOn(
  WidgetTester tester,
  String workDir, {
  List<Override> extraOverrides = const <Override>[],
}) async {
  // The desktop test window otherwise defaults to a size narrow enough to
  // overflow ordinary rows (e.g. a commit row's ref-chip badges) -- a
  // window-size artifact of the test harness, not a real layout bug, so
  // pin a realistic desktop size rather than let it vary.
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // Device-tier tests share the machine's real shared_preferences store, so
  // whatever splitter ratios the developer last dragged in the actual app
  // are still in there -- and `GbmSplitPane` restores them by `storageId`.
  // A stored `panelLayout.main.files` was observed making History's Changed
  // files panel and the commit graph overlap by ~28px, which is enough to
  // put a row's centre under the neighbouring pane and make an otherwise
  // correct `tester.tap` miss its hit test. Reset to the built-in defaults
  // so a test's geometry depends only on the code under test.
  //
  // `graphColumns.*` is cleared for the same reason and is the newer half of
  // it: the History column set, their order and their dragged widths are all
  // persisted app-wide, so a developer who once switched Author off would
  // make an author-finding test fail on their machine and nowhere else.
  for (final String key in prefs.getKeys().where(
    (String k) => k.startsWith('panelLayout.') || k.startsWith('graphColumns.'),
  )) {
    await prefs.remove(key);
  }

  await prefs.setString(
    'recents.repos',
    jsonEncode(<Map<String, Object?>>[
      <String, Object?>{'workDir': workDir, 'lastOpenedEpochMs': 0},
    ]),
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        ...extraOverrides,
      ],
      child: const GbmApp(),
    ),
  );
  await tester.pumpAndSettle(const Duration(seconds: 1));
  return prefs;
}

/// Deletes [workDir] recursively; safe to call even if a test already
/// deleted it or the directory never fully materialized.
void deleteTempGitRepo(String workDir) {
  final Directory dir = Directory(workDir);
  if (dir.existsSync()) {
    dir.deleteSync(recursive: true);
  }
}
