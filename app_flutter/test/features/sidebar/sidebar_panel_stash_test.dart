// Verifies SidebarPanel's 05-H (Stash entry) context menu wiring reaches
// the real repoSessionProvider/GoRouter seam -- see CLAUDE.md's Testing
// tiers: stash_menu_items_test.dart already covers the item list itself
// (labels/order/danger-last/nullable gating) in isolation; this covers the
// dispatch path stash_menu_items_test.dart structurally cannot, the same
// gap sidebar_panel_remote_branch_test.dart closed for the 05-C menu.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/stash_entry.dart';
import 'package:gbm_flutter/data/repositories/branch_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/stashes_panel.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _testIdentity = RepoIdentity.forWorkDir('/test/repo');
final String _repoIdParam = Uri.encodeComponent(_testIdentity.workDir);

// SidebarPanel renders "No branches" instead of the tree+stash section
// whenever the merged branch list is empty (see its `branches.isEmpty`
// guard) -- a real local branch has to be seeded here even though these
// tests only care about the stash section below it.
final RefInfo _localMain = RefInfo(
  fullName: 'refs/heads/main',
  shortName: 'main',
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: true,
  isSymbolic: true,
  worktreePath: '',
);

final RefSnapshot _testRefs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[_localMain],
  refCountGuardTripped: false,
  totalRefCount: 1,
);

final StashEntry _stash0 = StashEntry(
  index: 0,
  message: 'WIP on main: quick fix',
  oid: 'b' * 40,
  timestamp: 1700000000,
);

const RepoState _mergeState = RepoState(
  flags: RepoStateFlags.merge,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
);

class _Harness {
  _Harness({required this.fake});
  final FakeRepoSessionController fake;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  RepoSessionState initialState = const RepoSessionState(),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _testIdentity,
    initialState,
  );

  final GoRouter router = GoRouter(
    initialLocation: '/repo/$_repoIdParam/history',
    routes: <RouteBase>[
      GoRoute(
        path: '/repo/:repoId/history',
        builder: (context, state) => Scaffold(
          body: SidebarPanel(identity: _testIdentity, filterFocusNode: null),
        ),
      ),
      GoRoute(
        path: RoutePaths.compare,
        builder: (context, state) =>
            const Scaffold(body: SizedBox(key: Key('compare-stub'))),
      ),
      GoRoute(
        path: RoutePaths.panel,
        // The real panel, not a stub -- its initState is exactly what
        // "View diff" needs covered: it reads the ?select= the sidebar put
        // on the route and fires requestStashDiff for it. Tier 6c moved
        // this target from the manage-stashes dialog to a tab (spec page
        // 14 `IAMAP`); the assertion below follows it.
        builder: (context, state) => Scaffold(
          body: StashesPanel(
            identity: _testIdentity,
            initialSelectedIndex: int.tryParse(
              state.uri.queryParameters['select'] ?? '',
            ),
          ),
        ),
      ),
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoRefsProvider(_testIdentity).overrideWithValue(_testRefs),
      repoSessionProvider(_testIdentity).overrideWith((ref) => fake),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Harness(fake: fake);
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

void main() {
  group('SidebarPanel stash context menu (05-H)', () {
    testWidgets('right-clicking a stash row opens its 05-H menu', (
      tester,
    ) async {
      await _pump(
        tester,
        initialState: RepoSessionState(stashes: <StashEntry>[_stash0]),
      );

      await _rightClick(tester, find.text('WIP on main: quick fix'));

      expect(find.text('Apply stash'), findsOneWidget);
      expect(find.text('Pop stash'), findsOneWidget);
      expect(find.text('Create branch from stash…'), findsOneWidget);
      expect(find.text('View diff'), findsOneWidget);
      expect(find.text('Compare with…'), findsOneWidget);
      expect(find.text('Drop stash…'), findsOneWidget);
    });

    testWidgets('Apply stash reaches applyStash(pop: false)', (tester) async {
      final _Harness h = await _pump(
        tester,
        initialState: RepoSessionState(stashes: <StashEntry>[_stash0]),
      );

      await _rightClick(tester, find.text('WIP on main: quick fix'));
      await tester.tap(find.text('Apply stash'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = h.fake.commandLog.singleWhere(
        (c) => c.name == 'applyStash',
      );
      expect(cmd.args['index'], 0);
      expect(cmd.args['pop'], isFalse);
    });

    testWidgets('Pop stash reaches applyStash(pop: true)', (tester) async {
      final _Harness h = await _pump(
        tester,
        initialState: RepoSessionState(stashes: <StashEntry>[_stash0]),
      );

      await _rightClick(tester, find.text('WIP on main: quick fix'));
      await tester.tap(find.text('Pop stash'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = h.fake.commandLog.singleWhere(
        (c) => c.name == 'applyStash',
      );
      expect(cmd.args['pop'], isTrue);
    });

    testWidgets('Drop stash… reaches dropStash', (tester) async {
      final _Harness h = await _pump(
        tester,
        initialState: RepoSessionState(stashes: <StashEntry>[_stash0]),
      );

      await _rightClick(tester, find.text('WIP on main: quick fix'));
      await tester.tap(find.text('Drop stash…'));
      await tester.pumpAndSettle();

      expect(
        h.fake.commandLog.any(
          (c) => c.name == 'dropStash' && c.args['index'] == 0,
        ),
        isTrue,
      );
    });

    testWidgets(
      'View diff navigates to Manage Stashes with the stash pre-selected '
      'and its initState fires requestStashDiff',
      (tester) async {
        final _Harness h = await _pump(
          tester,
          initialState: RepoSessionState(stashes: <StashEntry>[_stash0]),
        );

        await _rightClick(tester, find.text('WIP on main: quick fix'));
        await tester.tap(find.text('View diff'));
        // Not pumpAndSettle: the dialog's diff pane shows an indefinitely
        // spinning CircularProgressIndicator until a real lastStashDiff
        // arrives (FakeRepoSessionController.requestStashDiff only
        // records the call, per its class doc comment -- it never
        // publishes a new state), which pumpAndSettle would wait on
        // forever. A few frames are enough for the navigation and
        // initState's microtask to land.
        await tester.pump();
        await tester.pump();

        // `go`, not `push` -- a panel is a tab that replaces the shell's
        // child rather than stacking over the sidebar.
        expect(
          GoRouterState.of(
            tester.element(find.byType(StashesPanel)),
          ).uri.toString(),
          contains('/panel/'),
        );
        expect(
          h.fake.commandLog.any(
            (c) => c.name == 'requestStashDiff' && c.args['index'] == 0,
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'Compare with… opens a Compare tab whose left ref is the stash oid',
      (tester) async {
        await _pump(
          tester,
          initialState: RepoSessionState(stashes: <StashEntry>[_stash0]),
        );

        await _rightClick(tester, find.text('WIP on main: quick fix'));
        await tester.tap(find.text('Compare with…'));
        await tester.pumpAndSettle();

        // `go`, not `push` -- SidebarPanel (and the History route it lives
        // under) is replaced, so the compare-stub route's own element is
        // what's left mounted to read the post-navigation location from.
        expect(
          GoRouterState.of(
            tester.element(find.byKey(const Key('compare-stub'))),
          ).uri.toString(),
          contains('/compare/'),
        );
      },
    );

    testWidgets(
      'Apply/Pop/Create branch from stash… are disabled while a conflict '
      'is active, then re-enabled once it clears (conflictActive '
      'round-trip, per CLAUDE.md\'s Rule)',
      (tester) async {
        final _Harness h = await _pump(
          tester,
          initialState: RepoSessionState(
            stashes: <StashEntry>[_stash0],
            repoState: _mergeState,
          ),
        );

        await _rightClick(tester, find.text('WIP on main: quick fix'));
        await tester.tap(find.text('Apply stash'));
        await tester.pumpAndSettle();
        expect(
          h.fake.commandLog.any((c) => c.name == 'applyStash'),
          isFalse,
          reason: 'mid-conflict, Apply stash should be disabled and no-op',
        );

        // repoState defaults to null (clean) on a fresh RepoSessionState
        // with no override.
        h.fake.emit(RepoSessionState(stashes: <StashEntry>[_stash0]));
        await tester.pumpAndSettle();

        await _rightClick(tester, find.text('WIP on main: quick fix'));
        await tester.tap(find.text('Apply stash'));
        await tester.pumpAndSettle();
        expect(
          h.fake.commandLog.any((c) => c.name == 'applyStash'),
          isTrue,
          reason: 'once clean, Apply stash should reach the controller',
        );
      },
    );
  });
}
