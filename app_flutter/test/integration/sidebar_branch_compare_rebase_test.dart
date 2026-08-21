// 05-B's two previously-missing items, driven through the real
// SidebarPanel/repoSessionProvider/GoRouter seam rather than against
// BranchTreeItem in isolation.
//
// Both dispatch by navigation, not by a session command, so neither shows up
// in FakeRepoSessionController.commandLog -- a commandLog-only assertion
// could not see either of them regress. This checks where the router
// actually lands and, for Compare, what CompareTabSpec was opened.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
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

import '../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

RefInfo _branch(String name, {bool isHead = false}) => RefInfo(
  fullName: 'refs/heads/$name',
  shortName: name,
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: isHead,
  isSymbolic: false,
  worktreePath: '',
);

RepoSessionState _state() => RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'a',
    ),
    refs: <RefInfo>[_branch('main', isHead: true), _branch('feature')],
    refCountGuardTripped: false,
    totalRefCount: 2,
  ),
);

late ProviderContainer _container;
late GoRouter _router;

/// The `target` the rebase-onto route actually received -- asserted instead
/// of the router's reported location, which for a pushed route still reads
/// as the base path.
String? _rebaseTarget;

Future<void> _pump(WidgetTester tester) async {
  _rebaseTarget = null;
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  _container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(
        _identity,
      ).overrideWith((ref) => FakeRepoSessionController(_identity, _state())),
    ],
  );
  addTearDown(_container.dispose);

  _router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: SidebarPanel(identity: _identity)),
      ),
      GoRoute(
        path: RoutePaths.compare,
        builder: (_, _) => const Scaffold(body: Text('compare-page')),
      ),
      GoRoute(
        path: RoutePaths.rebaseOntoDialog,
        builder: (_, GoRouterState state) {
          _rebaseTarget = state.uri.queryParameters['target'];
          return const Scaffold(body: Text('rebase-dialog'));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: _container,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: _router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openMenuOn(WidgetTester tester, String branch) async {
  final Finder row = find.byWidgetPredicate(
    (Widget w) => w is BranchTreeItem && w.ref.shortName == branch,
  );
  expect(row, findsOneWidget, reason: 'no row for $branch');
  await tester.tap(row, buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Compare with… opens a Compare tab with the branch on the '
      'left and the right left to the picker', (tester) async {
    await _pump(tester);
    await _openMenuOn(tester, 'feature');

    await tester.tap(find.text('Compare with…'));
    await tester.pumpAndSettle();

    final List<CompareTabSpec> tabs = _container.read(
      compareTabsProvider(_identity),
    );
    expect(tabs, hasLength(1));
    expect(tabs.single.left, 'feature');
    expect(tabs.single.right, isNull);
    expect(find.text('compare-page'), findsOneWidget);
  });

  testWidgets('Rebase current onto here opens the shared rebase dialog '
      'pre-filled with that branch', (tester) async {
    await _pump(tester);
    await _openMenuOn(tester, 'feature');

    await tester.tap(find.text('Rebase current onto here'));
    await tester.pumpAndSettle();

    expect(find.text('rebase-dialog'), findsOneWidget);
    expect(
      _rebaseTarget,
      'feature',
      reason: 'the target query parameter is what pre-fills the dialog',
    );
  });

  testWidgets('the current branch cannot be rebased onto itself', (
    tester,
  ) async {
    await _pump(tester);
    await _openMenuOn(tester, 'main');

    await tester.tap(find.text('Rebase current onto here'));
    await tester.pumpAndSettle();

    expect(find.text('rebase-dialog'), findsNothing);
  });
}
