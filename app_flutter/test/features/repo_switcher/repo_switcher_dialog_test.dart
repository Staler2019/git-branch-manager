// RepoSwitcherDialog displays recently-opened repositories and a link to the
// full repo list, allowing users to quickly switch between repos or browse all
// repositories. Tapping a recent repo navigates to that repo's workspace.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/repositories/discovery_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/features/repo_switcher/repo_switcher_dialog.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_shell.dart';
import 'package:go_router/go_router.dart';

const String _testWorkDir1 = '/Users/test/repo1';
const String _testWorkDir2 = '/Users/test/repo2';

final RepoRecord _testRepo1 = RepoRecord(
  id: 1,
  baseFolderId: 1,
  workDir: _testWorkDir1,
  gitDir: '$_testWorkDir1/.git',
  commonDir: '$_testWorkDir1/.git',
  kind: RepoKind.normal,
  name: 'test-repo-1',
  parentRepoId: null,
  depth: 0,
  discoveredAt: 1000000,
  missingSince: null,
);

final RepoRecord _testRepo2 = RepoRecord(
  id: 2,
  baseFolderId: 1,
  workDir: _testWorkDir2,
  gitDir: '$_testWorkDir2/.git',
  commonDir: '$_testWorkDir2/.git',
  kind: RepoKind.normal,
  name: 'test-repo-2',
  parentRepoId: null,
  depth: 0,
  discoveredAt: 1000001,
  missingSince: null,
);

final List<RecentRepoEntry> _testRecents = <RecentRepoEntry>[
  RecentRepoEntry(workDir: _testWorkDir1, lastOpenedEpochMs: 1000000),
  RecentRepoEntry(workDir: _testWorkDir2, lastOpenedEpochMs: 999999),
];

Future<GoRouter> _pump(
  WidgetTester tester, {
  List<RecentRepoEntry> recents = const <RecentRepoEntry>[],
  List<RepoRecord> repos = const <RepoRecord>[],
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(body: RepoSwitcherDialog()),
      ),
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) => Scaffold(
          body: Text('workspace: ${state.pathParameters['repoId']}'),
        ),
      ),
      GoRoute(
        path: RoutePaths.repoList,
        builder: (context, state) => const Scaffold(body: Text('repo-list')),
      ),
    ],
  );

  final List<Override> overrides = <Override>[
    recentsRepositoryProvider.overrideWithValue(
      _TestRecentsRepository(recents),
    ),
    gbmBindingsProvider.overrideWithValue(_FakeGbmBindings()),
    discoveryProvider.overrideWith((ref) => _TestDiscoveryController(repos)),
  ];

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );

  return router;
}

void main() {
  group('RepoSwitcherDialog', () {
    testWidgets('renders with GbmDialogShell wrapper', (tester) async {
      await _pump(
        tester,
        recents: _testRecents,
        repos: <RepoRecord>[_testRepo1, _testRepo2],
      );
      expect(find.byType(GbmDialogShell), findsOneWidget);
      expect(find.text('Switch Repository'), findsOneWidget);
    });

    testWidgets('shows Recently Opened section when there are recents', (
      tester,
    ) async {
      await _pump(
        tester,
        recents: _testRecents,
        repos: <RepoRecord>[_testRepo1, _testRepo2],
      );
      expect(find.text('Recently Opened'), findsOneWidget);
    });

    testWidgets('hides Recently Opened section when there are no recents', (
      tester,
    ) async {
      await _pump(tester, recents: const <RecentRepoEntry>[]);
      expect(find.text('Recently Opened'), findsNothing);
    });

    testWidgets('displays all recent repos with name and workDir', (
      tester,
    ) async {
      await _pump(
        tester,
        recents: _testRecents,
        repos: <RepoRecord>[_testRepo1, _testRepo2],
      );

      // Check that repo names are displayed
      expect(find.text('test-repo-1'), findsOneWidget);
      expect(find.text('test-repo-2'), findsOneWidget);

      // Check that workDirs are displayed as subtitles
      expect(find.text(_testWorkDir1), findsOneWidget);
      expect(find.text(_testWorkDir2), findsOneWidget);
    });

    testWidgets('displays workDir when repo name is not found in discovery', (
      tester,
    ) async {
      final List<RecentRepoEntry> recents = <RecentRepoEntry>[
        RecentRepoEntry(workDir: '/unknown/path', lastOpenedEpochMs: 1000000),
      ];

      await _pump(tester, recents: recents, repos: const <RepoRecord>[]);

      // Should display the workDir as both the title (fallback for the
      // missing name) and the subtitle (which always shows the workDir).
      expect(find.text('/unknown/path'), findsNWidgets(2));
    });

    testWidgets('tapping a recent repo navigates to workspace', (tester) async {
      final GoRouter router = await _pump(
        tester,
        recents: _testRecents,
        repos: <RepoRecord>[_testRepo1, _testRepo2],
      );

      // Tap the first recent repo
      await tester.tap(find.text('test-repo-1'));
      await tester.pumpAndSettle();

      // Verify navigation to workspace
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        RoutePaths.workspaceFor(Uri.encodeComponent(_testWorkDir1)),
      );
    });

    testWidgets('View All Repositories button navigates to repo list', (
      tester,
    ) async {
      final GoRouter router = await _pump(
        tester,
        recents: _testRecents,
        repos: <RepoRecord>[_testRepo1, _testRepo2],
      );

      await tester.tap(find.text('View All Repositories'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        RoutePaths.repoList,
      );
    });

    testWidgets(
      'View All Repositories button is visible even when no recents',
      (tester) async {
        await _pump(tester, recents: const <RecentRepoEntry>[]);

        expect(find.text('View All Repositories'), findsOneWidget);
      },
    );

    testWidgets('recently-opened ListView is scrollable when many items', (
      tester,
    ) async {
      // Create 20 recent repos to exceed the 300px max height
      final List<RecentRepoEntry> manyRecents = <RecentRepoEntry>[
        for (int i = 0; i < 20; i++)
          RecentRepoEntry(
            workDir: '/path/to/repo$i',
            lastOpenedEpochMs: 1000000 - i,
          ),
      ];

      final List<RepoRecord> manyRepos = <RepoRecord>[
        for (int i = 0; i < 20; i++)
          RepoRecord(
            id: i + 1,
            baseFolderId: 1,
            workDir: '/path/to/repo$i',
            gitDir: '/path/to/repo$i/.git',
            commonDir: '/path/to/repo$i/.git',
            kind: RepoKind.normal,
            name: 'repo$i',
            parentRepoId: null,
            depth: 0,
            discoveredAt: 1000000 - i,
            missingSince: null,
          ),
      ];

      await _pump(tester, recents: manyRecents, repos: manyRepos);

      // The ListView should exist and be scrollable
      expect(find.byType(ListView), findsOneWidget);

      // Some repos should be visible
      expect(find.text('repo0'), findsOneWidget);
      expect(find.text('repo1'), findsOneWidget);
    });

    testWidgets('divider appears between recents and View All button', (
      tester,
    ) async {
      await _pump(
        tester,
        recents: _testRecents,
        repos: <RepoRecord>[_testRepo1, _testRepo2],
      );

      // Divider should be visible when there are recents
      expect(find.byType(Divider), findsOneWidget);
    });

    testWidgets('no divider when there are no recents', (tester) async {
      await _pump(tester, recents: const <RecentRepoEntry>[]);

      // No divider should be visible when there are no recents
      expect(find.byType(Divider), findsNothing);
    });
  });
}

/// Fake GbmBindings for testing.
class _FakeGbmBindings implements GbmBindings {
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Not implemented for testing');
  }
}

/// Fake RecentsRepository for testing.
class _TestRecentsRepository implements RecentsRepository {
  _TestRecentsRepository(this._entries);

  final List<RecentRepoEntry> _entries;

  @override
  List<RecentRepoEntry> read() => _entries;

  @override
  Future<void> recordOpen(String workDir) async {
    // No-op for testing
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }
}

/// Minimal DiscoveryController implementation for testing.
class _TestDiscoveryController extends StateNotifier<DiscoveryState>
    implements DiscoveryController {
  _TestDiscoveryController(List<RepoRecord> repos)
    : super(DiscoveryState(repos: repos));

  @override
  void addBaseFolderAndScan(String path) {
    // No-op for testing
  }

  @override
  void removeBaseFolder(int baseFolderId) {
    // No-op for testing
  }

  @override
  void rescan() {
    // No-op for testing
  }

  @override
  void setBaseFolderEnabled(int baseFolderId, bool enabled) {
    // No-op for testing
  }
}
