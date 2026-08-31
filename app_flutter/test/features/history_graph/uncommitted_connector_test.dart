// The segment that joins History's uncommitted-changes row to HEAD's dot.
//
// The row draws the *upper* half of that join inside its own box (dot centre
// down to its bottom edge). The lower half belongs to the first commit row,
// and nothing was drawing it: a row's segments come from `graph.edges`, and
// the topmost row has no incoming edge by construction -- nothing in the view
// is its child. So the line stopped dead on the row boundary, half a row
// short of the dot it was pointing at.
//
// Fixing it in the *painter* rather than by synthesising an edge is
// deliberate. A fake `GraphEdge` would have to be given a childRow that does
// not exist, and it would then flow into `edgesSpanning`, the span index and
// the ASCII reference renderer -- none of which have any business knowing
// about an uncommitted working copy.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_column_painter.dart';
import 'package:gbm_flutter/theme/tokens.dart';

class _Line {
  const _Line(this.from, this.to);
  final Offset from;
  final Offset to;
}

/// Keeps the offsets, unlike `graph_dot_geometry_test.dart`'s canvas, which
/// only keeps the `Paint` because widths were all it asserted.
class _RecordingCanvas implements Canvas {
  final List<_Line> lines = <_Line>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => lines.add(_Line(p1, p2));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const Size _kRowSize = Size(34, 26);

GraphRow _row({int lane = 0}) => GraphRow(
  parentOffset: 0,
  edgeOffset: 0,
  commitTime: 0,
  lane: lane,
  color: 0,
  flags: 0,
);

_RecordingCanvas _paint({
  required bool connectsUpToUncommitted,
  int lane = 0,
}) {
  final GraphSnapshotView graph = GraphSnapshotView(
    rows: <GraphRow>[_row(lane: lane), _row(lane: lane)],
    oidsHex: const <String>['a', 'b'],
    parentPool: const <int>[],
    laneCount: lane + 1,
    complete: true,
    truncated: false,
  );
  final _RecordingCanvas canvas = _RecordingCanvas();
  GraphRowPainter(
    row: graph.rows.first,
    rowIndex: 0,
    graph: graph,
    laneWidth: GbmLayout.graphLaneWidth,
    colors: tokensFor(GbmThemeVariant.darkTechnical),
    connectsUpToUncommitted: connectsUpToUncommitted,
  ).paint(canvas, _kRowSize);
  return canvas;
}

void main() {
  test('the first row draws the stub from its top edge to its dot centre', () {
    final List<_Line> lines = _paint(connectsUpToUncommitted: true).lines;

    final Iterable<_Line> stubs = lines.where(
      (_Line l) => l.from.dy == 0.0 && l.to.dy == _kRowSize.height / 2,
    );
    expect(
      stubs.length,
      1,
      reason:
          'exactly one, and it must reach the dot centre -- stopping at the '
          'top edge is the very gap this exists to close',
    );
    final _Line stub = stubs.single;
    expect(
      stub.from.dx,
      kGraphLaneInset,
      reason: 'lane 0, the same x the uncommitted row puts its diamond at',
    );
    expect(
      stub.to.dx,
      kGraphLaneInset,
      reason: 'vertical: a bend here would claim a lane change that is not one',
    );
  });

  test('and draws nothing extra when there is no row above it', () {
    expect(
      _paint(connectsUpToUncommitted: false).lines,
      isEmpty,
      reason:
          'with no edges in the snapshot the topmost row paints no connector '
          'at all -- so the stub above is the only thing this flag adds',
    );
  });
}
