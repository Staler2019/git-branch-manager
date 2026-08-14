// GraphRowPainter is a CustomPainter drawing raw Canvas calls -- a golden
// test would cost more to maintain than the value it buys. This locks the
// `shouldRepaint` contract so a future edit to the fields it compares
// doesn't silently stop repainting on a row/graph change.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_column_painter.dart';
import 'package:gbm_flutter/theme/tokens.dart';

GraphRow _row({int lane = 0, int color = 0, int flags = 0}) {
  return GraphRow(
    parentOffset: 0,
    edgeOffset: 0,
    commitTime: 0,
    lane: lane,
    color: color,
    flags: flags,
  );
}

GraphSnapshotView _graph(
  List<GraphRow> rows, {
  List<GraphEdge> edges = const [],
}) {
  return GraphSnapshotView(
    rows: rows,
    oidsHex: List<String>.generate(rows.length, (i) => 'oid$i'),
    parentPool: const <int>[],
    laneCount: 2,
    complete: false,
    truncated: false,
    edges: edges,
  );
}

void main() {
  final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

  test('shouldRepaint is false when nothing relevant changed', () {
    // GraphRow/GraphSnapshotView have no value equality, so shouldRepaint's
    // `!=` checks only read false for the *same* instance -- share one
    // here rather than constructing field-identical duplicates.
    final GraphRow row = _row();
    final GraphSnapshotView graph = _graph(<GraphRow>[row]);
    final GraphRowPainter a = GraphRowPainter(
      row: row,
      rowIndex: 0,
      graph: graph,
      laneWidth: 18,
      colors: colors,
    );
    final GraphRowPainter b = GraphRowPainter(
      row: row,
      rowIndex: 0,
      graph: graph,
      laneWidth: 18,
      colors: colors,
    );
    expect(a.shouldRepaint(b), isFalse);
  });

  test('shouldRepaint is true when the row instance changes', () {
    final GraphSnapshotView graph = _graph(<GraphRow>[_row()]);
    final GraphRowPainter a = GraphRowPainter(
      row: _row(),
      rowIndex: 0,
      graph: graph,
      laneWidth: 18,
      colors: colors,
    );
    final GraphRowPainter b = GraphRowPainter(
      row: _row(color: 2),
      rowIndex: 0,
      graph: graph,
      laneWidth: 18,
      colors: colors,
    );
    expect(a.shouldRepaint(b), isTrue);
  });

  test('shouldRepaint is true when the graph instance changes', () {
    final GraphRow row = _row();
    final GraphRowPainter a = GraphRowPainter(
      row: row,
      rowIndex: 0,
      graph: _graph(<GraphRow>[row]),
      laneWidth: 18,
      colors: colors,
    );
    final GraphRowPainter b = GraphRowPainter(
      row: row,
      rowIndex: 0,
      graph: _graph(<GraphRow>[row]),
      laneWidth: 18,
      colors: colors,
    );
    expect(a.shouldRepaint(b), isTrue);
  });

  test('shouldRepaint is true when rowIndex changes', () {
    final GraphRow row = _row();
    final GraphSnapshotView graph = _graph(<GraphRow>[row, row]);
    final GraphRowPainter a = GraphRowPainter(
      row: row,
      rowIndex: 0,
      graph: graph,
      laneWidth: 18,
      colors: colors,
    );
    final GraphRowPainter b = GraphRowPainter(
      row: row,
      rowIndex: 1,
      graph: graph,
      laneWidth: 18,
      colors: colors,
    );
    expect(a.shouldRepaint(b), isTrue);
  });

  test('paint() runs without throwing for a row with no spanning edges', () {
    final GraphRowPainter painter = GraphRowPainter(
      row: _row(),
      rowIndex: 0,
      graph: _graph(<GraphRow>[_row()]),
      laneWidth: 18,
      colors: colors,
    );
    final PictureRecorder recorder = PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    painter.paint(canvas, const Size(18, 34));
    recorder.endRecording().dispose();
  });

  test('paint() runs without throwing for a row with a bending edge', () {
    final GraphRow row = _row(lane: 1);
    final GraphEdge edge = GraphEdge(
      childRow: 0,
      parentRow: 2,
      lane: 2,
      childLane: 1,
      color: 0,
      kind: EdgeKind.mergeParent,
    );
    final GraphRowPainter painter = GraphRowPainter(
      row: row,
      rowIndex: 0,
      graph: _graph(<GraphRow>[row], edges: <GraphEdge>[edge]),
      laneWidth: 18,
      colors: colors,
    );
    final PictureRecorder recorder = PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    painter.paint(canvas, const Size(54, 34));
    recorder.endRecording().dispose();
  });
}
