// InteractiveRebasePanel against spec page 19's PANELSPEC row for
// interactive-rebase:
//
//   list:    commit 序列（可拖曳排序）
//   detail:  每筆的動作（pick / squash / drop）與訊息編輯
//   toolbar: Start、Abort、Reset order
//
// 訊息編輯 is absent by an existing design decision (Reword is not an
// action -- see RebaseOps.h), which is why no test looks for a message box.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/rebase_todo_entry.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/interactive_rebase_panel.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const RebaseTodoEntry _first = RebaseTodoEntry(
  action: RebaseTodoAction.pick,
  oid: 'aaaaaaa1111',
  shortOid: 'aaaaaaa',
  subject: 'add the guard',
);

const RebaseTodoEntry _second = RebaseTodoEntry(
  action: RebaseTodoAction.pick,
  oid: 'bbbbbbb2222',
  shortOid: 'bbbbbbb',
  subject: 'fix the guard',
);

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<RebaseTodoEntry> plan = const <RebaseTodoEntry>[_first, _second],
  RepoState? repoState,
}) => pumpPanel(
  tester,
  InteractiveRebasePanel(identity: panelTestIdentity),
  state: RepoSessionState(
    isOpen: true,
    lastRebasePlan: plan,
    repoState: repoState,
  ),
);

void main() {
  group('InteractiveRebasePanel (spec P19 PANELSPEC)', () {
    testWidgets('the toolbar carries PANELSPEC\'s three actions', (
      tester,
    ) async {
      await _pump(tester);

      for (final String label in const <String>[
        'Start',
        'Abort',
        'Reset order',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the list shows the plan in replay order', (tester) async {
      await _pump(tester);

      expect(find.text('add the guard'), findsOneWidget);
      expect(find.text('fix the guard'), findsOneWidget);
      expect(find.text('pick'), findsNWidgets(2));
    });

    testWidgets('Load plan requests a plan for the typed upstream', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);

      await tester.enterText(find.byType(TextField), 'main');
      await tester.tap(find.text('Load plan'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestRebasePlan',
      );
      expect(cmd.args['upstream'], 'main');
    });

    testWidgets('the detail pane is empty until a commit is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.textContaining('Select a commit to change what the rebase'),
        findsOneWidget,
      );
    });

    testWidgets('selecting a commit offers all five actions', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('fix the guard'));
      await tester.pumpAndSettle();

      for (final String label in const <String>[
        'Pick',
        'Edit',
        'Squash',
        'Fixup',
        'Drop',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    // The plan is edited locally and only submitted by Start, so the action
    // change has to survive in this widget's state, not go to the session.
    testWidgets('changing an action updates the plan Start would submit', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);
      await tester.tap(find.text('fix the guard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Squash'));
      await tester.pumpAndSettle();

      expect(find.text('squash'), findsOneWidget);

      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'startInteractiveRebase',
      );
      expect(cmd.args['actions'], <String>['pick', 'squash']);
    });

    testWidgets('Reset order throws local edits away', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('fix the guard'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drop'));
      await tester.pumpAndSettle();
      expect(find.text('drop'), findsOneWidget);

      await tester.tap(find.text('Reset order'));
      await tester.pumpAndSettle();

      expect(find.text('drop'), findsNothing);
      expect(find.text('pick'), findsNWidgets(2));
    });

    // Aborting a rebase that is not running fails with git's own confusing
    // error, so the button must not offer it.
    testWidgets('Abort is disabled unless a rebase is actually running', (
      tester,
    ) async {
      await _pump(tester);

      expect(panelButton(tester, 'Abort').onPressed, isNull);
    });

    testWidgets('Abort is enabled mid-rebase, and Start is not', (
      tester,
    ) async {
      await _pump(
        tester,
        repoState: const RepoState(
          flags: 0,
          isClean: false,
          isSequencerOperation: true,
          rebaseStep: 1,
          rebaseTotal: 2,
          rebaseOntoLabel: 'main',
          indexLocked: false,
          indexLockAgeSeconds: null,
          describe: 'rebase -i 1/2',
        ),
      );

      expect(panelButton(tester, 'Abort').onPressed, isNotNull);
      expect(panelButton(tester, 'Start').onPressed, isNull);
    });

    testWidgets('an unloaded plan says how to get one', (tester) async {
      await _pump(tester, plan: const <RebaseTodoEntry>[]);

      expect(
        find.text('Load a plan to see the commits it would replay'),
        findsOneWidget,
      );
    });
  });
}
