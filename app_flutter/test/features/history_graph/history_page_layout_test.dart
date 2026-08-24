// Where History's three panes actually sit, in one assertion each.
//
// Nothing at any tier covered this before, which is how the page could
// disagree with spec's own prose in three ways at once and stay green:
// P02's HISTORY entry is「History 分頁：右側 Changed files（02-10）+ 下方
// Commit detail（02-08）」, and its SPLITTERS table spells the two dividers
// out — `main.detail` is「Commit list ↔ Commit detail」水平 62/38, and
// `main.files` is「中央 ↔ Changed files」垂直 186px.
//
// Positions are read off the rendered rects rather than off the widget tree:
// which GbmSplitPane nests inside which is an implementation detail, "the
// files panel is to the right of the graph" is the requirement.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/chrome_visibility_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/features/history_graph/history_page.dart';
import 'package:gbm_flutter/features/history_graph/widgets/changed_files_panel.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_detail_panel.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

String _oidAt(int i) => '${i.toRadixString(16).padLeft(4, '0')}${'a' * 36}';

const int _kRowCount = 4;

GraphSnapshotView _graph() => GraphSnapshotView(
  rows: <GraphRow>[
    for (int i = 0; i < _kRowCount; i++)
      const GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 0,
        color: 0,
        flags: 0,
      ),
  ],
  oidsHex: <String>[for (int i = 0; i < _kRowCount; i++) _oidAt(i)],
  parentPool: const <int>[],
  laneCount: 1,
  complete: true,
  truncated: false,
  edges: const <GraphEdge>[],
);

ChangedFile _file(String path) => ChangedFile(
  path: path,
  oldPath: path,
  kind: FileChangeKind.modified,
  oldMode: '100644',
  newMode: '100644',
  oldBlob: 'aaa',
  newBlob: 'bbb',
  similarity: 0,
  // 0/0 draws no badge, so these rows render exactly as they did before
  // spec P02-10's line counts existed -- this file is about something
  // else and should not start depending on them.
  addedLines: 0,
  removedLines: 0,
);

CommitMeta _meta(String oid) => CommitMeta(
  oid: oid,
  tree: 'b' * 40,
  parents: const <String>[],
  author: const Signature(
    name: 'Ada Lovelace',
    email: 'a@b.c',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  committer: const Signature(
    name: 'Ada Lovelace',
    email: 'a@b.c',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  subject: 'Commit $oid',
  body: '',
  signedCommit: false,
);

Future<void> _pump(WidgetTester tester, {ui.Size? size}) async {
  await pumpWorkspace(
    tester,
    identity: _identity,
    initialState: RepoSessionState(
      isOpen: true,
      graph: _graph(),
      commitMetaCache: <String, CommitMeta>{
        for (int i = 0; i < _kRowCount; i++) _oidAt(i): _meta(_oidAt(i)),
      },
      // Without a selection ChangedFilesPanel renders a centred 'No files
      // changed' and builds no header, so every assertion about the column
      // would be measuring a placeholder.
      commitFiles: <ChangedFile>[
        _file('lib/features/history_graph/history_page.dart'),
        _file('lib/widgets/split_pane.dart'),
      ],
    ),
    surfaceSize: size ?? const ui.Size(1600, 900),
    overrides: <Override>[
      commitSelectionProvider(_identity).overrideWith(
        (Ref ref) => ListSelection<String>(
          items: <String>[_oidAt(0)],
          anchor: _oidAt(0),
        ),
      ),
    ],
    historyBuilder: (context, state) => HistoryPage(identity: _identity),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('History page composition (spec P02 HISTORY + SPLITTERS)', () {
    testWidgets('Changed files is a fixed column on the right', (tester) async {
      await _pump(tester);

      final Rect graph = tester.getRect(find.byType(CommitGraphView));
      final Rect detail = tester.getRect(find.byType(CommitDetailPanel));
      final Rect files = tester.getRect(find.byType(ChangedFilesPanel));

      expect(files.left, greaterThan(graph.right));
      expect(files.left, greaterThan(detail.right));
      // 186px from the SPLITTERS table, read through the token rather than
      // written out, so a spec revision moves one number.
      expect(files.width, GbmLayout.splitterMainFiles.defaultExtent);
      // It spans both, rather than sitting beside only one of them.
      expect(files.top, lessThanOrEqualTo(graph.top));
      expect(files.bottom, greaterThanOrEqualTo(detail.bottom));
    });

    testWidgets('Commit detail is below the graph, in the same column', (
      tester,
    ) async {
      await _pump(tester);

      final Rect graph = tester.getRect(find.byType(CommitGraphView));
      final Rect detail = tester.getRect(find.byType(CommitDetailPanel));

      expect(detail.top, greaterThan(graph.bottom));
      expect(detail.left, graph.left);
      expect(detail.right, graph.right);
    });

    testWidgets('the graph gets the 62 of the 62/38 split', (tester) async {
      await _pump(tester);

      final Rect graph = tester.getRect(find.byType(CommitGraphView));
      final Rect detail = tester.getRect(find.byType(CommitDetailPanel));

      final List<double> ratio = GbmLayout.splitterMainDetail.flexRatio!;
      final double share = graph.height / (graph.height + detail.height);
      expect(share, closeTo(ratio[0] / (ratio[0] + ratio[1]), 0.02));
      // Stated separately: a ratio alone would still hold if the two were
      // swapped and the numbers happened to be near 50/50.
      expect(graph.height, greaterThan(detail.height));
    });

    testWidgets('the files column survives being 186px wide', (tester) async {
      // It used to be a full-width band 186px *tall*; as a column it is 186px
      // *wide*, which is the shape its header (title + the List/Tree switcher)
      // had never been laid out at. Checked at the app's own default window
      // and one step below it, since the column keeps its width as the window
      // shrinks -- the centre pane is what yields.
      for (final ui.Size size in <ui.Size>[
        const ui.Size(1280, 720),
        const ui.Size(1024, 768),
      ]) {
        await _pump(tester, size: size);
        expect(tester.takeException(), isNull, reason: '$size');
        // The header is the part that had never been laid out this narrow;
        // assert it is really on screen, or this is a placeholder test.
        expect(find.text('CHANGED FILES'), findsOneWidget, reason: '$size');
        expect(
          tester.getRect(find.byType(ChangedFilesPanel)).width,
          GbmLayout.splitterMainFiles.defaultExtent,
          reason: '$size',
        );
      }
    });

    testWidgets('hiding Commit detail gives the graph the full height', (
      tester,
    ) async {
      await _pump(tester);
      final Rect files = tester.getRect(find.byType(ChangedFilesPanel));
      final Rect before = tester.getRect(find.byType(CommitGraphView));

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(HistoryPage)),
        listen: false,
      );
      container.read(chromeVisibilityProvider.notifier).toggleCommitDetail();
      await tester.pumpAndSettle();

      expect(find.byType(CommitDetailPanel), findsNothing);
      final Rect after = tester.getRect(find.byType(CommitGraphView));
      expect(after.height, greaterThan(before.height));
      expect(after.top, before.top);
      // The files column is unaffected -- it is the outer splitter.
      expect(tester.getRect(find.byType(ChangedFilesPanel)).width, files.width);
    });
  });
}
