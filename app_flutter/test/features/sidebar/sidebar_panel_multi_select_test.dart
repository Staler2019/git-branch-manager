// Spec page 13 section B, sidebar half: MULTIKEYS' click semantics,
// MULTIBRANCHMENU's right-click rule, and COMPARES 1's literal
// 「同時選兩個分支 → 右鍵 Compare」.
//
// Driven through the real SidebarPanel / branchSelectionProvider /
// repoSessionProvider / GoRouter seam rather than against BranchTreeItem in
// isolation, for the reason CLAUDE.md's Testing tiers section gives: a
// widget test proves the row renders a disabled item correctly, not that
// the panel's own wiring ever produces one. Two of the actions asserted
// here (Compare, Delete N branches…) dispatch by *navigation* and never
// touch commandLog at all, so a commandLog-only test could not see them
// regress.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/repositories/branch_repository.dart';
import 'package:gbm_flutter/data/repositories/branch_selection_repository.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');
final String _repoIdParam = Uri.encodeComponent(_identity.workDir);

RefInfo _local(
  String name, {
  String upstream = '',
  int ahead = 0,
  bool isHead = false,
}) => RefInfo(
  fullName: 'refs/heads/$name',
  shortName: name,
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: upstream,
  ahead: ahead,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: isHead,
  isSymbolic: false,
  worktreePath: '',
);

// Flat names with no `/`: branch_tree_builder groups `feature/x` under a
// collapsible folder, so the row's text would be `x`, not the full name --
// a dependency on tree rendering these tests have no business carrying.
final RefInfo _main = _local(
  'main',
  upstream: 'refs/remotes/origin/main',
  isHead: true,
);
final RefInfo _alpha = _local('alpha', upstream: 'refs/remotes/origin/alpha');
final RefInfo _beta = _local('beta', upstream: 'refs/remotes/origin/beta');
// No upstream: spec's `local` badge state, the case Push has to invent a
// remote for.
final RefInfo _gamma = _local('gamma');
final RefInfo _delta = _local('delta');

final RefSnapshot _refs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[_main, _alpha, _beta, _gamma, _delta],
  refCountGuardTripped: false,
  totalRefCount: 5,
);

class _Harness {
  _Harness({required this.fake, required this.container, required this.router});

  final FakeRepoSessionController fake;
  final ProviderContainer container;
  final GoRouter router;

  ListSelection<String> get selection =>
      container.read(branchSelectionProvider(_identity));

  set selection(ListSelection<String> value) =>
      container.read(branchSelectionProvider(_identity).notifier).state = value;

  List<FakeCommand> commands(String name) =>
      fake.commandLog.where((FakeCommand c) => c.name == name).toList();
}

Future<_Harness> _pump(
  WidgetTester tester, {
  List<RemoteInfo> remotes = const <RemoteInfo>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    RepoSessionState(refs: _refs, remotes: remotes),
  );

  final GoRouter router = GoRouter(
    initialLocation: '/repo/$_repoIdParam/history',
    routes: <RouteBase>[
      GoRoute(
        path: '/repo/:repoId/history',
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: SidebarPanel(identity: _identity, filterFocusNode: null),
        ),
      ),
      GoRoute(
        path: RoutePaths.deleteBranchesDialog,
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: Text('delete-branches:${state.uri.queryParameters['names']}'),
        ),
      ),
      GoRoute(
        path: '/repo/:repoId/compare/:tabId',
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: Text('compare-page')),
      ),
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoRefsProvider(_identity).overrideWithValue(_refs),
      repoSessionProvider(_identity).overrideWith((Ref ref) => fake),
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
  return _Harness(fake: fake, container: container, router: router);
}

Finder _row(String branch) =>
    find.ancestor(of: find.text(branch), matching: find.byType(BranchTreeItem));

/// Ctrl/Cmd-click: the modifier is read from `HardwareKeyboard` at tap
/// time (`currentSelectionGesture()`), so the key has to be genuinely held
/// across the tap rather than passed as a flag.
Future<void> _modifierClick(
  WidgetTester tester,
  String branch,
  LogicalKeyboardKey key,
) async {
  await tester.sendKeyDownEvent(key);
  await tester.tap(_row(branch));
  await tester.pumpAndSettle();
  await tester.sendKeyUpEvent(key);
}

Future<void> _rightClick(WidgetTester tester, String branch) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  addTearDown(gesture.removePointer);
  await gesture.down(tester.getCenter(_row(branch)));
  await gesture.up();
  await tester.pumpAndSettle();
}

/// The labels of the menu that is currently open. Scoped to PopupMenuItem
/// rather than the whole Overlay so the sidebar's own row text underneath
/// does not leak in.
List<String> _menuLabels(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(PopupMenuItem<void>),
        matching: find.byType(Text),
      ),
    )
    .map((Text t) => t.data ?? '')
    .where((String s) => s.isNotEmpty)
    .toList();

void main() {
  testWidgets('a plain click on a branch row is still a checkout, not a '
      'selection -- MULTIKEYS is not applied to the sidebar\'s primary '
      'interaction', (WidgetTester tester) async {
    final _Harness h = await _pump(tester);
    await tester.tap(_row('alpha'));
    await tester.pumpAndSettle();

    expect(h.selection.items, isEmpty);
    expect(h.commands('checkout'), hasLength(1));
  });

  testWidgets('Ctrl/Cmd-click toggles rows into the selection', (
    WidgetTester tester,
  ) async {
    final _Harness h = await _pump(tester);
    await _modifierClick(tester, 'alpha', LogicalKeyboardKey.controlLeft);
    await _modifierClick(tester, 'beta', LogicalKeyboardKey.controlLeft);

    expect(h.selection.items, <String>['alpha', 'beta']);
    expect(
      h.commands('checkout'),
      isEmpty,
      reason: 'a modifier click must not also check the branch out',
    );

    await _modifierClick(tester, 'alpha', LogicalKeyboardKey.controlLeft);
    expect(h.selection.items, <String>['beta']);
  });

  testWidgets('Shift-click takes a range over the rendered rows', (
    WidgetTester tester,
  ) async {
    final _Harness h = await _pump(tester);
    await _modifierClick(tester, 'alpha', LogicalKeyboardKey.controlLeft);
    await _modifierClick(tester, 'gamma', LogicalKeyboardKey.shiftLeft);

    // Set equality, not containsAll. The rows render in tree order --
    // buildBranchTree sorts leaves alphabetically, so the sidebar shows
    // alpha, beta, delta, gamma, main -- which puts `delta` *between* the
    // two clicked rows even though the ref list orders it after `gamma`.
    // A containsAll(['alpha','beta','gamma']) assertion is satisfied by both
    // the rendered-order answer (4 rows) and the ref-order one (3 rows), so
    // it could never fail on the very thing this test is named for.
    expect(h.selection.items.toSet(), <String>{
      'alpha',
      'beta',
      'delta',
      'gamma',
    });
    expect(
      h.selection.items,
      isNot(contains('main')),
      reason: 'HEAD is excluded from the selectable rows',
    );
  });

  testWidgets('Shift-picking the two rows either side of a gap still leaves '
      'Compare enabled (COMPARES 1)', (WidgetTester tester) async {
    // The user-visible symptom of measuring a range in ref order: Compare is
    // gated on exactly two branches, so a range that silently picks up a
    // third -- or drops one -- greys it out for no reason the user can see.
    // alpha and beta are adjacent *as painted*, which is the only adjacency
    // the user can act on.
    final _Harness h = await _pump(tester);
    await _modifierClick(tester, 'alpha', LogicalKeyboardKey.controlLeft);
    await _modifierClick(tester, 'beta', LogicalKeyboardKey.shiftLeft);

    expect(h.selection.items.toSet(), <String>{'alpha', 'beta'});

    await _rightClick(tester, 'alpha');
    expect(
      find.byTooltip('Compare takes exactly two branches'),
      findsNothing,
      reason: 'exactly two rows selected, so Compare must be live',
    );
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();

    final List<CompareTabSpec> tabs = h.container.read(
      compareTabsProvider(_identity),
    );
    expect(tabs, hasLength(1));
  });

  testWidgets('a three-row Shift range disables Compare, with the reason '
      'shown', (WidgetTester tester) async {
    // alpha -> delta spans three *painted* rows (alpha, beta, delta). In ref
    // order the same two clicks would span all four, so this also pins the
    // ordering from the other side.
    final _Harness h = await _pump(tester);
    await _modifierClick(tester, 'alpha', LogicalKeyboardKey.controlLeft);
    await _modifierClick(tester, 'delta', LogicalKeyboardKey.shiftLeft);

    expect(h.selection.items.toSet(), <String>{'alpha', 'beta', 'delta'});

    await _rightClick(tester, 'alpha');
    // Disabled-with-a-reason, never hidden -- spec page 13's rule.
    expect(
      find.byTooltip('Compare takes exactly two branches'),
      findsOneWidget,
    );
  });

  testWidgets('right-clicking a selected row keeps the selection and opens '
      'MULTIBRANCHMENU with a counted title', (WidgetTester tester) async {
    final _Harness h = await _pump(tester);
    h.selection = const ListSelection<String>(
      items: <String>['alpha', 'beta'],
      anchor: 'beta',
    );
    await tester.pumpAndSettle();

    await _rightClick(tester, 'alpha');
    expect(h.selection.items, <String>['alpha', 'beta']);
    expect(find.text('2 branches selected'), findsOneWidget);
    expect(_menuLabels(tester), contains('Delete 2 branches…'));
  });

  testWidgets('right-clicking an unselected row collapses onto it first, '
      'then opens the ordinary 05-B menu', (WidgetTester tester) async {
    final _Harness h = await _pump(tester);
    h.selection = const ListSelection<String>(
      items: <String>['alpha', 'beta'],
      anchor: 'beta',
    );
    await tester.pumpAndSettle();

    await _rightClick(tester, 'gamma');
    expect(h.selection.items, <String>[
      'gamma',
    ], reason: 'spec page 13: 點在未選中的項目上先改為只選它，再開選單');
    expect(_menuLabels(tester), contains('Rebase current onto here'));
    expect(_menuLabels(tester), isNot(contains('Delete 2 branches…')));
  });

  testWidgets('Compare on a two-branch selection opens a tab with both '
      'sides filled (COMPARES 1)', (WidgetTester tester) async {
    final _Harness h = await _pump(tester);
    h.selection = const ListSelection<String>(
      items: <String>['alpha', 'beta'],
      anchor: 'beta',
    );
    await tester.pumpAndSettle();

    await _rightClick(tester, 'alpha');
    await tester.tap(find.text('Compare'));
    await tester.pumpAndSettle();

    expect(find.text('compare-page'), findsOneWidget);
    final List<CompareTabSpec> tabs = h.container.read(
      compareTabsProvider(_identity),
    );
    expect(tabs, hasLength(1));
    expect(tabs.single.left, 'alpha');
    expect(tabs.single.right, 'beta');
  });

  testWidgets('Delete N branches… routes to the confirmation instead of '
      'deleting outright', (WidgetTester tester) async {
    final _Harness h = await _pump(tester);
    h.selection = const ListSelection<String>(
      items: <String>['alpha', 'beta'],
      anchor: 'beta',
    );
    await tester.pumpAndSettle();

    await _rightClick(tester, 'alpha');
    await tester.tap(find.text('Delete 2 branches…'));
    await tester.pumpAndSettle();

    expect(find.text('delete-branches:alpha,beta'), findsOneWidget);
    expect(
      h.commands('deleteBranch'),
      isEmpty,
      reason: 'spec page 13 requires a per-branch confirmation first',
    );
  });

  testWidgets('Fetch groups by the remote each upstream names', (
    WidgetTester tester,
  ) async {
    final _Harness h = await _pump(tester);
    h.selection = const ListSelection<String>(
      items: <String>['alpha', 'beta'],
      anchor: 'beta',
    );
    await tester.pumpAndSettle();

    await _rightClick(tester, 'alpha');
    await tester.tap(find.text('Fetch 2 branches'));
    await tester.pumpAndSettle();

    final List<FakeCommand> fetches = h.commands('fetchRemote');
    expect(fetches, hasLength(1), reason: 'both upstreams live on origin');
    expect(fetches.single.args['remoteName'], 'origin');
    expect(fetches.single.args['refs'], <String>['alpha', 'beta']);
  });

  testWidgets('Fetch is disabled, with a reason, when nothing selected has '
      'an upstream', (WidgetTester tester) async {
    final _Harness h = await _pump(tester);
    h.selection = const ListSelection<String>(
      items: <String>['gamma', 'delta'],
      anchor: 'delta',
    );
    await tester.pumpAndSettle();

    await _rightClick(tester, 'gamma');
    // Asserted while the menu is still up: tapping the row dismisses it,
    // taking the Tooltip with it.
    expect(
      find.byTooltip(
        'None of the selected branches has an upstream to fetch from',
      ),
      findsOneWidget,
      reason: 'spec page 13: a disabled row must say why, never go mute',
    );

    await tester.tap(find.text('Fetch 2 branches'));
    await tester.pumpAndSettle();
    expect(
      h.commands('fetchRemote'),
      isEmpty,
      reason: 'no upstream means no remote-tracking ref to update',
    );
  });

  testWidgets('Ctrl/Cmd+A selects every selectable row, and Esc collapses '
      'back to the anchor (MULTIKEYS)', (WidgetTester tester) async {
    final _Harness h = await _pump(tester);
    await _modifierClick(tester, 'beta', LogicalKeyboardKey.controlLeft);

    await _modifierClick(tester, 'beta', LogicalKeyboardKey.controlLeft);
    h.selection = const ListSelection<String>(
      items: <String>['beta'],
      anchor: 'beta',
    );
    await tester.pumpAndSettle();

    // Focus has to be inside the tree for the list-scoped binding to fire --
    // that is the whole point of not registering it app-wide.
    h.container.read(branchSelectionProvider(_identity).notifier).state =
        const ListSelection<String>(items: <String>['beta'], anchor: 'beta');
    await tester.tap(_row('beta'));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      h.selection.items,
      containsAll(<String>['alpha', 'beta', 'gamma', 'delta']),
    );
    expect(h.selection.items, isNot(contains('main')));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.selection.items, <String>[
      h.selection.anchor!,
    ], reason: 'Esc collapses to the anchor, it does not clear');
  });

  testWidgets('Push sends one call per remote, and unpublished branches go '
      'to the sole remote with --set-upstream', (WidgetTester tester) async {
    final _Harness h = await _pump(
      tester,
      remotes: const <RemoteInfo>[
        RemoteInfo(name: 'origin', fetchUrl: 'u', pushUrl: 'u'),
      ],
    );
    h.selection = const ListSelection<String>(
      items: <String>['alpha', 'beta', 'gamma'],
      anchor: 'gamma',
    );
    await tester.pumpAndSettle();

    await _rightClick(tester, 'alpha');
    await tester.tap(find.text('Push 3 branches'));
    await tester.pumpAndSettle();

    final List<FakeCommand> pushes = h.commands('pushChanges');
    expect(pushes, hasLength(2));
    expect(pushes[0].args['branches'], <String>['alpha', 'beta']);
    expect(pushes[0].args['setUpstream'], isFalse);
    expect(
      pushes[1].args['branches'],
      <String>['gamma'],
      reason:
          'kept in its own call: folding it into the origin group would '
          'let push -u repoint a branch tracking a differently-named ref',
    );
    expect(pushes[1].args['setUpstream'], isTrue);
  });

  testWidgets('Push is disabled, with a reason, when an unpublished branch '
      'has no single remote to go to', (WidgetTester tester) async {
    final _Harness h = await _pump(
      tester,
      remotes: const <RemoteInfo>[
        RemoteInfo(name: 'origin', fetchUrl: 'u', pushUrl: 'u'),
        RemoteInfo(name: 'fork', fetchUrl: 'u', pushUrl: 'u'),
      ],
    );
    h.selection = const ListSelection<String>(
      items: <String>['alpha', 'gamma'],
      anchor: 'gamma',
    );
    await tester.pumpAndSettle();

    await _rightClick(tester, 'alpha');
    await tester.tap(find.text('Push 2 branches'));
    await tester.pumpAndSettle();

    expect(
      h.commands('pushChanges'),
      isEmpty,
      reason: 'the row is disabled, so its onTap is null (not merely grey)',
    );
  });
}
