// The Committer column (spec's GRAPH_COLS lists it, switched off by default).
//
// The author and committer differ in this file's fixture on purpose. Every
// other CommitMeta fixture in the suite reuses one Signature for both, which
// means an arm that rendered `meta.author.name` under the committer id would
// pass against them -- the same fixture-falsifiability trap CLAUDE.md records
// for `hasTrackingInfo` and for the graph-edge conjunction case. A rebase or
// a cherry-pick produces exactly this shape in a real repository, so it is
// not a contrived fixture either.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row_layout.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_ref_chips.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../../../support/pump_app.dart';

const String _subject = 'Fix the thing that was broken';
const String _author = 'Ada Lovelace';
const String _committer = 'Grace Hopper';
const String _oid = 'abc12345def67890abc12345def67890abc12345';

/// Wide enough that the degradation ladder gives nothing up -- a Committer
/// column dropped for width would look exactly like one that never rendered.
const double _kWide = 1400;

GraphSnapshotView _graph() => const GraphSnapshotView(
  rows: <GraphRow>[
    GraphRow(
      parentOffset: 0,
      edgeOffset: 0,
      commitTime: 0,
      lane: 0,
      color: 0,
      flags: 0,
    ),
  ],
  oidsHex: <String>[_oid],
  parentPool: <int>[],
  laneCount: 1,
  complete: true,
  truncated: false,
  edges: <GraphEdge>[],
);

CommitMeta _meta() => CommitMeta(
  oid: _oid,
  tree: 'b' * 40,
  parents: const <String>[],
  author: const Signature(
    name: _author,
    email: 'ada@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  committer: const Signature(
    name: _committer,
    email: 'grace@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  subject: _subject,
  body: '',
  signedCommit: false,
);

Future<void> _pump(
  WidgetTester tester, {
  bool showCommitter = false,
  bool isOwnCommit = false,
}) async {
  tester.view.physicalSize = const ui.Size(_kWide + 40, 200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final GraphSnapshotView graph = _graph();
  await pumpGbmWidget(
    tester,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: _kWide,
        child: CommitRow(
          row: graph.rows.first,
          oidHex: _oid,
          graph: graph,
          rowIndex: 0,
          maxLane: 1,
          plan: planCommitRowColumns(
            availableWidth: _kWide,
            laneCount: 1,
            showGraph: true,
            // The hidden set, not the order, is what a picker tick changes --
            // so switching the column on here goes through the same input
            // the real toggle writes.
            hiddenByUser: showCommitter ? const <String>{'changedFiles'} : null,
          ),
          meta: _meta(),
          isOwnCommit: isOwnCommit,
          refChips: const <RefChipData>[],
        ),
      ),
    ),
  );
}

TextStyle _styleOf(WidgetTester tester, String text) =>
    tester.widget<Text>(find.text(text)).style!;

void main() {
  testWidgets('the column is off by default and draws nothing', (tester) async {
    await _pump(tester);

    expect(find.text(_author), findsOneWidget);
    expect(find.text(_committer), findsNothing);
  });

  testWidgets('switched on, it renders the committer, not the author again', (
    tester,
  ) async {
    await _pump(tester, showCommitter: true);

    expect(find.text(_committer), findsOneWidget);
    // And it sits after the hash, which is where GRAPH_COLS puts it.
    expect(
      tester.getTopLeft(find.text(_oid.substring(0, 8))).dx,
      lessThan(tester.getTopLeft(find.text(_committer)).dx),
    );
  });

  testWidgets('an own commit accents the author column only', (tester) async {
    // Spec singles out the Author column for the accent ("Author 欄以 accent
    // 色加粗顯示"). Carrying it into Committer as well would make a commit
    // you merely rebased claim, in the committer column, to be authored by
    // you -- which is the one thing the two columns exist to tell apart.
    await _pump(tester, showCommitter: true, isOwnCommit: true);

    final GbmColors colors = tester.element(find.byType(CommitRow)).gbmColors;

    expect(_styleOf(tester, _author).color, colors.accent);
    expect(_styleOf(tester, _author).fontWeight, GbmTypography.weightSemibold);

    expect(_styleOf(tester, _committer).color, colors.textSecondary);
    expect(_styleOf(tester, _committer).fontWeight, isNull);
  });
}
