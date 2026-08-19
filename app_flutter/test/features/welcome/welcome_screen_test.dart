// The `/` screen shown when no repository is open: it is a repository
// picker (the same RepoSwitcherList the sidebar popover shows), not the
// repository dashboard it replaced -- no base-folder controls of its own,
// since those belong to Preferences → Repository sources.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/repositories/discovery_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/features/repo_switcher/repo_switcher_popover.dart';
import 'package:gbm_flutter/features/welcome/welcome_screen.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _workDir = '/Users/test/repo1';

final RepoRecord _repo = RepoRecord(
  id: 1,
  baseFolderId: 1,
  workDir: _workDir,
  gitDir: '$_workDir/.git',
  commonDir: '$_workDir/.git',
  kind: RepoKind.normal,
  name: 'test-repo-1',
  parentRepoId: null,
  depth: 0,
  discoveredAt: 1000000,
  missingSince: null,
);

Future<GoRouter> _pump(
  WidgetTester tester, {
  List<RepoRecord> repos = const <RepoRecord>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final GoRouter router = GoRouter(
    initialLocation: RoutePaths.welcome,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) => Scaffold(
          body: Text('workspace: ${state.pathParameters['repoId']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        // The app bar's theme switcher reads this one directly.
        sharedPreferencesProvider.overrideWithValue(prefs),
        recentsRepositoryProvider.overrideWithValue(RecentsRepository(prefs)),
        gbmBindingsProvider.overrideWithValue(_FakeGbmBindings()),
        discoveryProvider.overrideWith(
          (ref) => _TestDiscoveryController(repos),
        ),
      ],
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('lays out the repository picker with no overflow', (
    tester,
  ) async {
    await _pump(tester, repos: <RepoRecord>[_repo]);

    expect(find.text('No repository open'), findsOneWidget);
    expect(find.byType(RepoSwitcherList), findsOneWidget);
    expect(find.text('test-repo-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('picking a repository opens its workspace', (tester) async {
    final GoRouter router = await _pump(tester, repos: <RepoRecord>[_repo]);

    await tester.tap(find.text('test-repo-1'));
    await tester.pumpAndSettle();

    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      RoutePaths.workspaceFor(Uri.encodeComponent(_workDir)),
    );
  });

  testWidgets('sends base-folder setup to Preferences rather than owning it', (
    tester,
  ) async {
    await _pump(tester);

    expect(
      find.textContaining('Preferences → Repository sources'),
      findsWidgets,
    );
    // The quick-add field this screen used to carry now lives in
    // Preferences → Repository sources; the only field here is the
    // switcher's own search box.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Rescan'), findsNothing);
  });
}

/// Fake GbmBindings: nothing on this screen reaches the native layer once
/// `discoveryProvider` is overridden, so any call at all is a test bug.
class _FakeGbmBindings implements GbmBindings {
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Not implemented for testing');
  }
}

class _TestDiscoveryController extends StateNotifier<DiscoveryState>
    implements DiscoveryController {
  _TestDiscoveryController(List<RepoRecord> repos)
    : super(DiscoveryState(repos: repos));

  @override
  void addBaseFolderAndScan(String path) {}

  @override
  void removeBaseFolder(int baseFolderId) {}

  @override
  void rescan() {}

  @override
  void setBaseFolderEnabled(int baseFolderId, bool enabled) {}

  @override
  void setBaseFolderDepth(int baseFolderId, int maxDepth) {}
}
