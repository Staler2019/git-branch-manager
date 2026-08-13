// GraphRowPainter is a CustomPainter drawing raw Canvas calls -- a golden
// test would cost more to maintain than the value it buys for a single
// stroke-width tweak (see the plan's note; the actual thinner-line look is
// confirmed on a real device). This just locks the `shouldRepaint` contract
// so a future edit to the fields it compares doesn't silently stop
// repainting on a lane/color change.
import 'dart:ui';

import 'package:flutter/material.dart' show Colors;
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_column_painter.dart';

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

void main() {
  test('shouldRepaint is false when nothing relevant changed', () {
    // GraphRow has no value equality, so shouldRepaint's `oldDelegate.row
    // != row` check only reads false for the *same* instance -- share one
    // here rather than constructing two field-identical rows.
    final GraphRow row = _row();
    final GraphRowPainter a = GraphRowPainter(
      row: row,
      previousLane: 0,
      nextLane: 1,
      color: Colors.blue,
      laneWidth: 18,
    );
    final GraphRowPainter b = GraphRowPainter(
      row: row,
      previousLane: 0,
      nextLane: 1,
      color: Colors.blue,
      laneWidth: 18,
    );
    expect(a.shouldRepaint(b), isFalse);
  });

  test('shouldRepaint is true when the lane color changes', () {
    final GraphRow row = _row();
    final GraphRowPainter a = GraphRowPainter(
      row: row,
      previousLane: 0,
      nextLane: 1,
      color: Colors.blue,
      laneWidth: 18,
    );
    final GraphRowPainter b = GraphRowPainter(
      row: row,
      previousLane: 0,
      nextLane: 1,
      color: Colors.red,
      laneWidth: 18,
    );
    expect(a.shouldRepaint(b), isTrue);
  });

  test(
    'paint() runs without throwing for a boundary row (no prev/next lane)',
    () {
      final GraphRowPainter painter = GraphRowPainter(
        row: _row(),
        previousLane: null,
        nextLane: null,
        color: Colors.blue,
        laneWidth: 18,
      );
      final PictureRecorder recorder = PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      painter.paint(canvas, const Size(18, 34));
      recorder.endRecording().dispose();
    },
  );
}
