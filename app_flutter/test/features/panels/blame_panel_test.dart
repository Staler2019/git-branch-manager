// BlamePanel against spec page 19's PANELSPEC row for blame:
//
//   list:    檔案內容（每行帶作者）
//   detail:  選到的行對應的 commit 明細
//   toolbar: 上一版、忽略空白、跳到 commit
//
// 忽略空白 is disabled (gbm_request_blame has no -w) and 上一版 needs the
// selected line's commit's *parent*, which only arrives with commit meta --
// both are decisions this pins down.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/blame_result.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/blame_panel.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const BlameLine _line1 = BlameLine(
  commitOid: 'aaaaaaa',
  authorName: 'Ada',
  authorEmail: 'ada@example.com',
  authorTime: 1755000000,
  summary: 'add the header',
  finalLine: 1,
  originalLine: 1,
  content: 'import foo;',
  boundary: false,
);

const BlameLine _line2 = BlameLine(
  commitOid: 'bbbbbbb',
  authorName: 'Grace',
  authorEmail: 'grace@example.com',
  authorTime: 1754000000,
  summary: 'tidy imports',
  finalLine: 2,
  originalLine: 2,
  content: 'import bar;',
  boundary: false,
);

const CommitMeta _metaOfLine2 = CommitMeta(
  oid: 'bbbbbbb',
  tree: 'ttt',
  parents: <String>['9999999'],
  author: Signature(
    name: 'Grace',
    email: 'grace@example.com',
    when: 1754000000,
    tzOffsetMinutes: 0,
  ),
  committer: Signature(
    name: 'Grace',
    email: 'grace@example.com',
    when: 1754000000,
    tzOffsetMinutes: 0,
  ),
  subject: 'tidy imports',
  body: '',
  signedCommit: false,
);

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<BlameLine> lines = const <BlameLine>[_line1, _line2],
  Map<String, CommitMeta> meta = const <String, CommitMeta>{},
}) => pumpPanel(
  tester,
  BlamePanel(identity: panelTestIdentity, path: 'lib/main.dart'),
  state: RepoSessionState(
    isOpen: true,
    lastBlame: BlameResult(lines: lines, truncated: false),
    commitMetaCache: meta,
  ),
  extraRoutes: <RouteBase>[
    GoRoute(
      path: RoutePaths.history,
      builder: (context, state) => const Scaffold(body: Text('history-page')),
    ),
  ],
);

void main() {
  group('BlamePanel (spec P19 PANELSPEC)', () {
    testWidgets('the toolbar carries PANELSPEC\'s three actions', (
      tester,
    ) async {
      await _pump(tester);

      for (final String label in const <String>[
        'Previous revision',
        'Ignore whitespace',
        'Go to commit',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the list shows each line with its author and content', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('import foo;'), findsOneWidget);
      expect(find.text('Ada'), findsOneWidget);
      expect(find.text('import bar;'), findsOneWidget);
      expect(find.text('Grace'), findsOneWidget);
    });

    // No -w in gbm_request_blame, so the control says so instead of
    // silently doing nothing.
    testWidgets('Ignore whitespace is permanently disabled and says why', (
      tester,
    ) async {
      await _pump(tester);

      expect(panelButton(tester, 'Ignore whitespace').onPressed, isNull);
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: find.text('Ignore whitespace'),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        contains('not supported'),
      );
    });

    testWidgets('the detail shows the selected line\'s commit', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('import bar;'));
      await tester.pumpAndSettle();

      expect(find.text('Line'), findsOneWidget);
      expect(find.text('bbbbbbb'), findsOneWidget);
      expect(find.text('tidy imports'), findsOneWidget);
    });

    // BlameLine has the commit but not its parent, so walking back has to
    // wait for commit meta rather than guess a revision.
    testWidgets('Previous revision stays disabled until the parent is known', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('import bar;'));
      await tester.pumpAndSettle();

      expect(panelButton(tester, 'Previous revision').onPressed, isNull);
    });

    testWidgets('Previous revision re-blames at the parent commit', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        meta: const <String, CommitMeta>{'bbbbbbb': _metaOfLine2},
      );
      await tester.tap(find.text('import bar;'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Previous revision'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestBlame',
      );
      expect(cmd.args['revision'], '9999999');
      // The list is about to be replaced, so the old line selection must go.
      expect(panelButton(tester, 'Go to commit').onPressed, isNull);
    });

    testWidgets('Go to commit selects the commit and navigates to History', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);
      await tester.tap(find.text('import foo;'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go to commit'));
      await tester.pumpAndSettle();

      expect(
        pumped.container
            .read(commitSelectionProvider(panelTestIdentity))
            .anchor,
        'aaaaaaa',
      );
      expect(find.text('history-page'), findsOneWidget);
    });

    testWidgets('the toolbar follows P19 rule 2\'s four segments', (
      tester,
    ) async {
      await _pump(tester);

      expectPanelTemplate(
        tester,
        // **No primary segment.** Nothing in a blame view creates anything;
        // it is a read-only surface. An empty segment draws no placeholder,
        // which is what stops a read-only panel growing a fake primary.
        //
        // `Previous revision` is maintenance rather than 「跳出去」: it
        // re-blames *inside this panel* rather than taking the user
        // anywhere. Only `Go to commit` leaves, which is the example
        // PanelToolbarSpec's own doc gives for that segment.
        maintenance: const <String>['Previous revision', 'Ignore whitespace'],
        external: const <String>['Go to commit'],
        listHeader: 'Lines · 2',
        statusBar: RegExp(r'^2 lines$'),
        filterEnabled: false,
      );
    });

    // This list is *file content*, not a named collection, so there is
    // nothing a name filter could match. Disabled with a stated reason
    // rather than hidden -- 隱藏會讓人以為功能不存在.
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

    testWidgets('a file with no blame information says so', (tester) async {
      await _pump(tester, lines: const <BlameLine>[]);

      expect(find.text('No blame information'), findsOneWidget);
    });
  });
}
