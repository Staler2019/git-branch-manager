// FileHistoryPanel against spec page 19's PANELSPEC row for file-history:
//
//   list:    該檔的 commit 清單
//   detail:  逐版 diff（唯讀）
//   toolbar: 欄位選擇器、含重命名、Compare
//
// 含重命名 is not a toggle (gbm_request_file_history always follows renames)
// and 欄位選擇器 is absent -- see FileHistoryPanel's class doc.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/file_history_entry.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/diff/diff_page.dart';
import 'package:gbm_flutter/features/panels/file_history_panel.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
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

const FileHistoryEntry _latest = FileHistoryEntry(
  oid: 'aaaaaaa',
  author: _who,
  subject: 'tidy the header',
  status: 'M',
  renamedFrom: '',
);

const FileHistoryEntry _renamed = FileHistoryEntry(
  oid: 'bbbbbbb',
  author: _who,
  subject: 'rename it',
  status: 'R100',
  renamedFrom: 'lib/old_main.dart',
);

const ParsedDiff _diff = ParsedDiff(
  files: <DiffFile>[
    DiffFile(
      oldPath: 'lib/main.dart',
      newPath: 'lib/main.dart',
      kind: FileChangeKind.modified,
      oldMode: '100644',
      newMode: '100644',
      oldBlob: 'a',
      newBlob: 'b',
      binary: false,
      similarity: 0,
      addedLines: 1,
      removedLines: 1,
      displayPath: 'lib/main.dart',
      hunks: <DiffHunk>[],
    ),
  ],
  truncated: false,
  inputBytes: 10,
);

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<FileHistoryEntry> entries = const <FileHistoryEntry>[_latest, _renamed],
  ParsedDiff? diff,
}) => pumpPanel(
  tester,
  FileHistoryPanel(identity: panelTestIdentity, path: 'lib/main.dart'),
  state: RepoSessionState(
    isOpen: true,
    lastFileHistory: entries,
    selectedCommitFileDiff: diff,
  ),
  extraRoutes: <RouteBase>[
    GoRoute(
      path: RoutePaths.compare,
      builder: (context, state) => const Scaffold(body: Text('compare-page')),
    ),
  ],
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

void main() {
  group('FileHistoryPanel (spec P19 PANELSPEC)', () {
    testWidgets('the list shows each commit that touched the file', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('tidy the header'), findsOneWidget);
      expect(find.text('rename it'), findsOneWidget);
    });

    testWidgets('the panel asks for this file\'s history on mount', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestFileHistory',
      );
      expect(cmd.args['path'], 'lib/main.dart');
    });

    // The follow is unconditional in the capi, so a switch would be a lie.
    testWidgets('Renames followed is a disabled indicator, not a toggle', (
      tester,
    ) async {
      await _pump(tester);

      expect(panelButton(tester, 'Renames followed').onPressed, isNull);
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: find.text('Renames followed'),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        contains('always follows renames'),
      );
    });

    testWidgets('a rename is called out in the list row', (tester) async {
      await _pump(tester);

      expect(
        find.textContaining('renamed from lib/old_main.dart'),
        findsOneWidget,
      );
    });

    testWidgets('the detail pane is empty until a commit is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.text('Select a commit to see how it changed this file'),
        findsOneWidget,
      );
    });

    testWidgets('selecting a commit requests and renders its diff', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester, diff: _diff);
      await tester.tap(find.text('tidy the header'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestCommitFileDiff',
      );
      expect(cmd.args['oid'], 'aaaaaaa');
      expect(cmd.args['path'], 'lib/main.dart');
      expect(find.byType(DiffPage), findsOneWidget);
    });

    // Asking for the current name inside a commit that predates the rename
    // returns nothing, so the request has to use the old path.
    testWidgets('a renamed entry asks for the diff under its old path', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester, diff: _diff);
      await tester.tap(find.text('rename it'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestCommitFileDiff',
      );
      expect(cmd.args['path'], 'lib/old_main.dart');
    });

    testWidgets('Compare… is disabled until a commit is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(panelButton(tester, 'Compare…').onPressed, isNull);
    });

    // Only the left side is filled; the Compare page's own ref picker takes
    // the right, the convention sidebar_panel's _compareTag established.
    testWidgets('Compare… opens a Compare tab anchored at that commit', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester, diff: _diff);
      await tester.tap(find.text('tidy the header'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compare…'));
      await tester.pumpAndSettle();

      final List<CompareTabSpec> tabs = pumped.container.read(
        compareTabsProvider(panelTestIdentity),
      );
      expect(tabs, hasLength(1));
      expect(tabs.single.left, 'aaaaaaa');
      expect(tabs.single.right, isNull);
      expect(find.text('compare-page'), findsOneWidget);
    });

    testWidgets('a file with no history says so', (tester) async {
      await _pump(tester, entries: const <FileHistoryEntry>[]);

      expect(find.text('No commits touched this file'), findsOneWidget);
    });
    testWidgets('the toolbar follows P19 rule 2\'s four segments', (
      tester,
    ) async {
      await _pump(tester);

      expectPanelTemplate(
        tester,
        // **No primary segment.** A file history creates nothing; the
        // 欄位選擇器 PANELSPEC names has no backing capi and is absent
        // rather than faked (see the class doc), so 「Renames followed」 is
        // the whole maintenance segment.
        maintenance: const <String>['Renames followed'],
        // Compare… opens a Compare tab and navigates to it, which is
        // exactly PanelToolbarSpec's 「跳出去」.
        external: const <String>['Compare…'],
        listHeader: 'Commits · 2',
        statusBar: RegExp(r'^2 commits$'),
      );
    });

    testWidgets('the filter narrows the list, the header and the status line', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byType(PanelListRow), findsNWidgets(2));

      await _filter(tester, 'rename it');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('Commits · 1'), findsOneWidget);
      expect(find.text('2 commits · 命中 1'), findsOneWidget);
    });

    // The discriminating case. A row draws the subject, the author and the
    // date -- never the oid -- so 「bbbbbbb」 appears in no rendered text,
    // and it is the only kind of query that tells a subject-only filter
    // apart from one that also reads the oid
    // ([TEST-fixture-cannot-disagree]).
    testWidgets('a commit is findable by an oid the row never draws', (
      tester,
    ) async {
      await _pump(tester);

      await _filter(tester, 'bbbbbbb');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('rename it'), findsOneWidget);
    });

    testWidgets('a filter that hides everything says so, not "none touched"', (
      tester,
    ) async {
      await _pump(tester);

      await _filter(tester, 'zzz');

      expect(find.text('No commit matches the filter'), findsOneWidget);
      expect(find.text('No commits touched this file'), findsNothing);
    });
  });
}
