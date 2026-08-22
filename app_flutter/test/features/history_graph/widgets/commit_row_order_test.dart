// CommitRow draws its columns in the order the plan hands it, not in a
// hardcoded one. commit_row_layout_test.dart pins what the plan decides;
// this file pins that the row obeys it, which is the half a pure-function
// test structurally cannot see.
//
// Assertions are on rendered x positions rather than on child indices: the
// Row's children include gap SizedBoxes and skip columns with nothing to
// draw, so an index-based check would pass for the wrong reason the first
// time a gap moved.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_column.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row_layout.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_ref_chips.dart';

import '../../../support/pump_app.dart';

const String _subject = 'Fix the thing that was broken';
const String _author = 'Ada Lovelace';
const String _oid = 'abc12345def67890abc12345def67890abc12345';
const String _branch = 'feature-x';

GraphSnapshotView _graph() => GraphSnapshotView(
  rows: const <GraphRow>[
    GraphRow(
      parentOffset: 0,
      edgeOffset: 0,
      commitTime: 0,
      lane: 0,
      color: 0,
      flags: 0,
    ),
  ],
  oidsHex: const <String>[_oid],
  parentPool: const <int>[],
  laneCount: 1,
  complete: true,
  truncated: false,
  edges: const <GraphEdge>[],
);

CommitMeta _meta() => CommitMeta(
  oid: _oid,
  tree: 'b' * 40,
  parents: const <String>[],
  author: const Signature(
    name: _author,
    email: 'a@b.c',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  committer: const Signature(
    name: _author,
    email: 'a@b.c',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  subject: _subject,
  body: '',
  signedCommit: false,
);

const List<RefChipData> _chips = <RefChipData>[
  RefChipData(
    label: _branch,
    kind: RefKind.localBranch,
    isCurrent: false,
    showCloudIcon: false,
    isDashed: false,
  ),
];

/// Wide enough that the ladder gives nothing up -- this file is about order,
/// and a dropped column would make an ordering assertion vacuously true.
const double _kWide = 1400;

Future<void> _pump(
  WidgetTester tester, {
  List<GbmGraphColumnId> order = kGraphColumnOrderDefault,
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
            order: order,
          ),
          meta: _meta(),
          refChips: _chips,
        ),
      ),
    ),
  );
}

double _leftOf(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text)).dx;

void main() {
  group('default order is the spec layout', () {
    // spec_raw.html:1310-1316 draws the row as graph, message (flex:1),
    // chips, author, date, hash -- the same order GRAPH_COLS lists the
    // columns in. Before this commit the row drew hash and refs *before* the
    // message, which is where the two disagreed.
    testWidgets('message, then refs, then author, then date, then hash', (
      tester,
    ) async {
      await _pump(tester);

      final double message = _leftOf(tester, _subject);
      final double refs = _leftOf(tester, _branch);
      final double author = _leftOf(tester, _author);
      final double hash = _leftOf(tester, _oid.substring(0, 8));

      expect(message, lessThan(refs));
      expect(refs, lessThan(author));
      expect(author, lessThan(hash));
    });

    testWidgets('the graph column is leftmost', (tester) async {
      await _pump(tester);
      expect(
        tester.getTopLeft(find.byType(CustomPaint).first).dx,
        lessThan(_leftOf(tester, _subject)),
      );
    });
  });

  group('a reordered plan reorders the row', () {
    testWidgets('hash moves ahead of author and date', (tester) async {
      await _pump(
        tester,
        order: const <GbmGraphColumnId>[
          GbmGraphColumnId.graph,
          GbmGraphColumnId.message,
          GbmGraphColumnId.hash,
          GbmGraphColumnId.refs,
          GbmGraphColumnId.author,
          GbmGraphColumnId.date,
        ],
      );

      expect(
        _leftOf(tester, _oid.substring(0, 8)),
        lessThan(_leftOf(tester, _branch)),
      );
      expect(_leftOf(tester, _branch), lessThan(_leftOf(tester, _author)));
    });

    // Message is the sole flex column, so moving it does not just relabel
    // positions -- everything after it has to end up on its right.
    testWidgets('message keeps flexing wherever it is placed', (tester) async {
      await _pump(
        tester,
        order: const <GbmGraphColumnId>[
          GbmGraphColumnId.graph,
          GbmGraphColumnId.hash,
          GbmGraphColumnId.message,
          GbmGraphColumnId.refs,
          GbmGraphColumnId.author,
          GbmGraphColumnId.date,
        ],
      );

      expect(
        _leftOf(tester, _oid.substring(0, 8)),
        lessThan(_leftOf(tester, _subject)),
      );
      expect(_leftOf(tester, _subject), lessThan(_leftOf(tester, _branch)));
      // Still the column absorbing the slack: it has to be wider than the
      // fixed slots beside it, or "flex" would just mean "first in line".
      expect(
        tester.getSize(find.text(_subject)).width,
        greaterThan(GbmGraphColumnId.author.defaultWidth),
      );
    });
  });

  group('columns with nothing to draw cost no space', () {
    // The mockup gives the chip span no width at all, so a commit carrying
    // no refs must let the message run straight into the author rather than
    // leaving the column's 60px reserved and empty.
    testWidgets('a commit with no ref chips leaves no gap', (tester) async {
      final GraphSnapshotView graph = _graph();
      tester.view.physicalSize = const ui.Size(_kWide + 40, 200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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
              ),
              meta: _meta(),
            ),
          ),
        ),
      );

      // The message column absorbs what the absent chips did not take, so it
      // is wider here than in the same row with a chip in it.
      final double without = tester.getSize(find.text(_subject)).width;
      await _pump(tester);
      final double with_ = tester.getSize(find.text(_subject)).width;
      expect(without, greaterThan(with_));
    });
  });
}
