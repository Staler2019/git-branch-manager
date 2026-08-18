// Regression coverage for GbmActionId.viewNextTab: workspace_screen.dart's
// _buildActionHandlers() hardcoded this id to `null` even though
// gbm_shortcuts.dart binds Ctrl/Cmd+Tab to it and gbm_menu_model.dart draws
// "Next tab" under View -- so both the keyboard shortcut and the menu item
// rendered as live UI that silently did nothing on click/press, the same
// failure shape CLAUDE.md documents for the historical
// repositoryFetch/Pull/Push/viewToggleSidebar bug.
//
// This drives the real WorkspaceScreen behind pumpWorkspace (not a hand-fed
// handler map) so it exercises the actual GoRouter location the same way a
// user's keypress would, including wrapping through a Compare tab opened
// via the real compareTabsProvider.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

final List<RouteBase> _compareRoute = <RouteBase>[
  GoRoute(
    path: RoutePaths.compare,
    builder: (context, state) =>
        const Scaffold(body: SizedBox(key: Key('compare-stub'))),
  ),
];

String _location(WidgetTester tester) => GoRouterState.of(
  tester.element(find.byType(WorkspaceScreen)),
).uri.toString();

// pumpWorkspace always passes isMacOS: false unless overridden, so the
// bound shortcut is Ctrl+Tab (see gbm_shortcuts.dart's _makeShortcut).
Future<void> _pressCtrlTab(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

Future<void> _openCompareTab(WidgetTester tester) async {
  await tester.tap(find.text('Repository'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Compare…'));
  await tester.pumpAndSettle();
}

void main() {
  group('View > Next tab / Ctrl+Tab intent dispatch', () {
    testWidgets('Ctrl+Tab from History navigates to Working Copy', (
      tester,
    ) async {
      await pumpWorkspace(tester, identity: _identity);
      expect(
        _location(tester),
        RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
      );

      await _pressCtrlTab(tester);

      expect(
        _location(tester),
        RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
        reason:
            'Ctrl+Tab should advance to the next tab the same way View > '
            'Next tab does -- it currently no-ops because '
            'actionHandlers[viewNextTab] is hardcoded null.',
      );
    });

    testWidgets('Ctrl+Tab from the last tab wraps back around to History', (
      tester,
    ) async {
      await pumpWorkspace(tester, identity: _identity);

      await _pressCtrlTab(tester);
      expect(
        _location(tester),
        RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
      );

      await _pressCtrlTab(tester);

      expect(
        _location(tester),
        RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
      );
    });

    testWidgets(
      'Ctrl+Tab cycles through an open Compare tab between Working Copy '
      'and the wrap back to History',
      (tester) async {
        await pumpWorkspace(
          tester,
          identity: _identity,
          extraRoutes: _compareRoute,
        );

        await _openCompareTab(tester);
        expect(_location(tester), contains('/compare/'));
        final String compareLocation = _location(tester);

        await _pressCtrlTab(tester);

        expect(
          _location(tester),
          RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
          reason:
              'the newly-opened Compare tab is last in tab order, so '
              'the next tab after it wraps back to History.',
        );

        await _pressCtrlTab(tester);
        expect(
          _location(tester),
          RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
        );

        await _pressCtrlTab(tester);
        expect(_location(tester), compareLocation);
      },
    );
  });
}
