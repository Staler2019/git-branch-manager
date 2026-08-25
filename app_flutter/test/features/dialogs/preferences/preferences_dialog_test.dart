// Regression coverage for the five Preferences fields that had data flowing
// through them already but no UI entry point -- see CLAUDE.md's 0g spec
// conformance note. Two (per-folder depth edit, scan summary's skipped
// count) needed a capi wrapper first (gbm_discovery_set_base_folder_depth,
// RepoIndexDb::finishScan's new dirsSkipped param); the other three
// (offline marker, manual-open per-entry delete, gitignore import-source
// label) are Flutter-only.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gbm_flutter/data/models/base_folder_record.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/discovery_repository.dart';
import 'package:gbm_flutter/features/dialogs/preferences/preferences_dialog.dart';
import 'package:gbm_flutter/features/update/auto_update_check.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

BaseFolderRecord _folder({
  int id = 1,
  required String path,
  int maxDepth = 3,
  int lastScanSkipped = 0,
}) => BaseFolderRecord(
  id: id,
  path: path,
  enabled: true,
  maxDepth: maxDepth,
  followLinks: false,
  lastScanStarted: 0,
  lastScanFinished: 0,
  lastScanDirs: 0,
  lastScanMs: 0,
  lastScanSkipped: lastScanSkipped,
);

/// Records every call instead of no-op'ing like the read-only fakes in
/// repo_switcher_popover_test.dart/welcome_screen_test.dart -- this dialog's
/// whole point is dispatching these calls, so the test needs to see them.
class _RecordingDiscoveryController extends StateNotifier<DiscoveryState>
    implements DiscoveryController {
  _RecordingDiscoveryController(List<BaseFolderRecord> folders)
    : super(DiscoveryState(baseFolders: folders, repos: const <RepoRecord>[]));

  final List<(int, int)> depthCalls = <(int, int)>[];

  @override
  void addBaseFolderAndScan(String path) {}

  @override
  void removeBaseFolder(int baseFolderId) {}

  @override
  void rescan() {}

  @override
  void setBaseFolderEnabled(int baseFolderId, bool enabled) {}

  @override
  void setBaseFolderDepth(int baseFolderId, int maxDepth) {
    depthCalls.add((baseFolderId, maxDepth));
  }
}

Future<({ProviderContainer container, _RecordingDiscoveryController discovery})>
_pump(
  WidgetTester tester, {
  List<BaseFolderRecord> folders = const <BaseFolderRecord>[],
  Map<String, Object> initialPrefs = const <String, Object>{},
  String section = 'Repository sources',
}) async {
  SharedPreferences.setMockInitialValues(initialPrefs);
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final _RecordingDiscoveryController discovery = _RecordingDiscoveryController(
    folders,
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      discoveryProvider.overrideWith((ref) => discovery),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: const Scaffold(body: PreferencesDialogContent()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // Repository sources is the section most fields in this round live under
  // (except the gitignore label, which switches section itself).
  await tester.tap(find.text(section));
  await tester.pumpAndSettle();

  return (container: container, discovery: discovery);
}

void main() {
  group('PreferencesDialogContent - General, updates', () {
    testWidgets('the startup check is on until it is turned off', (
      tester,
    ) async {
      final result = await _pump(tester, section: 'General');

      expect(find.text('Check for updates at startup'), findsOneWidget);

      await tester.ensureVisible(find.text('Check for updates at startup'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for updates at startup'));
      await tester.pumpAndSettle();

      expect(
        result.container.read(appPreferencesProvider).autoUpdateCheckEnabled,
        isFalse,
      );
    });

    // The once-a-day gate used to be invisible: nothing in the app could
    // tell "the startup check found nothing" from "the startup check is not
    // due for another 23 hours", which is how a working automatic check
    // reads as a broken one.
    testWidgets('says never before any automatic check has run', (
      tester,
    ) async {
      await _pump(tester, section: 'General');

      expect(find.text('Last automatic check: never.'), findsOneWidget);
    });

    testWidgets('names when the last automatic check ran', (tester) async {
      await _pump(
        tester,
        section: 'General',
        initialPrefs: <String, Object>{
          kLastAutoUpdateCheckKey: DateTime(
            2026,
            8,
            25,
            9,
            4,
          ).toIso8601String(),
        },
      );

      expect(
        find.text('Last automatic check: 2026-08-25 09:04.'),
        findsOneWidget,
      );
    });

    // Routed, not a callback: Preferences opens with no repository at all,
    // and this has to reach the same dialog About's button does. Replacement
    // rather than a push -- leaving Preferences stacked underneath is not
    // what "now" means.
    testWidgets('offers a route to check right now', (tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final GoRouter router = GoRouter(
        initialLocation: RoutePaths.preferencesDialog,
        routes: <RouteBase>[
          dialogRoute(
            path: RoutePaths.preferencesDialog,
            builder: (BuildContext context, GoRouterState state) =>
                const PreferencesDialogContent(),
          ),
          dialogRoute(
            path: RoutePaths.updateDialog,
            builder: (BuildContext context, GoRouterState state) =>
                const Text('update-dialog'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: MaterialApp.router(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('General'));
      await tester.pumpAndSettle();
      expect(find.text('update-dialog'), findsNothing);

      await tester.ensureVisible(find.text('Check for updates now'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for updates now'));
      await tester.pumpAndSettle();

      expect(find.text('update-dialog'), findsOneWidget);
    });

    // A suppression the user can neither see nor undo is hidden material
    // state -- the same class this app's own UX rubric flags. The row only
    // appears once something is actually being skipped, so it costs nothing
    // in the common case.
    testWidgets('says nothing about skipping when nothing is skipped', (
      tester,
    ) async {
      await _pump(tester, section: 'General');

      expect(find.textContaining('skipping'), findsNothing);
    });

    testWidgets('names the skipped version and offers to stop', (tester) async {
      final result = await _pump(
        tester,
        section: 'General',
        initialPrefs: <String, Object>{'appPrefs.skippedVersion': '9.9.9'},
      );

      expect(find.textContaining('9.9.9'), findsOneWidget);

      await tester.ensureVisible(find.text('Stop skipping'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Stop skipping'));
      await tester.pumpAndSettle();

      expect(result.container.read(appPreferencesProvider).skippedVersion, '');
      expect(find.text('Stop skipping'), findsNothing);
    });
  });

  group('PreferencesDialogContent - Repository sources', () {
    testWidgets(
      'editing the depth field and submitting calls setBaseFolderDepth',
      (tester) async {
        final result = await _pump(
          tester,
          folders: <BaseFolderRecord>[
            _folder(id: 7, path: '/code', maxDepth: 3),
          ],
        );

        // The depth field is the first TextField in this section -- the
        // folder row renders above the "Add folder…" path field below it.
        await tester.enterText(find.byType(TextField).first, '5');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();

        expect(result.discovery.depthCalls, contains((7, 5)));
      },
    );

    testWidgets(
      'scan summary reports the skipped-past-depth-limit count when nonzero',
      (tester) async {
        await _pump(
          tester,
          folders: <BaseFolderRecord>[
            _folder(id: 1, path: '/code', lastScanSkipped: 4),
          ],
        );

        expect(find.textContaining('4 skipped (depth limit)'), findsOneWidget);
      },
    );

    testWidgets('scan summary omits the skipped count when it is zero', (
      tester,
    ) async {
      await _pump(
        tester,
        folders: <BaseFolderRecord>[
          _folder(id: 1, path: '/code', lastScanSkipped: 0),
        ],
      );

      expect(find.textContaining('skipped'), findsNothing);
    });

    testWidgets('a base folder that no longer exists on disk shows a warning', (
      tester,
    ) async {
      await _pump(
        tester,
        folders: <BaseFolderRecord>[
          _folder(id: 1, path: '/definitely/does/not/exist/gbm-test-xyz'),
        ],
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
    });

    testWidgets('a base folder that exists on disk shows no warning', (
      tester,
    ) async {
      final Directory realDir = Directory.systemTemp.createTempSync(
        'gbm-prefs-test-',
      );
      addTearDown(() => realDir.deleteSync(recursive: true));

      await _pump(
        tester,
        folders: <BaseFolderRecord>[_folder(id: 1, path: realDir.path)],
      );

      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('removing one manually-opened entry only forgets that entry', (
      tester,
    ) async {
      await _pump(
        tester,
        initialPrefs: <String, Object>{
          'recents.repos':
              '[{"workDir":"/a","lastOpenedEpochMs":2},'
              '{"workDir":"/b","lastOpenedEpochMs":1}]',
        },
      );

      expect(find.text('/a'), findsOneWidget);
      expect(find.text('/b'), findsOneWidget);

      // Keyed by workDir rather than found by icon or tooltip:
      // GbmDialogShell's own header close button uses the same Icons.close
      // (would ambiguously match), and there are two "Remove from list"
      // rows once /a and /b both render (order not worth depending on).
      // ensureVisible: "Manually opened" sits below the fold of the
      // dialog's fixed-height SingleChildScrollView, so a bare tap()
      // computes an offset outside the scrolled viewport and silently
      // hits whatever else happens to occupy that screen position.
      final Finder removeA = find.byKey(
        const ValueKey<String>('recent-entry-remove-/a'),
      );
      await tester.ensureVisible(removeA);
      await tester.pumpAndSettle();
      await tester.tap(removeA);
      await tester.pumpAndSettle();

      expect(find.text('/a'), findsNothing);
      expect(
        find.text('/b'),
        findsOneWidget,
        reason: 'removing one recorded entry must not clear the others',
      );
    });
  });

  group('PreferencesDialogContent - Git', () {
    testWidgets(
      'shows the imported-from-.gitconfig label when the source is imported',
      (tester) async {
        await _pump(
          tester,
          initialPrefs: <String, Object>{
            'appPrefs.globalGitignoreEnabled': true,
            'appPrefs.globalGitignoreSource': 'imported',
          },
        );

        await tester.tap(find.text('Git'));
        await tester.pumpAndSettle();

        expect(find.text('Imported from .gitconfig'), findsOneWidget);
      },
    );

    testWidgets('shows no source label when nothing has been imported', (
      tester,
    ) async {
      await _pump(
        tester,
        initialPrefs: <String, Object>{'appPrefs.globalGitignoreEnabled': true},
      );

      await tester.tap(find.text('Git'));
      await tester.pumpAndSettle();

      expect(find.text('Imported from .gitconfig'), findsNothing);
    });
  });
}
