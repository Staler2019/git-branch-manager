// BisectPanel against spec page 19's PANELSPEC row for bisect:
//
//   list:    已標記的 good / bad 步驟
//   detail:  目前待測 commit、剩餘步數、自訂測試指令
//   toolbar: Good、Bad、Skip、Reset
//
// 剩餘步數 and 自訂測試指令 are absent (no capi backs either) -- see
// BisectPanel's class doc. Start lives in the not-running state rather than
// the toolbar, which is what most of these tests actually pin down.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/bisect_status.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/bisect_panel.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const BisectStatus _running = BisectStatus(
  active: true,
  currentOid: 'cccccccdddd',
  badOid: 'bbbbbbbaaaa',
  goodOids: <String>['9999999eeee'],
  skippedOids: <String>['7777777ffff'],
  logText: '# bad: [bbbbbbbaaaa] broke it',
);

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  BisectStatus status = _running,
}) => pumpPanel(
  tester,
  BisectPanel(identity: panelTestIdentity),
  state: RepoSessionState(isOpen: true, bisectStatus: status),
);

Future<void> _fillLabelled(
  WidgetTester tester,
  String label,
  String value,
) async {
  await tester.enterText(
    find.ancestor(of: find.text(label), matching: find.byType(TextField)),
    value,
  );
  await tester.pumpAndSettle();
}

Future<void> _filter(WidgetTester tester, String query) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(PanelFilterField),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('BisectPanel (spec P19 PANELSPEC)', () {
    testWidgets('the toolbar carries PANELSPEC\'s four actions', (
      tester,
    ) async {
      await _pump(tester);

      for (final String label in const <String>[
        'Good',
        'Bad',
        'Skip',
        'Reset',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the list shows every marked step with its mark', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('bbbbbbbaaaa'), findsOneWidget);
      expect(find.text('bad'), findsOneWidget);
      expect(find.text('9999999eeee'), findsOneWidget);
      expect(find.text('good'), findsOneWidget);
      expect(find.text('7777777ffff'), findsOneWidget);
      expect(find.text('skipped'), findsOneWidget);
    });

    testWidgets('the detail names the commit currently under test', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Now testing'), findsOneWidget);
      expect(find.text('cccccccdddd'), findsOneWidget);
    });

    // Good/Bad/Skip act on HEAD, not on a list selection -- git chose the
    // commit, the user only reports the verdict.
    testWidgets('Good marks HEAD without needing a selection', (tester) async {
      final PumpedPanel pumped = await _pump(tester);
      await tester.tap(find.text('Good'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'markBisect',
      );
      expect(cmd.args['good'], isTrue);
      expect(cmd.args['ref'], '');
    });

    testWidgets('Bad marks HEAD as bad', (tester) async {
      final PumpedPanel pumped = await _pump(tester);
      await tester.tap(find.text('Bad'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'markBisect',
      );
      expect(cmd.args['good'], isFalse);
    });

    // With no bisect running, every one of the four would fail.
    testWidgets('all four are disabled when no bisect is running', (
      tester,
    ) async {
      await _pump(tester, status: BisectStatus.empty);

      for (final String label in const <String>[
        'Good',
        'Bad',
        'Skip',
        'Reset',
      ]) {
        expect(panelButton(tester, label).onPressed, isNull, reason: label);
      }
    });

    // Start needs two refs and only means anything while stopped, so it is
    // the not-running state's own form rather than a fifth toolbar button.
    testWidgets('the not-running state offers a start form, not a button', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        status: BisectStatus.empty,
      );

      expect(find.text('No bisect in progress'), findsWidgets);
      // Scoped by label. These were `.first`/`.last`, which is the
      // *dangerous* form of this round's recurring finder trap: the
      // toolbar's filter is a TextField too and sits before both of these
      // in the tree, so `.first` would have silently typed 「HEAD」 into the
      // filter and left the bad-ref box empty -- and the test would still
      // have passed, because startBisect was dispatched either way
      // ([TEST-design-system-swap-breaks-finders]).
      await _fillLabelled(tester, 'Known bad (empty = HEAD)', 'HEAD');
      await _fillLabelled(tester, 'Known good', 'v1.0');
      await tester.tap(find.text('Start bisect'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'startBisect',
      );
      expect(cmd.args['badRef'], 'HEAD');
      expect(cmd.args['goodRefs'], <String>['v1.0']);
    });

    // git accepts a bisect with no good ref yet -- it waits for the first
    // `bisect good` -- so an empty field must not become [''].
    testWidgets('an empty good ref starts with no good refs at all', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        status: BisectStatus.empty,
      );

      await tester.tap(find.text('Start bisect'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'startBisect',
      );
      expect(cmd.args['goodRefs'], isEmpty);
    });

    testWidgets('the toolbar follows P19 rule 2\'s four segments', (
      tester,
    ) async {
      await _pump(tester);

      expectPanelTemplate(
        tester,
        // **No primary segment.** Rule 2's first segment is 主要建立動作,
        // and the only action here that creates anything is `Start bisect`
        // -- which is not on the toolbar: it needs two refs, so it lives in
        // the not-running state's own form (the same call LfsPanel makes
        // for `Install`). An empty segment draws no placeholder, which is
        // exactly what stops a read-only panel growing a fake primary.
        maintenance: const <String>['Good', 'Bad', 'Skip', 'Reset'],
        // Reset stays on the toolbar: it ends the bisect and puts HEAD back
        // where it was, which restores a prior state rather than destroying
        // work. It keeps danger styling all the same.
        dangerOnToolbar: const <String>{'Reset'},
        listHeader: 'Marked steps · 3',
        statusBar: RegExp(r'^3 steps$'),
      );
    });

    // Undisputed gap 1: these rows were a bare Padding + Row, so they had
    // none of rule 3's row shape and nothing else in the app could style
    // them consistently.
    testWidgets('every marked step is a PanelListRow', (tester) async {
      await _pump(tester);

      expect(find.byType(PanelListRow), findsNWidgets(3));
    });

    // Undisputed gap 2: the rows were not selectable at all, so this was
    // the one panel of the twelve whose left list did not drive its right
    // detail -- P19's whole shape.
    testWidgets('selecting a marked step describes that step, not HEAD', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.text('Now testing'), findsOneWidget);

      await tester.tap(find.text('9999999eeee'));
      await tester.pumpAndSettle();

      expect(find.text('Marked'), findsOneWidget);
      expect(find.text('good'), findsWidgets);
      expect(find.text('Now testing'), findsNothing);
      // Session-level fields describe the bisect, not the selection, so
      // they survive it.
      expect(find.text('Marked so far'), findsOneWidget);
    });

    testWidgets('the filter narrows the list, the header and the status line', (
      tester,
    ) async {
      await _pump(tester);

      await _filter(tester, '9999999');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('Marked steps · 1'), findsOneWidget);
      expect(find.text('3 steps · 命中 1'), findsOneWidget);
    });

    // The discriminating case. Every oid in this fixture is hex, so 「good」
    // appears in no oid at all -- it is the only kind of query that tells
    // an oid-only filter apart from one that also reads the mark
    // ([TEST-fixture-cannot-disagree]). A query like 「9999999」 is answered
    // identically by both.
    testWidgets('the mark is filterable, not just the oid', (tester) async {
      await _pump(tester);

      await _filter(tester, 'good');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('9999999eeee'), findsOneWidget);
    });

    // With no bisect running the list is a form, so there is nothing to
    // filter -- disabled with a stated reason rather than live and inert.
    testWidgets('the filter is disabled while no bisect is running', (
      tester,
    ) async {
      await _pump(tester, status: BisectStatus.empty);

      final PanelFilterField filter = tester.widget<PanelFilterField>(
        find.byType(PanelFilterField),
      );
      expect(filter.enabled, isFalse);
      expect(filter.disabledReason, isNotEmpty);
    });

    testWidgets('a running bisect with nothing marked explains what to do', (
      tester,
    ) async {
      await _pump(
        tester,
        status: const BisectStatus(
          active: true,
          currentOid: 'aaa',
          badOid: '',
          goodOids: <String>[],
          skippedOids: <String>[],
          logText: '',
        ),
      );

      expect(find.textContaining('Nothing marked yet'), findsOneWidget);
    });
  });
}
