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
import 'package:flutter/material.dart';
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

/// Every command [RepoSessionController.refreshRepoStatus] dispatches. Kept
/// here rather than imported from the focus-refresh test so that a change to
/// the sweep has to be acknowledged in both places -- these two files assert
/// the same composition arriving down two entirely different paths (a
/// lifecycle event, and a keypress/menu selection).
const List<String> _sweepCommands = <String>[
  'refreshRepoState',
  'refreshHasCommitGraph',
  'refreshHistory',
  'refreshWorkingCopy',
  'refreshStashes',
  'refreshWorktrees',
  'refreshRemotes',
  'refreshSubmodules',
  'refreshBisectStatus',
  'refreshLfs',
  'refreshLocalIdentity',
  'refreshEffectiveIdentity',
];

int _count(List<FakeCommand> log, String name) =>
    log.where((FakeCommand c) => c.name == name).length;

Map<String, int> _tally(List<FakeCommand> log) => <String, int>{
  for (final String name in _sweepCommands) name: _count(log, name),
};

/// Walks the PlatformMenu tree for a leaf with [label], since
/// `PlatformMenuItem` is not a Widget and no finder reaches it.
PlatformMenuItem? _findMenuItem(List<PlatformMenuItem> menus, String label) {
  for (final PlatformMenuItem item in menus) {
    if (item is PlatformMenu) {
      final PlatformMenuItem? found = _findMenuItem(item.menus, label);
      if (found != null) return found;
    } else if (item.label == label) {
      return item;
    }
  }
  return null;
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

    // F5 used to refresh only the history, so pressing it after editing a
    // file in another window left the Working Copy tab's pending badge, the
    // diff pane and the conflict state exactly as they were -- on the one
    // path where the user has explicitly *asked* for fresh state. It now
    // dispatches the same sweep the window-focus listener does; these two
    // tests are what stop the two drifting apart again.
    //
    // Deltas, not absolutes: opening a session refreshes on its own.
    testWidgets(
      'F5 (Refresh) re-reads every local git fact, not just history',
      (WidgetTester tester) async {
        final PumpedWorkspace pumped = await pumpWorkspace(
          tester,
          identity: identity,
        );
        final Map<String, int> before = _tally(pumped.controller.commandLog);

        await tester.sendKeyDownEvent(LogicalKeyboardKey.f5);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.f5);
        await tester.pumpAndSettle();

        final Map<String, int> after = _tally(pumped.controller.commandLog);
        for (final String name in _sweepCommands) {
          expect(
            after[name]! - before[name]!,
            1,
            reason: 'F5 must dispatch $name exactly once',
          );
        }
      },
    );

    // The third dispatch path. A PlatformMenuItem takes its callback straight
    // out of the same actionHandlers map, so wiring viewRefresh only in
    // MenuBarRow's params would leave this one null -- the exact shape of the
    // bug this file was created for.
    testWidgets(
      'the macOS system menu Refresh item dispatches the same sweep',
      (WidgetTester tester) async {
        final PumpedWorkspace pumped = await pumpWorkspace(
          tester,
          identity: identity,
          isMacOS: true,
        );
        final PlatformMenuBar bar = tester.widget<PlatformMenuBar>(
          find.byType(PlatformMenuBar),
        );
        final PlatformMenuItem? item = _findMenuItem(bar.menus, 'Refresh');
        expect(item, isNotNull, reason: 'View > Refresh must exist on macOS');
        expect(
          item!.onSelected,
          isNotNull,
          reason: 'a null handler is what greys the item out natively',
        );

        final Map<String, int> before = _tally(pumped.controller.commandLog);
        item.onSelected!();
        await tester.pumpAndSettle();

        final Map<String, int> after = _tally(pumped.controller.commandLog);
        for (final String name in _sweepCommands) {
          expect(after[name]! - before[name]!, 1, reason: 'system menu: $name');
        }
      },
    );

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
