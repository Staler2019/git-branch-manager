// LineHistoryPanel against spec page 19's PANELSPEC row for line-history:
//
//   list:    選定行區的演化
//   detail:  每一步的前後對照
//   toolbar: 擴大行區、跳到 commit
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/line_history_chunk.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/line_history_panel.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/features/panels/panel_diff_text.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const Signature _who = Signature(
  name: 'Ada',
  email: 'ada@example.com',
  when: 1755000000,
  tzOffsetMinutes: 0,
);

const LineHistoryChunk _step = LineHistoryChunk(
  oid: 'aaaaaaa',
  author: _who,
  subject: 'rewrite the guard',
  diffText: '@@ -10,3 +10,3 @@\n-old line\n+new line\n context',
);

/// A second step, so the filter tests have something to narrow *away*.
/// Its oid shares no substring with [_step]'s and its subject shares no word,
/// which is what lets one query separate them.
const LineHistoryChunk _earlier = LineHistoryChunk(
  oid: 'bbbbbbb',
  author: _who,
  subject: 'introduce the helper',
  diffText: '@@ -10,1 +10,3 @@\n+helper\n',
);

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

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<LineHistoryChunk> chunks = const <LineHistoryChunk>[_step],
  int from = 10,
  int to = 12,
}) => pumpPanel(
  tester,
  LineHistoryPanel(
    identity: panelTestIdentity,
    path: 'lib/main.dart',
    initialStartLine: from,
    initialEndLine: to,
  ),
  state: RepoSessionState(isOpen: true, lastLineHistory: chunks),
  extraRoutes: <RouteBase>[
    GoRoute(
      path: RoutePaths.history,
      builder: (context, state) => const Scaffold(body: Text('history-page')),
    ),
  ],
);

void main() {
  group('LineHistoryPanel (spec P19 PANELSPEC)', () {
    testWidgets('the toolbar carries PANELSPEC\'s two actions', (tester) async {
      await _pump(tester);

      expect(find.text('Widen range'), findsOneWidget);
      expect(find.text('Go to commit'), findsOneWidget);
    });

    testWidgets('the panel requests the initial range on mount', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestLineHistory',
      );
      expect(cmd.args['path'], 'lib/main.dart');
      expect(cmd.args['startLine'], 10);
      expect(cmd.args['endLine'], 12);
    });

    testWidgets('the list shows each step in the range\'s evolution', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('rewrite the guard'), findsOneWidget);
    });

    testWidgets('the detail pane is empty until a step is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.text('Select a step to see its before/after'),
        findsOneWidget,
      );
      expect(find.byType(PanelDiffText), findsNothing);
    });

    // git's `log -L` output is text, not a ParsedDiff, so the detail is the
    // text renderer rather than DiffPage.
    testWidgets('selecting a step renders its diff text', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('rewrite the guard'));
      await tester.pumpAndSettle();

      expect(find.byType(PanelDiffText), findsOneWidget);
      expect(find.text('+new line'), findsOneWidget);
      expect(find.text('-old line'), findsOneWidget);
    });

    testWidgets('Widen range re-requests a larger range', (tester) async {
      final PumpedPanel pumped = await _pump(tester);
      await tester.tap(find.text('Widen range'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestLineHistory',
      );
      expect(cmd.args['startLine'], 1);
      expect(cmd.args['endLine'], 22);
    });

    // git's line numbers are 1-based; asking for line 0 is an error, not
    // "the beginning of the file".
    testWidgets('Widen range never asks for a line below 1', (tester) async {
      final PumpedPanel pumped = await _pump(tester, from: 2, to: 3);
      await tester.tap(find.text('Widen range'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestLineHistory',
      );
      expect(cmd.args['startLine'], 1);
    });

    testWidgets('Go to commit is disabled until a step is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(panelButton(tester, 'Go to commit').onPressed, isNull);
    });

    testWidgets('Go to commit selects that commit and navigates to History', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);
      await tester.tap(find.text('rewrite the guard'));
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

    testWidgets('a range no commit touched says so', (tester) async {
      await _pump(tester, chunks: const <LineHistoryChunk>[]);

      expect(find.text('No commits touched these lines'), findsOneWidget);
    });
    testWidgets('the toolbar follows P19 rule 2\'s four segments', (
      tester,
    ) async {
      await _pump(tester);

      expectPanelTemplate(
        tester,
        // **No primary segment.** A line history creates nothing.
        // `Widen range` changes what *this panel* shows, so it is
        // maintenance; only `Go to commit` leaves for History.
        maintenance: const <String>['Widen range'],
        external: const <String>['Go to commit'],
        listHeader: 'Commits · 1',
        statusBar: RegExp(r'^1 commit$'),
      );
    });

    // **The filter is live here, and the round's own plan said it would be
    // disabled.** The plan grouped this panel with `blame` as 「左清單是檔案
    // 內容」 — but a LineHistoryChunk carries `oid`, `author` and `subject`,
    // and the row draws a subject over an author and a date. That is the
    // same shape as `file-history`, not the same shape as blame's raw file
    // lines, so there is plenty to filter and nothing an order could be
    // wrong about ([CULT-scrutinise-the-comment]).
    testWidgets('the filter narrows the list, the header and the status line', (
      tester,
    ) async {
      await _pump(tester, chunks: const <LineHistoryChunk>[_step, _earlier]);
      expect(find.byType(PanelListRow), findsNWidgets(2));

      await _filter(tester, 'helper');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('introduce the helper'), findsOneWidget);
      expect(find.text('Commits · 1'), findsOneWidget);
      expect(find.text('2 commits · 命中 1'), findsOneWidget);
    });

    // The discriminating case, the same shape as reflog's and
    // file-history's: a row draws the subject, the author and the date and
    // never the oid, so 「bbbbbbb」 is in no rendered text
    // ([TEST-fixture-cannot-disagree]).
    testWidgets('a step is findable by an oid the row never draws', (
      tester,
    ) async {
      await _pump(tester, chunks: const <LineHistoryChunk>[_step, _earlier]);

      await _filter(tester, 'bbbbbbb');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('introduce the helper'), findsOneWidget);
    });

    // The selection is keyed on the *unfiltered* index. Keyed on the
    // filtered one, narrowing the list silently moves the highlight onto a
    // different commit -- and the detail, which indexes into the unfiltered
    // list, would then disagree with the row that looks selected.
    //
    // Found by mutation: the panel's own comment claimed this and nothing
    // asserted it, so `chunks.indexOf(visible[i])` -> `i` came back fully
    // green -- the same shape as the fake-primary hole in `blame`.
    testWidgets('a selected step stays selected when the filter hides others', (
      tester,
    ) async {
      await _pump(tester, chunks: const <LineHistoryChunk>[_step, _earlier]);
      await tester.tap(find.text('introduce the helper'));
      await tester.pumpAndSettle();
      expect(find.text('+helper'), findsOneWidget);

      // Only the selected one survives, and it lands at filtered index 0
      // while its real index is 1 -- which is what tells the two keyings
      // apart.
      await _filter(tester, 'helper');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(
        tester.widget<PanelListRow>(find.byType(PanelListRow)).selected,
        isTrue,
        reason: 'the highlight must follow the commit, not the row number',
      );
      expect(find.text('+helper'), findsOneWidget);
    });

    testWidgets('a filter that hides everything says so, not "none touched"', (
      tester,
    ) async {
      await _pump(tester);

      await _filter(tester, 'zzz');

      expect(find.text('No commit matches the filter'), findsOneWidget);
      expect(find.text('No commits touched these lines'), findsNothing);
    });
  });
}
