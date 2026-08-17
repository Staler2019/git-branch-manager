// The repository switcher (spec page 02 item 15): the merged recents +
// discovery list, the search field, the fixed Open / Clone footer, the 05-A
// row context menu, and the popover the sidebar button opens.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/repositories/discovery_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/features/repo_switcher/repo_switcher_popover.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

const String _workDir1 = '/Users/test/repo1';
const String _workDir2 = '/Users/test/repo2';

RepoRecord _record({
  int id = 1,
  String workDir = _workDir1,
  String name = 'test-repo-1',
  int? missingSince,
}) {
  return RepoRecord(
    id: id,
    baseFolderId: 1,
    workDir: workDir,
    gitDir: '$workDir/.git',
    commonDir: '$workDir/.git',
    kind: RepoKind.normal,
    name: name,
    parentRepoId: null,
    depth: 0,
    discoveredAt: 1000000,
    missingSince: missingSince,
  );
}

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  addTearDown(gesture.removePointer);
  await gesture.down(tester.getCenter(finder));
  await gesture.up();
  await tester.pumpAndSettle();
}

/// Pumps [child] under a router with a workspace and a repository-settings
/// route to navigate to, plus stub recents/discovery providers.
Future<GoRouter> _pump(
  WidgetTester tester,
  Widget child, {
  List<RecentRepoEntry> recents = const <RecentRepoEntry>[],
  List<RepoRecord> repos = const <RepoRecord>[],
  _TestRecentsRepository? recentsRepository,
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/', builder: (context, state) => Scaffold(body: child)),
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) => Scaffold(
          body: Text('workspace: ${state.pathParameters['repoId']}'),
        ),
      ),
      GoRoute(
        path: RoutePaths.repositorySettingsDialog,
        builder: (context, state) =>
            const Scaffold(body: Text('repository-settings-dialog')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        recentsRepositoryProvider.overrideWithValue(
          recentsRepository ?? _TestRecentsRepository(recents.toList()),
        ),
        gbmBindingsProvider.overrideWithValue(_FakeGbmBindings()),
        discoveryProvider.overrideWith((ref) => _TestDiscoveryController(repos)),
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
  group('buildRepoSwitcherEntries', () {
    test('lists recents first, in order, then the rest by name', () {
      final List<RepoSwitcherEntry> entries = buildRepoSwitcherEntries(
        recents: <RecentRepoEntry>[
          const RecentRepoEntry(workDir: _workDir2, lastOpenedEpochMs: 2),
        ],
        discovered: <RepoRecord>[
          _record(id: 1, workDir: '/z/zeta', name: 'zeta'),
          _record(id: 2, workDir: _workDir2, name: 'test-repo-2'),
          _record(id: 3, workDir: '/a/alpha', name: 'alpha'),
        ],
      );

      expect(
        entries.map((RepoSwitcherEntry e) => e.name),
        <String>['test-repo-2', 'alpha', 'zeta'],
      );
    });

    test('a repo in both sources appears once and counts as scanned', () {
      final List<RepoSwitcherEntry> entries = buildRepoSwitcherEntries(
        recents: <RecentRepoEntry>[
          const RecentRepoEntry(workDir: _workDir1, lastOpenedEpochMs: 1),
        ],
        discovered: <RepoRecord>[_record()],
      );

      expect(entries, hasLength(1));
      expect(entries.single.isManual, isFalse);
      expect(entries.single.name, 'test-repo-1');
    });

    test('a recent no scan ever found is manual, named after its folder', () {
      final List<RepoSwitcherEntry> entries = buildRepoSwitcherEntries(
        recents: <RecentRepoEntry>[
          const RecentRepoEntry(workDir: '/tmp/spike-lfs/', lastOpenedEpochMs: 1),
        ],
        discovered: const <RepoRecord>[],
      );

      expect(entries.single.isManual, isTrue);
      expect(entries.single.name, 'spike-lfs');
    });

    test('carries the missing flag through from the discovery record', () {
      final List<RepoSwitcherEntry> entries = buildRepoSwitcherEntries(
        recents: const <RecentRepoEntry>[],
        discovered: <RepoRecord>[_record(missingSince: 42)],
      );

      expect(entries.single.isMissing, isTrue);
    });
  });

  group('filterRepoSwitcherEntries', () {
    const List<RepoSwitcherEntry> entries = <RepoSwitcherEntry>[
      RepoSwitcherEntry(workDir: '/a/alpha', name: 'alpha', isManual: false),
      RepoSwitcherEntry(workDir: '/b/beta', name: 'beta', isManual: true),
    ];

    test('an empty query keeps everything', () {
      expect(filterRepoSwitcherEntries(entries, '   '), entries);
    });

    test('matches name and path, case-insensitively', () {
      expect(
        filterRepoSwitcherEntries(entries, 'ALPH').single.name,
        'alpha',
      );
      expect(filterRepoSwitcherEntries(entries, '/b/').single.name, 'beta');
      expect(filterRepoSwitcherEntries(entries, 'gamma'), isEmpty);
    });
  });

  group('RepoSwitcherList', () {
    testWidgets('renders the merged list and the fixed footer', (tester) async {
      await _pump(
        tester,
        const RepoSwitcherList(),
        recents: <RecentRepoEntry>[
          const RecentRepoEntry(workDir: _workDir1, lastOpenedEpochMs: 2),
        ],
        repos: <RepoRecord>[
          _record(),
          _record(id: 2, workDir: _workDir2, name: 'test-repo-2'),
        ],
      );

      expect(find.text('test-repo-1'), findsOneWidget);
      expect(find.text('test-repo-2'), findsOneWidget);
      expect(find.text('Open repository…'), findsOneWidget);
      expect(find.text('Clone repository…'), findsOneWidget);
    });

    testWidgets('the search field filters the list', (tester) async {
      await _pump(
        tester,
        const RepoSwitcherList(),
        repos: <RepoRecord>[
          _record(),
          _record(id: 2, workDir: _workDir2, name: 'other-repo'),
        ],
      );

      await tester.enterText(find.byType(TextField), 'other');
      await tester.pumpAndSettle();

      expect(find.text('test-repo-1'), findsNothing);
      expect(find.text('other-repo'), findsOneWidget);
    });

    testWidgets('says so when nothing matches the query', (tester) async {
      await _pump(
        tester,
        const RepoSwitcherList(),
        repos: <RepoRecord>[_record()],
      );

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.textContaining('No repository matches'), findsOneWidget);
    });

    testWidgets('points at Preferences when there is nothing to list', (
      tester,
    ) async {
      await _pump(tester, const RepoSwitcherList());

      expect(
        find.textContaining('Preferences → Repository sources'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a row switches the window to that repository', (
      tester,
    ) async {
      final GoRouter router = await _pump(
        tester,
        const RepoSwitcherList(),
        repos: <RepoRecord>[_record()],
      );

      await tester.tap(find.text('test-repo-1'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        RoutePaths.workspaceFor(Uri.encodeComponent(_workDir1)),
      );
    });

    testWidgets('a manually-opened row can be removed from the list', (
      tester,
    ) async {
      final _TestRecentsRepository recents = _TestRecentsRepository(
        <RecentRepoEntry>[
          const RecentRepoEntry(workDir: '/tmp/spike', lastOpenedEpochMs: 1),
        ],
      );
      await _pump(
        tester,
        const RepoSwitcherList(),
        recentsRepository: recents,
      );

      expect(find.text('spike'), findsOneWidget);
      await _rightClick(tester, find.text('spike'));
      await tester.tap(find.text('Remove from list'));
      await tester.pumpAndSettle();

      expect(recents.read(), isEmpty);
      expect(find.text('spike'), findsNothing);
    });
  });

  group('RepoSwitcherRow', () {
    const RepoSwitcherEntry scanned = RepoSwitcherEntry(
      workDir: _workDir1,
      name: 'test-repo-1',
      isManual: false,
    );

    testWidgets('right-click shows the 05-A menu', (tester) async {
      await _pump(tester, RepoSwitcherRow(entry: scanned, onTap: () {}));
      await _rightClick(tester, find.byType(RepoSwitcherRow));

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Open in file manager'), findsOneWidget);
      expect(find.text('Open in terminal'), findsOneWidget);
      expect(find.text('Settings…'), findsOneWidget);
      expect(find.text('Remove from list'), findsOneWidget);
    });

    testWidgets('Remove from list is styled danger', (tester) async {
      await _pump(tester, RepoSwitcherRow(entry: scanned, onTap: () {}));
      await _rightClick(tester, find.byType(RepoSwitcherRow));

      final Text label = tester.widget<Text>(find.text('Remove from list'));
      expect(
        label.style?.color,
        tokensFor(GbmThemeVariant.darkTechnical).danger,
      );
    });

    testWidgets('tapping Open invokes onTap', (tester) async {
      bool opened = false;
      await _pump(
        tester,
        RepoSwitcherRow(entry: scanned, onTap: () => opened = true),
      );
      await _rightClick(tester, find.byType(RepoSwitcherRow));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(opened, isTrue);
    });

    testWidgets('Settings… pushes the repository settings route', (
      tester,
    ) async {
      await _pump(tester, RepoSwitcherRow(entry: scanned, onTap: () {}));
      await _rightClick(tester, find.byType(RepoSwitcherRow));
      await tester.tap(find.text('Settings…'));
      await tester.pumpAndSettle();

      expect(find.text('repository-settings-dialog'), findsOneWidget);
    });

    testWidgets('a scanned row says nothing about being manual', (
      tester,
    ) async {
      await _pump(tester, RepoSwitcherRow(entry: scanned, onTap: () {}));
      expect(find.text('manual'), findsNothing);
    });

    testWidgets('a manual row is labelled with its source', (tester) async {
      await _pump(
        tester,
        RepoSwitcherRow(
          entry: const RepoSwitcherEntry(
            workDir: '/tmp/spike',
            name: 'spike',
            isManual: true,
          ),
          onTap: () {},
        ),
      );
      expect(find.text('manual'), findsOneWidget);
    });

    testWidgets('a missing row is flagged offline', (tester) async {
      await _pump(
        tester,
        RepoSwitcherRow(
          entry: const RepoSwitcherEntry(
            workDir: _workDir1,
            name: 'test-repo-1',
            isManual: false,
            isMissing: true,
          ),
          onTap: () {},
        ),
      );
      expect(find.text('offline'), findsOneWidget);
    });
  });

  group('RepoSwitcherButton', () {
    testWidgets('shows the current repository and opens the popover', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 240,
          child: RepoSwitcherButton(currentWorkDir: _workDir1),
        ),
        repos: <RepoRecord>[_record()],
      );

      expect(find.text('repo1'), findsOneWidget);
      expect(find.byType(RepoSwitcherList), findsNothing);

      await tester.tap(find.byType(RepoSwitcherButton));
      await tester.pumpAndSettle();

      expect(find.byType(RepoSwitcherList), findsOneWidget);
      expect(find.text('test-repo-1'), findsOneWidget);
    });

    testWidgets('Esc closes the popover without switching', (tester) async {
      final GoRouter router = await _pump(
        tester,
        const SizedBox(
          width: 240,
          child: RepoSwitcherButton(currentWorkDir: _workDir1),
        ),
        repos: <RepoRecord>[_record()],
      );

      await tester.tap(find.byType(RepoSwitcherButton));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(RepoSwitcherList), findsNothing);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
    });

    testWidgets('the controller opens the popover from outside the button', (
      tester,
    ) async {
      final RepoSwitcherController controller = RepoSwitcherController();
      await _pump(
        tester,
        SizedBox(
          width: 240,
          child: RepoSwitcherButton(
            currentWorkDir: _workDir1,
            controller: controller,
          ),
        ),
        repos: <RepoRecord>[_record()],
      );

      controller.open();
      await tester.pumpAndSettle();

      expect(find.byType(RepoSwitcherList), findsOneWidget);
    });
  });
}

/// Fake GbmBindings: nothing in these tests reaches the native layer, so any
/// call at all is a test bug rather than something to stub out.
class _FakeGbmBindings implements GbmBindings {
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Not implemented for testing');
  }
}

class _TestRecentsRepository implements RecentsRepository {
  _TestRecentsRepository(this._entries);

  final List<RecentRepoEntry> _entries;

  @override
  List<RecentRepoEntry> read() => List<RecentRepoEntry>.unmodifiable(_entries);

  @override
  Future<void> recordOpen(String workDir) async {
    _entries.insert(
      0,
      RecentRepoEntry(workDir: workDir, lastOpenedEpochMs: 0),
    );
  }

  @override
  Future<void> remove(String workDir) async {
    _entries.removeWhere((RecentRepoEntry e) => e.workDir == workDir);
  }

  @override
  Future<void> clear() async => _entries.clear();
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
}
