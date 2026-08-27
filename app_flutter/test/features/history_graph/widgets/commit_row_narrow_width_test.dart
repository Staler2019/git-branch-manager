// CommitRow rendering under a plan, i.e. that the widget honours what
// planCommitRowColumns decided. commit_row_layout_test.dart pins the
// decision itself; this tier pins the wiring, which is the half a pure-
// function test structurally cannot see.
//
// Every assertion is relational -- no exception, a rect inside its box, a
// non-zero width. Widget tests render in the Ahem test font where each glyph
// is one em wide, so any pixel constant here would encode the harness rather
// than the behaviour.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row_layout.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_ref_chips.dart';
import 'package:gbm_flutter/widgets/gbm_tag_chip.dart';

import '../../../support/pump_app.dart';

const String _subject = 'Fix the thing that was broken';
const String _oid = 'abc12345def67890abc12345def67890abc12345';

/// A snapshot whose rows sit one per lane. The fixture asserts *layout*, not
/// edge geometry, so unlike graph_edge_continuity_test.dart it deliberately
/// does not anchor its lane values to GraphBuilderTest.cpp output and carries
/// no edges at all -- there is nothing here for a bend to be wrong about.
GraphSnapshotView _graph(int laneCount) {
  return GraphSnapshotView(
    rows: <GraphRow>[
      for (int i = 0; i < laneCount; i++)
        GraphRow(
          parentOffset: 0,
          edgeOffset: 0,
          commitTime: 0,
          lane: i,
          color: i,
          flags: 0,
        ),
    ],
    oidsHex: <String>[for (int i = 0; i < laneCount; i++) _oid],
    parentPool: const <int>[],
    laneCount: laneCount,
    complete: true,
    truncated: false,
    edges: const <GraphEdge>[],
  );
}

CommitMeta _meta() => CommitMeta(
  oid: _oid,
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
  subject: _subject,
  body: '',
  signedCommit: false,
);

/// The default test surface is 800x600, so a SizedBox wider than that is
/// silently clamped -- which made an early version of the 1200px control
/// case overflow by exactly (1200 - 80) - 800 = 320px and look like a bug in
/// the plan. Size the surface to the row being asked for.
void _sizeSurface(WidgetTester tester, double width) {
  tester.view.physicalSize = ui.Size(width + 40, 200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  int laneCount = 1,
  List<RefChipData> refChips = const <RefChipData>[],
}) async {
  _sizeSurface(tester, width);
  final GraphSnapshotView graph = _graph(laneCount);
  final CommitRowColumnPlan plan = planCommitRowColumns(
    availableWidth: width,
    laneCount: laneCount,
    showGraph: true,
  );
  await pumpGbmWidget(
    tester,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: CommitRow(
          row: graph.rows.first,
          oidHex: _oid,
          graph: graph,
          rowIndex: 0,
          maxLane: laneCount,
          plan: plan,
          meta: _meta(),
          refChips: refChips,
        ),
      ),
    ),
  );
}

List<RefChipData> _manyChips() => <RefChipData>[
  for (int i = 0; i < 6; i++)
    RefChipData(
      label: 'a-long-branch-name-$i',
      kind: RefKind.localBranch,
      isCurrent: false,
      showCloudIcon: false,
      isDashed: false,
    ),
];

Rect _graphRect(WidgetTester tester) => tester.getRect(
  find
      .descendant(
        of: find.byType(CommitRow),
        matching: find.byType(CustomPaint),
      )
      .first,
);

void main() {
  group('a narrow row', () {
    for (final double width in <double>[480, 360, 240, 180]) {
      testWidgets('does not overflow at ${width.toInt()}px', (tester) async {
        await _pump(tester, width: width, laneCount: 8);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('does not overflow with six ref chips at 360px', (
      tester,
    ) async {
      // The chip strip used to be a Wrap, which in a Row gets an unbounded
      // width constraint and so pushed the whole row rather than wrapping.
      await _pump(tester, width: 360, laneCount: 4, refChips: _manyChips());
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps the subject visible, not collapsed to zero', (
      tester,
    ) async {
      await _pump(tester, width: 240, laneCount: 8);

      // Spec P02-16 locks Message. An Expanded at zero width overflows
      // nothing and shows nothing, so "no exception" alone does not cover it.
      expect(tester.getSize(find.text(_subject)).width, greaterThan(0));
    });

    testWidgets('keeps the graph column inside the row', (tester) async {
      await _pump(tester, width: 240, laneCount: 12);

      final Rect graph = _graphRect(tester);
      expect(graph.left, greaterThanOrEqualTo(0));
      expect(graph.right, lessThanOrEqualTo(240));
    });

    testWidgets('draws the graph at the width the plan allotted', (
      tester,
    ) async {
      const double width = 240;
      const int laneCount = 12;
      final CommitRowColumnPlan plan = planCommitRowColumns(
        availableWidth: width,
        laneCount: laneCount,
        showGraph: true,
      );
      await _pump(tester, width: width, laneCount: laneCount);

      expect(
        plan.graphClipped,
        isTrue,
        reason: 'fixture must exercise clipping',
      );
      expect(_graphRect(tester).width, plan.graphWidth);
    });
  });

  group('degradation reaches the rendered row', () {
    testWidgets('keeps the author column at a width that only costs date', (
      tester,
    ) async {
      // 610/8 lanes is one rung down: the plan drops date and nothing else.
      // The plan is asserted alongside the render so the case says which
      // rung it is standing on -- the width alone does not.
      //
      // **This number has moved twice, both times because a fixed cost in
      // the row moved under it, and the second time proves the first one's
      // own lesson.** It was 560 until the refs column widened from 92 to
      // 104 and the lane pitch narrowed from 18 to 17 (net +3px at eight
      // lanes), which pushed 560 onto the next rung down; the rung was then
      // measured at 563..670 and 610 taken from the middle of it. The lane
      // pitch then went 17 -> 11 on the user's ruling, which takes eight
      // lanes from 153px to 99 -- 54px of fixed cost gone -- and the rung
      // slid down with it to **509..596**, leaving 610 outside it entirely.
      // 552 is the middle of the measured span, not an edge of it.
      const double width = 552;
      final CommitRowColumnPlan plan = planCommitRowColumns(
        availableWidth: width,
        laneCount: 8,
        showGraph: true,
      );
      expect(plan.showDate, isFalse);
      expect(plan.showAuthor, isTrue);

      await _pump(tester, width: width, laneCount: 8);
      expect(find.text('Ada Lovelace'), findsOneWidget);
    });

    testWidgets('drops the author column one rung further down', (
      tester,
    ) async {
      await _pump(tester, width: 420, laneCount: 8);
      expect(find.text('Ada Lovelace'), findsNothing);
    });

    testWidgets('drops the hash column at a narrow width', (tester) async {
      await _pump(tester, width: 200, laneCount: 8);
      expect(find.text(_oid.substring(0, 8)), findsNothing);
    });

    testWidgets('drops the ref chips at a narrow width', (tester) async {
      await _pump(tester, width: 200, laneCount: 8, refChips: _manyChips());
      expect(find.byType(GbmTagChip), findsNothing);
    });
  });

  group('control: a wide row degrades nothing', () {
    testWidgets('renders every column at 1200px', (tester) async {
      await _pump(tester, width: 1200, laneCount: 4, refChips: _manyChips());

      expect(tester.takeException(), isNull);
      expect(find.text(_subject), findsOneWidget);
      expect(find.text('Ada Lovelace'), findsOneWidget);
      expect(find.text(_oid.substring(0, 8)), findsOneWidget);
      expect(find.byType(GbmTagChip), findsNWidgets(6));
    });

    testWidgets('the default plan leaves the graph at its natural width', (
      tester,
    ) async {
      // CommitRowColumnPlan.full is what every unmeasured caller gets.
      _sizeSurface(tester, 1200);
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 1200,
          child: CommitRow(
            row: _graph(4).rows.first,
            oidHex: _oid,
            graph: _graph(4),
            rowIndex: 0,
            maxLane: 4,
            meta: _meta(),
          ),
        ),
      );

      expect(_graphRect(tester).width, kGraphLaneWidth * 5);
    });
  });

  group('resizing in place', () {
    testWidgets('the graph column follows a width change without a rebuild '
        'of the row itself', (tester) async {
      // GraphRowPainter.shouldRepaint compares only row/rowIndex/graph, none
      // of which change when the window is resized -- so on paper a narrower
      // box could keep the old painting. Measured rather than reasoned about,
      // per this round's plan: RenderCustomPaint marks itself needing paint
      // when its size changes regardless of shouldRepaint, and this is the
      // case that says so out loud.
      _sizeSurface(tester, 1200);
      final GraphSnapshotView graph = _graph(12);

      late StateSetter setWidth;
      double width = 1000;

      await pumpGbmWidget(
        tester,
        child: StatefulBuilder(
          builder: (context, setState) {
            setWidth = setState;
            return Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: CommitRow(
                  row: graph.rows.first,
                  oidHex: _oid,
                  graph: graph,
                  rowIndex: 0,
                  maxLane: 12,
                  plan: planCommitRowColumns(
                    availableWidth: width,
                    laneCount: 12,
                    showGraph: true,
                  ),
                  meta: _meta(),
                ),
              ),
            );
          },
        ),
      );

      final double wide = _graphRect(tester).width;

      // 160, not 240: at twelve lanes the plan's graph is capped at
      // `GbmGraphColumnId.graph.defaultWidth` (99 since the pitch became
      // 11), and 240 is wide enough to afford that cap in full -- so both
      // measurements came back 99 and «narrower box» stopped being what the
      // fixture exercised. Measured: the graph is 60px at 160 and 99 from
      // 200 up.
      setWidth(() => width = 160);
      await tester.pump();

      final double narrow = _graphRect(tester).width;
      expect(narrow, lessThan(wide));
      expect(tester.takeException(), isNull);
    });
  });
}
