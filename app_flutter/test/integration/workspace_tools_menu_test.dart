// Spec page 14 adds a Tools menu as the menu bar's eighth menu and routes
// the twelve advanced management panels to *tabs* rather than dialogs
// ("大型管理面板（12）… → 分頁（與 History / Working copy / Compare 同一條分頁
// 列）").
//
// This drives the real WorkspaceScreen through pumpWorkspace rather than a
// hand-fed handler map, because the thing most likely to break here is the
// dispatch seam, not the widget: CLAUDE.md records a shipped bug where menu
// ids were wired only via MenuBarRow's named params, leaving the keyboard
// and macOS menu paths silently dead. A widget test on MenuBarRow cannot
// see that; this can.
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:gbm_flutter/data/repositories/panel_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

// A ShellRoute child in the real router, like Compare -- so it belongs in
// extraRoutes, not topLevelRoutes (see pumpWorkspace's doc comment).
final List<RouteBase> _panelRoute = <RouteBase>[
  GoRoute(
    path: RoutePaths.panel,
    builder: (context, state) =>
        Scaffold(body: Text('panel:${state.pathParameters['tabId']}')),
  ),
];

String _location(WidgetTester tester) => GoRouterState.of(
  tester.element(find.byType(WorkspaceScreen)),
).uri.toString();

Future<void> _openToolsMenu(WidgetTester tester) async {
  await tester.tap(find.text('Tools'));
  await tester.pumpAndSettle();
}

void main() {
  group('Tools menu (spec page 14)', () {
    testWidgets('the menu bar renders Tools between Remote and Help', (
      tester,
    ) async {
      await pumpWorkspace(tester, identity: _identity);

      // Rule 1: "放在 Remote 之後、Help 之前".
      final double remoteX = tester.getTopLeft(find.text('Remote')).dx;
      final double toolsX = tester.getTopLeft(find.text('Tools')).dx;
      final double helpX = tester.getTopLeft(find.text('Help')).dx;

      expect(toolsX, greaterThan(remoteX));
      expect(toolsX, lessThan(helpX));
    });

    testWidgets('Tools > Worktrees… opens a panel tab and navigates to it', (
      tester,
    ) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        extraRoutes: _panelRoute,
      );

      await _openToolsMenu(tester);
      await tester.tap(find.text('Worktrees…'));
      await tester.pumpAndSettle();

      final List<PanelTabSpec> tabs = pumped.container.read(
        panelTabsProvider(_identity),
      );
      expect(tabs, hasLength(1));
      expect(tabs.single.kind, GbmPanelKind.manageWorktrees);
      expect(
        _location(tester),
        RoutePaths.panelFor(
          Uri.encodeComponent(_identity.workDir),
          tabs.single.id,
        ),
      );
    });

    testWidgets('the opened panel appears in the tab strip as a closable tab', (
      tester,
    ) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        extraRoutes: _panelRoute,
      );

      await _openToolsMenu(tester);
      await tester.tap(find.text('Worktrees…'));
      await tester.pumpAndSettle();

      // The tab strip label is the panel's name, not the menu item's.
      expect(find.text('Worktrees'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
    });

    // Re-opening focuses rather than stacking a duplicate -- the tab-strip
    // counterpart of "同一功能不留兩條路".
    testWidgets('choosing the same panel twice does not open a second tab', (
      tester,
    ) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        extraRoutes: _panelRoute,
      );

      for (int i = 0; i < 2; i++) {
        await _openToolsMenu(tester);
        await tester.tap(find.text('Worktrees…'));
        await tester.pumpAndSettle();
      }

      expect(pumped.container.read(panelTabsProvider(_identity)), hasLength(1));
    });

    testWidgets('Rewrite history opens a submenu with its three items', (
      tester,
    ) async {
      await pumpWorkspace(tester, identity: _identity);

      await _openToolsMenu(tester);
      // Rule 2 keeps the destructive/multi-step three off the top level.
      expect(find.text('Interactive rebase…'), findsNothing);

      await tester.tap(find.text('Rewrite history'));
      await tester.pumpAndSettle();

      expect(find.text('Interactive rebase…'), findsOneWidget);
      expect(find.text('Bisect…'), findsOneWidget);
      expect(find.text('Clean untracked files…'), findsOneWidget);
    });

    // Spec page 14 assigns all twelve panels to tabs, but they are ported
    // one at a time (#76). Until GbmPanelKind.isPortedToTab flips, an entry
    // point must keep opening the existing dialog -- sending it to an
    // unbuilt tab would swap a working screen for a placeholder. This locks
    // that rule in so a future port cannot quietly regress it.
    testWidgets('an unported panel still opens its dialog, not a stub tab', (
      tester,
    ) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        extraRoutes: _panelRoute,
        topLevelRoutes: <RouteBase>[
          GoRoute(
            path: RoutePaths.patchesDialog,
            builder: (context, state) =>
                const Scaffold(body: Text('patches-dialog')),
          ),
        ],
      );

      expect(GbmPanelKind.patches.isPortedToTab, isFalse);

      await _openToolsMenu(tester);
      await tester.tap(find.text('Patches…'));
      await tester.pumpAndSettle();

      expect(find.text('patches-dialog'), findsOneWidget);
      expect(pumped.container.read(panelTabsProvider(_identity)), isEmpty);
    });
  });
}
