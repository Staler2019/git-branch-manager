// TabRow is presentational (no Riverpod/FFI dependency, same split as
// MenuBarRow -- see its doc comment), so this drives it directly with
// GoRouter + a plain pendingChangeCount int: History/Working Copy tabs
// navigate to the expected route, and the Working Copy tab shows a
// change-count badge only when there is something to show.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
import 'package:gbm_flutter/features/workspace/widgets/tab_row.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

const String _repoId = 'repo1';

Future<GoRouter> _pump(
  WidgetTester tester, {
  required int pendingChangeCount,
  String initialLocation = '',
  List<CompareTabSpec> compareTabs = const <CompareTabSpec>[],
  ValueChanged<String>? onCloseCompareTab,
  bool conflictActive = false,
}) async {
  final GoRouter router = GoRouter(
    initialLocation: initialLocation.isEmpty
        ? RoutePaths.historyFor(_repoId)
        : initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) => Scaffold(
          body: TabRow(
            repoId: _repoId,
            pendingChangeCount: pendingChangeCount,
            compareTabs: compareTabs,
            onCloseCompareTab: onCloseCompareTab,
            conflictActive: conflictActive,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.workingCopy,
        builder: (context, state) => Scaffold(
          body: TabRow(
            repoId: _repoId,
            pendingChangeCount: pendingChangeCount,
            compareTabs: compareTabs,
            onCloseCompareTab: onCloseCompareTab,
            conflictActive: conflictActive,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.compare,
        builder: (context, state) => Scaffold(
          body: TabRow(
            repoId: _repoId,
            pendingChangeCount: pendingChangeCount,
            compareTabs: compareTabs,
            onCloseCompareTab: onCloseCompareTab,
            conflictActive: conflictActive,
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.mergeDialog,
        builder: (context, state) => const Scaffold(body: Text('merge-dialog')),
      ),
      GoRoute(
        path: RoutePaths.cherryPickDialog,
        builder: (context, state) =>
            const Scaffold(body: Text('cherry-pick-dialog')),
      ),
      GoRoute(
        path: RoutePaths.resetBranchDialog,
        builder: (context, state) =>
            const Scaffold(body: Text('reset-branch-dialog')),
      ),
      GoRoute(
        path: RoutePaths.createTagDialog,
        builder: (context, state) =>
            const Scaffold(body: Text('create-tag-dialog')),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      routerConfig: router,
    ),
  );
  return router;
}

void main() {
  testWidgets(
    'shows no badge on Working Copy when there are no pending changes',
    (tester) async {
      await _pump(tester, pendingChangeCount: 0);
      expect(find.text('Working Copy'), findsOneWidget);
      expect(find.byKey(const Key('tab-row-pending-badge')), findsNothing);
    },
  );

  testWidgets('shows the pending change count as a badge on Working Copy', (
    tester,
  ) async {
    await _pump(tester, pendingChangeCount: 3);
    expect(find.byKey(const Key('tab-row-pending-badge')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('tapping Working Copy navigates to the working-copy route', (
    tester,
  ) async {
    final GoRouter router = await _pump(tester, pendingChangeCount: 1);
    await tester.tap(find.text('Working Copy'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      RoutePaths.workingCopyFor(_repoId),
    );
  });

  testWidgets('Cherry-pick button pushes the cherry-pick dialog route', (
    tester,
  ) async {
    await _pump(tester, pendingChangeCount: 0);
    await tester.tap(find.text('Cherry-pick…'));
    await tester.pumpAndSettle();
    expect(find.text('cherry-pick-dialog'), findsOneWidget);
  });

  // Tier 6b removed the Merge… and Reset… buttons: spec page 14 confines
  // beyond-spec entry points to the menu bar and context menus, and both
  // already had a home there (Branch -> Merge into current…, and 05-E's
  // "Reset branch to here…"). Cherry-pick… stayed -- see #86.
  testWidgets('the tab row no longer offers Merge… or Reset… buttons', (
    tester,
  ) async {
    await _pump(tester, pendingChangeCount: 0);
    expect(find.text('Merge…'), findsNothing);
    expect(find.text('Reset…'), findsNothing);
    expect(find.text('Cherry-pick…'), findsOneWidget);
  });

  group('conflictActive gates Cherry-pick', () {
    testWidgets('Cherry-pick renders as a disabled TextButton '
        '(onPressed null) while conflictActive is true', (tester) async {
      await _pump(tester, pendingChangeCount: 0, conflictActive: true);

      final TextButton button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Cherry-pick…'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'tapping Cherry-pick while conflictActive is true does not navigate',
      (tester) async {
        final GoRouter router = await _pump(
          tester,
          pendingChangeCount: 0,
          conflictActive: true,
        );
        final String startLocation = router
            .routerDelegate
            .currentConfiguration
            .uri
            .toString();

        await tester.tap(find.text('Cherry-pick…'));
        await tester.pumpAndSettle();

        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          startLocation,
        );
      },
    );

    testWidgets('Cherry-pick is enabled again once conflictActive '
        'flips back to false', (tester) async {
      await _pump(tester, pendingChangeCount: 0);

      final TextButton button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Cherry-pick…'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNotNull);
    });
  });

  testWidgets(
    'More menu holds only the two items spec has not rehomed',
    // Spec page 14 deletes this menu outright ("分頁列右側的 18 項溢出選單在
    // Tools 與 flyout 上線後刪除。同一功能不留兩條路"). Tier 6b moved every
    // item it could: nine to the Tools menu, three to the file context
    // menu's History flyout, Stash changes to the Branch menu, two
    // duplicates dropped, and Operation Log deleted in Tier 6a.
    //
    // These two have nowhere to go: spec gives Create tag… and Undo last
    // operation… no entry point at all -- not in 05-D, not in TOOLSMENU, not
    // in MENUS (P18 draws both dialogs but names no `from:`). Issues #84 and
    // #85. Keeping them here does not violate "同一功能不留兩條路" because
    // neither has a second route; the menu disappears once they are placed.
    (tester) async {
      await _pump(tester, pendingChangeCount: 0);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();

      // Not a Material PopupMenuButton overlay -- see tab_row.dart's
      // _MoreMenu doc comment on why this must go through showGbmMenu.
      expect(find.byType(PopupMenuButton<String>), findsNothing);

      expect(find.text('Create tag…'), findsOneWidget);
      expect(find.text('Undo last operation…'), findsOneWidget);

      // Everything that was rehomed must be gone from here, or the app has
      // two routes to one feature -- exactly what page 14 forbids.
      for (final String gone in const <String>[
        'Stash changes…',
        'Manage stashes…',
        'Manage worktrees…',
        'Remotes…',
        'Blame…',
        'File history…',
        'Line history…',
        'Reflog…',
        'Interactive rebase…',
        'Submodules…',
        'Bisect…',
        'Large files (LFS)…',
        'Patches…',
        'Clean untracked files…',
        'Repository Settings…',
        'Preferences…',
        'Operation Log…',
      ]) {
        expect(find.text(gone), findsNothing, reason: gone);
      }
    },
  );

  // Manage stashes… moved to the Tools menu in Tier 6b; its dispatch is
  // covered by test/integration/workspace_tools_menu_test.dart. What is
  // still worth asserting here is that a surviving _MoreMenu item routes.
  testWidgets('More menu > Create tag… pushes the create-tag route', (
    tester,
  ) async {
    await _pump(tester, pendingChangeCount: 0);
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create tag…'));
    await tester.pumpAndSettle();
    expect(find.text('create-tag-dialog'), findsOneWidget);
  });

  testWidgets('renders an open Compare tab after the two fixed tabs', (
    tester,
  ) async {
    await _pump(
      tester,
      pendingChangeCount: 0,
      compareTabs: const <CompareTabSpec>[
        CompareTabSpec(id: 'compare-0', left: 'main', right: 'feature'),
      ],
    );
    expect(find.text('main vs feature'), findsOneWidget);
  });

  testWidgets('tapping a Compare tab navigates to its route', (tester) async {
    final GoRouter router = await _pump(
      tester,
      pendingChangeCount: 0,
      compareTabs: const <CompareTabSpec>[
        CompareTabSpec(id: 'compare-0', left: 'main', right: 'feature'),
      ],
    );
    await tester.ensureVisible(find.text('main vs feature'));
    await tester.tap(find.text('main vs feature'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      RoutePaths.compareFor(_repoId, 'compare-0'),
    );
  });

  testWidgets('tapping a Compare tab close icon calls onCloseCompareTab '
      'with its id', (tester) async {
    String? closedId;
    await _pump(
      tester,
      pendingChangeCount: 0,
      compareTabs: const <CompareTabSpec>[
        CompareTabSpec(id: 'compare-0', left: 'main', right: 'feature'),
      ],
      onCloseCompareTab: (String id) => closedId = id,
    );
    await tester.ensureVisible(find.byIcon(Icons.close));
    await tester.tap(find.byIcon(Icons.close));
    expect(closedId, 'compare-0');
  });

  testWidgets(
    'History/Working Copy tabs have no close icon even with Compare tabs '
    'open',
    (tester) async {
      await _pump(
        tester,
        pendingChangeCount: 0,
        compareTabs: const <CompareTabSpec>[
          CompareTabSpec(id: 'compare-0', left: 'main', right: 'feature'),
        ],
        onCloseCompareTab: (_) {},
      );
      // Exactly one close icon: the Compare tab's, not History/Working Copy.
      expect(find.byIcon(Icons.close), findsOneWidget);
    },
  );
}
