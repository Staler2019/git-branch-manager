// Safety net for removing the operation-log dialog (issue #61).
//
// Spec page 10's LOGRULES gained a "只有一套" row on 260820: "Log 只有底部抽屜
// 這一個實作（main.log splitter）。不另開 operation log dialog -- 同一份資料兩套
// 介面會各自漂移。" P14's IAMAP says the same in the other direction:
// operation-log dialog -> "刪除 -- 改走 P10 底部抽屜".
//
// Deleting a live route is only safe if the surviving carrier is genuinely
// reachable, so this test is written BEFORE the removal and asserts the
// drawer's own entry point works: View -> Log (Ctrl/Cmd+Shift+L, bound in
// gbm_shortcuts.dart to GbmActionId.viewLog) really expands the drawer and
// really shows the operation log's contents.
//
// It has to assert on *size*, not on presence: LogDrawer is always mounted
// as pane 0 of the main.log GbmSplitPane, and GbmLayout.splitterMainLog is
// `collapsedByDefault: true, defaultExtent: 0, minExtent: 90` -- so
// `find.byType(LogDrawer)` matches whether or not the drawer is open, and
// only its rendered height distinguishes the two states.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/panel_layout_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/log_drawer/log_drawer.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

OperationRecord _record(String commandLine) => OperationRecord(
  whenEpochMs: 0,
  repoDir: '/test/repo',
  argv: commandLine.split(' '),
  commandLine: commandLine,
  exitCode: 0,
  durationMs: 12,
  stderrText: '',
  cancelled: false,
  timedOut: false,
);

// pumpWorkspace always passes isMacOS: false unless overridden, so the
// bound chord is Ctrl+Shift+L (see gbm_shortcuts.dart's _makeShortcut).
Future<void> _pressCtrlShiftL(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyL);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyL);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  group('View > Log / Ctrl+Shift+L reaches the log drawer', () {
    testWidgets('the drawer starts collapsed and the shortcut expands it', (
      tester,
    ) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: RepoSessionState(
          isOpen: true,
          operationLog: <OperationRecord>[_record('git status --porcelain')],
        ),
      );

      // collapsedByDefault: true -> pane 0 has no extent yet.
      expect(tester.getSize(find.byType(LogDrawer)).height, 0);

      await _pressCtrlShiftL(tester);

      // _openToMinimum() expands to at least GbmLayout.splitterMainLog's
      // minExtent (90).
      expect(
        tester.getSize(find.byType(LogDrawer)).height,
        greaterThanOrEqualTo(90),
      );
    });

    // 使用者回報:「log沒辦法隱藏，view>log那個沒有作用，沒有toggle的效果」--
    // the action only ever called GbmSplitPaneController.open(), and the
    // controller had no close() at all, so the drawer was a one-way door:
    // once open, the only way back was dragging the divider.
    testWidgets('pressing it again collapses the drawer', (tester) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: RepoSessionState(
          isOpen: true,
          operationLog: <OperationRecord>[_record('git status --porcelain')],
        ),
      );

      await _pressCtrlShiftL(tester);
      expect(
        tester.getSize(find.byType(LogDrawer)).height,
        greaterThanOrEqualTo(90),
      );

      await _pressCtrlShiftL(tester);
      expect(tester.getSize(find.byType(LogDrawer)).height, 0);

      // And it is a toggle, not a one-shot close: a third press reopens.
      await _pressCtrlShiftL(tester);
      expect(
        tester.getSize(find.byType(LogDrawer)).height,
        greaterThanOrEqualTo(90),
      );
    });

    // 使用者裁定:「log不預設打開，使用者toggle才開」-- and the reason the first
    // test above could not see the defect is that it pumps a *virgin*
    // profile. `collapsedByDefault` only reached its `initialExtent = 0`
    // branch when nothing was stored, so a single previous open (which
    // persists an extent) made the drawer come back open on every launch
    // afterwards, forever. Seeding the stored extent is the whole of what
    // makes this test able to disagree with the code.
    testWidgets('a stored extent does not reopen the drawer at startup', (
      tester,
    ) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        // What a previous session that dragged the drawer to 200px left.
        initialPrefs: <String, Object>{'panelLayout.main.log': '[200.0]'},
        initialState: RepoSessionState(
          isOpen: true,
          operationLog: <OperationRecord>[_record('git status --porcelain')],
        ),
      );

      expect(tester.getSize(find.byType(LogDrawer)).height, 0);

      // ...and the height is *remembered*, not discarded: the toggle brings
      // back the 200 the user dragged to, not a reset to minExtent (90).
      await _pressCtrlShiftL(tester);
      expect(tester.getSize(find.byType(LogDrawer)).height, 200);

      // Closing must not overwrite that remembered height with 0, or the
      // next launch reopens at minExtent instead. For a collapsedByDefault
      // pane, storage holds the height and never the open/closed state --
      // the state is 「collapsed」 by definition at every startup.
      await _pressCtrlShiftL(tester);
      expect(tester.getSize(find.byType(LogDrawer)).height, 0);
      expect(
        pumped.container.read(panelLayoutRepositoryProvider).read('main.log'),
        <double>[200.0],
      );
    });

    // Asserts the seam only -- that session.operationLog is what the drawer
    // is handed. How the drawer renders/filters/exports those records is
    // covered at the widget tier by test/features/log_drawer/
    // log_drawer_test.dart, and re-asserting it here would just duplicate
    // it (and be brittle: at minExtent the ListView has almost no height,
    // so its rows are not built at all).
    testWidgets('the drawer is fed the session operation log', (tester) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: RepoSessionState(
          isOpen: true,
          operationLog: <OperationRecord>[
            _record('git rev-parse --absolute-git-dir'),
            _record('git status --porcelain'),
          ],
        ),
      );

      await _pressCtrlShiftL(tester);

      // The capability the deleted dialog provided -- reading back every
      // git invocation this session made -- survives in the drawer.
      final LogDrawer drawer = tester.widget<LogDrawer>(find.byType(LogDrawer));
      expect(drawer.records.map((GbmLogEntry e) => e.message), <String>[
        'git rev-parse --absolute-git-dir',
        'git status --porcelain',
      ]);
    });
  });
}
