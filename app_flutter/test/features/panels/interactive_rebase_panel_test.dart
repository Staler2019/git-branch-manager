// InteractiveRebasePanel against spec page 19's PANELSPEC row for
// interactive-rebase:
//
//   list:    commit 序列（可拖曳排序）
//   detail:  每筆的動作（pick / squash / drop）與訊息編輯
//   toolbar: Start、Abort、Reset order
//
// 訊息編輯 is absent by an existing design decision (Reword is not an
// action -- see RebaseOps.h), which is why no test looks for a message box.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/rebase_todo_entry.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/interactive_rebase_panel.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';

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

/// The subjects as *painted*, top to bottom -- a reorder claim is about
/// render order, so it is read out of the tree rather than out of the model.
List<String> _subjectsInOrder(WidgetTester tester) {
  final List<String> subjects = <String>['add the guard', 'fix the guard'];
  final List<({double y, String subject})> found =
      subjects
          .where((String s) => find.text(s).evaluate().isNotEmpty)
          .map((String s) => (y: tester.getCenter(find.text(s)).dy, subject: s))
          .toList()
        ..sort((a, b) => a.y.compareTo(b.y));
  return found.map((e) => e.subject).toList();
}

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

      // Scoped by label: the toolbar's filter is a TextField too, and it
      // sits *before* this one in the tree, so the bare finder became
      // ambiguous the moment rule 2's filter slot was filled. The fourth
      // instance of this trap in the round
      // ([TEST-design-system-swap-breaks-finders]); this one reds loudly
      // rather than silently retargeting, because two matches is an error.
      await tester.enterText(
        find.ancestor(
          of: find.text('Upstream (e.g. main)'),
          matching: find.byType(TextField),
        ),
        'main',
      );
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

    testWidgets('the toolbar follows P19 rule 2\'s four segments', (
      tester,
    ) async {
      await _pump(tester);

      expectPanelTemplate(
        tester,
        primary: const <String>['Start'],
        maintenance: const <String>['Abort', 'Reset order'],
        // Abort stays on the toolbar (it restores the prior state rather
        // than destroying work, so rule 2's 破壞性 clause does not reach it)
        // while keeping the danger styling, because it is still the one
        // button here a user should hesitate over.
        dangerOnToolbar: const <String>{'Abort'},
        listHeader: 'Commits · 2',
        statusBar: RegExp(r'^2 commits$'),
        filterEnabled: false,
      );
    });

    // Rule 3 makes this list writable, and a filtered order is not the real
    // order -- dragging row 3 onto row 1 of a filtered view would reorder
    // against commits the user cannot see. So the filter is disabled *and
    // says why*, rather than hidden (隱藏會讓人以為功能不存在) or, worse,
    // live and wrong.
    testWidgets('the filter is disabled, and the tooltip says why', (
      tester,
    ) async {
      await _pump(tester);

      final PanelFilterField filter = tester.widget<PanelFilterField>(
        find.byType(PanelFilterField),
      );
      expect(filter.enabled, isFalse);
      expect(filter.disabledReason, isNotEmpty);
      expect(find.byTooltip(filter.disabledReason), findsOneWidget);
    });

    // The panel's entire purpose is editing the replay order, and until now
    // *nothing* asserted that a drag actually reorders -- there was no drag
    // test at all, only 「the list shows the plan in replay order」.
    // Asserting a ReorderableListView exists is not asserting that a drop
    // works ([TEST-draggable-is-not-a-drop]).
    //
    // The platform override is load-bearing: ReorderableListView builds a
    // trailing `Icons.drag_handle` wrapped in a ReorderableDragStartListener
    // on desktop, and a long-press listener over the whole row on mobile.
    // flutter_test reports android by default, so the default is the one
    // platform this desktop-only app never runs on -- and it is reset inside
    // the test body, because the no-debug-variable-outlived-the-test check
    // runs before tearDowns.
    testWidgets('dragging a row really reorders the plan Start would submit', (
      tester,
    ) async {
      // try/finally rather than a bare reset at the end: the reset has to
      // happen *in the test body* (the no-debug-variable-outlived-the-test
      // check runs before tearDowns), and without the finally a failure
      // anywhere below leaks the override and reddens the *next* test
      // instead -- which is exactly what the first run of this test did.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        final PumpedPanel pumped = await _pump(tester);

        expect(_subjectsInOrder(tester), <String>[
          'add the guard',
          'fix the guard',
        ]);

        final Finder handle = find.byIcon(Icons.drag_handle).first;
        final Offset from = tester.getCenter(handle);
        final double target = tester.getCenter(find.text('fix the guard')).dy;
        final TestGesture gesture = await tester.startGesture(from);
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
        await gesture.moveTo(Offset(from.dx, target + 10));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();

        expect(_subjectsInOrder(tester), <String>[
          'fix the guard',
          'add the guard',
        ]);

        // The reorder has to reach the plan Start submits, not just the
        // painted list -- the two are separate ([FLU-finder-proves-existence-
        // not-position] one level up: repainting is not dispatching).
        await tester.tap(find.text('Start'));
        await tester.pumpAndSettle();
        final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
          (FakeCommand c) => c.name == 'startInteractiveRebase',
        );
        expect(cmd.args['oids'], <String>[_second.oid, _first.oid]);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
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
