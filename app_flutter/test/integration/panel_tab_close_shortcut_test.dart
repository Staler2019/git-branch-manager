// Spec page 19 樣板規則 1: 「以分頁開啟，與 History / Working copy / Compare
// 共用同一條分頁列；可同時開多個、各自記憶捲動位置與 splitter，
// Ctrl/Cmd+W 關閉。」
//
// The Ctrl/Cmd+W half was implemented in `ComparePage` and **not at all** in
// `PanelPage`, so all twelve management panels were unclosable by keyboard.
//
// This has to be an integration test with the *real* PanelPage mounted: the
// binding lives inside the page, so a stub route (which is what the Tools
// menu test uses) would exercise nothing, and a widget test on one panel
// never goes through the router at all ([TEST-new-gate-needs-integration]).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/panel_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/panels/panel_page.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

// The real PanelPage, not a stub -- see the header.
final List<RouteBase> _panelRoute = <RouteBase>[
  GoRoute(
    path: RoutePaths.panel,
    builder: (BuildContext context, GoRouterState state) => PanelPage(
      identity: _identity,
      tabId: state.pathParameters['tabId']!,
      query: state.uri.queryParameters,
    ),
  ),
];

String _location(WidgetTester tester) => GoRouterState.of(
  tester.element(find.byType(WorkspaceScreen)),
).uri.toString();

/// The tabs Ctrl/Cmd+W is allowed to close. D7 seeds a pinned Worktrees tab
/// into every repository, so 「the strip is empty」 stopped being the way to
/// say 「this tab closed」 -- filtering keeps each assertion below pinning
/// what it was written for.
List<PanelTabSpec> _closable(PumpedWorkspace pumped) => pumped.container
    .read(panelTabsProvider(_identity))
    .where((PanelTabSpec t) => !t.kind.isPinned)
    .toList();

/// Opens a management panel tab and navigates to it, the way
/// `workspace_screen.dart`'s Tools-menu handler does.
Future<String> _openPanel(
  WidgetTester tester,
  PumpedWorkspace pumped,
  GbmPanelKind kind,
) async {
  final String id = pumped.container
      .read(panelTabsProvider(_identity).notifier)
      .open(kind);
  pumped.router.go(
    RoutePaths.panelFor(Uri.encodeComponent(_identity.workDir), id),
  );
  await tester.pumpAndSettle();
  return id;
}

void main() {
  group('P19 rule 1: Ctrl/Cmd+W closes a management panel tab', () {
    testWidgets('Ctrl+W closes the tab and leaves its route', (tester) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        extraRoutes: _panelRoute,
      );
      // Deliberately not Worktrees: that one is D7's pinned tab and
      // refuses to close, which is asserted in its own group below.
      final String id = await _openPanel(
        tester,
        pumped,
        GbmPanelKind.manageStashes,
      );

      expect(_closable(pumped), hasLength(1));
      expect(_location(tester), contains('/panel/$id'));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(
        _closable(pumped),
        isEmpty,
        reason: 'the tab is gone from the strip, not merely navigated away',
      );
      expect(
        _location(tester),
        isNot(contains('/panel/')),
        reason: 'a closed tab must not stay the current route',
      );
    });

    testWidgets('Cmd+W does the same, for macOS', (tester) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        extraRoutes: _panelRoute,
      );
      await _openPanel(tester, pumped, GbmPanelKind.manageRemotes);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(_closable(pumped), isEmpty);
    });

    testWidgets('it closes only the panel the shortcut was sent to', (
      tester,
    ) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        extraRoutes: _panelRoute,
      );
      await _openPanel(tester, pumped, GbmPanelKind.manageStashes);
      final String second = await _openPanel(
        tester,
        pumped,
        GbmPanelKind.manageRemotes,
      );

      expect(_closable(pumped), hasLength(2));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      final List<PanelTabSpec> left = _closable(pumped);
      expect(left, hasLength(1));
      expect(
        left.single.id,
        isNot(second),
        reason: 'the visible tab closes, not whichever was opened first',
      );
    });
  });

  // D7's fourth clause: 「Ctrl/Cmd+W 落在它身上時是 no-op」. The seeded
  // Worktrees tab is a real panel tab on a real route, so the binding does
  // fire on it -- what stops it is `_closeThisTab`'s own early return, not
  // the absence of a shortcut.
  group('D7: Ctrl/Cmd+W is a no-op on the pinned tab', () {
    testWidgets('the tab survives and the route does not change', (
      tester,
    ) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        extraRoutes: _panelRoute,
      );
      // Navigating to it, rather than opening it -- it is already open.
      final PanelTabSpec pinned = pumped.container
          .read(panelTabsProvider(_identity))
          .single;
      pumped.router.go(
        RoutePaths.panelFor(Uri.encodeComponent(_identity.workDir), pinned.id),
      );
      await tester.pumpAndSettle();
      expect(_location(tester), contains('/panel/${pinned.id}'));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(
        pumped.container.read(panelTabsProvider(_identity)).single.id,
        pinned.id,
        reason: 'the pinned tab is still in the strip',
      );
      // The half-action the early return exists to prevent: refusing the
      // close but navigating away anyway would leave the user on History
      // wondering what the keystroke did.
      expect(
        _location(tester),
        contains('/panel/${pinned.id}'),
        reason: 'and the user is still looking at it',
      );
    });
  });
}
