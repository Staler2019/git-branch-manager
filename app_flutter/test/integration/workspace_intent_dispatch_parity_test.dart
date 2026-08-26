// Regression test for a real dispatch-parity bug found while auditing
// action availability: WorkspaceScreen._buildActionHandlers() hardcodes
// `null` for repositoryFetch/Pull/Push and viewToggleSidebar in the
// actionHandlers map it hands to BOTH WorkspaceActionShortcuts (keyboard)
// and PlatformMenuBarHost (macOS system menu) -- because the real
// implementation is wired separately, through MenuBarRow's onFetch/onPull/
// onPush/onToggleSidebar params instead. MenuBarRow's own
// `_resolveHandler` special-cases those four ids and reads the params
// directly, so clicking the in-window menu item (or the toolbar button)
// still works. The keyboard shortcut and the macOS system menu item do
// not go through that special-casing -- they read the map, get `null`,
// and silently no-op.
//
// This test presses the real keyboard shortcuts through the real
// WorkspaceScreen (via pumpWorkspace, not a hand-fed handler map like
// workspace_action_shortcuts_test.dart uses) and asserts the underlying
// controller method actually fires. It is expected to fail (RED) before
// the fix in gbm_action_availability.dart's follow-up commit, which
// removes the hardcoded nulls and shares one real, policy-gated callback
// between the map and MenuBarRow's params.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

Future<void> _pressCtrl(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  final identity = RepoIdentity(
    workDir: '/test/repo',
    gitDir: '/test/repo/.git',
  );

  group('intent dispatch parity -- keyboard shortcut vs menu click', () {
    testWidgets(
      'Ctrl+Shift+F (Fetch) reaches RepoSessionController.fetchRemote',
      (tester) async {
        final pumped = await pumpWorkspace(tester, identity: identity);

        await _pressCtrl(tester, LogicalKeyboardKey.keyF, shift: true);

        expect(
          pumped.controller.commandLog.any((c) => c.name == 'fetchRemote'),
          isTrue,
          reason:
              'Ctrl+Shift+F should reach fetchRemote() the same way clicking '
              'Repository > Fetch does -- it currently no-ops because '
              'actionHandlers[repositoryFetch] is hardcoded null.',
        );
      },
    );

    testWidgets(
      'Ctrl+Shift+P (Pull) reaches RepoSessionController.pullChanges',
      (tester) async {
        final pumped = await pumpWorkspace(tester, identity: identity);

        await _pressCtrl(tester, LogicalKeyboardKey.keyP, shift: true);

        expect(
          pumped.controller.commandLog.any((c) => c.name == 'pullChanges'),
          isTrue,
          reason:
              'Ctrl+Shift+P should reach pullChanges() the same way '
              'clicking Repository > Pull does.',
        );
      },
    );

    testWidgets('Ctrl+P (Push) reaches RepoSessionController.pushChanges', (
      tester,
    ) async {
      final pumped = await pumpWorkspace(tester, identity: identity);

      await _pressCtrl(tester, LogicalKeyboardKey.keyP);

      expect(
        pumped.controller.commandLog.any((c) => c.name == 'pushChanges'),
        isTrue,
        reason:
            'Ctrl+P should reach pushChanges() the same way clicking '
            'Repository > Push does.',
      );
    });

    // Refresh had no keyboard binding and no menu item at all until this
    // round: TopBar's button was its only affordance in the whole window, and
    // deleting TopBar would have removed the feature rather than moving it.
    // Asserted here rather than in a widget test because the point is that the
    // *real* dispatch path reaches the controller -- a widget test feeding a
    // handler map directly cannot tell a wired id from an unwired one.
    testWidgets('F5 (Refresh) reaches RepoSessionController.refreshHistory', (
      WidgetTester tester,
    ) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: identity,
      );
      // Counted as a delta, not from zero: opening a session refreshes on its
      // own, so `== 1` from zero would be asserting something else. And
      // counted rather than `.any(...)`, which cannot see a double dispatch --
      // the regression shape this file already exists for.
      final int before = pumped.controller.commandLog
          .where((FakeCommand c) => c.name == 'refreshHistory')
          .length;

      await tester.sendKeyDownEvent(LogicalKeyboardKey.f5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();

      final int after = pumped.controller.commandLog
          .where((FakeCommand c) => c.name == 'refreshHistory')
          .length;
      expect(after - before, 1);
    });

    testWidgets('Ctrl+B (Toggle sidebar) actually hides SidebarPanel', (
      tester,
    ) async {
      await pumpWorkspace(tester, identity: identity);

      expect(find.byType(SidebarPanel), findsOneWidget);

      await _pressCtrl(tester, LogicalKeyboardKey.keyB);

      expect(
        find.byType(SidebarPanel),
        findsNothing,
        reason:
            'Ctrl+B should toggle the sidebar the same way clicking '
            'View > Toggle sidebar does -- it currently no-ops because '
            'actionHandlers[viewToggleSidebar] is hardcoded null.',
      );
    });
  });
}
