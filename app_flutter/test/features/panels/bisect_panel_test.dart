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
      await tester.enterText(find.byType(TextField).first, 'HEAD');
      await tester.enterText(find.byType(TextField).last, 'v1.0');
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
