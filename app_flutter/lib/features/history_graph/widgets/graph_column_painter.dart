import 'package:flutter/material.dart';

import '../../../data/models/graph_snapshot.dart';

/// Paints one row's lane dot and its connectors to the row above/below, in
/// the row's own lane column. A simplified sibling of
/// `GraphColumnDelegate`/`GraphAsciiRenderer` (src/app/models/
/// GraphColumnDelegate.cpp, src/core/graph/GraphAsciiRenderer.cpp): draws
/// per-row from [GraphRow.lane] alone rather than routing the real edge list
/// ([GraphSnapshotView] exposes `edges` via `gbm_graph_snapshot_edges`, not
/// yet consumed here), so a merge/branch bend renders as a straight jog
/// between two lane columns instead of a curved edge. Good enough to make
/// the graph recognizably a graph for M1; real edge routing is graph-view
/// polish for a later milestone.
class GraphRowPainter extends CustomPainter {
  const GraphRowPainter({
    required this.row,
    required this.previousLane,
    required this.nextLane,
    required this.color,
    required this.laneWidth,
  });

  final GraphRow row;
  final int? previousLane;
  final int? nextLane;
  final Color color;
  final double laneWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height / 2;
    final double x = laneWidth * (row.lane + 0.5);

    final Paint linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (previousLane != null) {
      canvas.drawLine(
        Offset(laneWidth * (previousLane! + 0.5), 0),
        Offset(x, centerY),
        linePaint,
      );
    }
    if (nextLane != null) {
      canvas.drawLine(
        Offset(x, centerY),
        Offset(laneWidth * (nextLane! + 0.5), size.height),
        linePaint,
      );
    }

    final double radius = row.isHead ? 4.5 : 3.5;
    final Paint dotPaint = Paint()..color = color;
    canvas.drawCircle(Offset(x, centerY), radius, dotPaint);
    if (row.isHead) {
      canvas.drawCircle(
        Offset(x, centerY),
        radius + 2,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(GraphRowPainter oldDelegate) {
    return oldDelegate.row != row ||
        oldDelegate.previousLane != previousLane ||
        oldDelegate.nextLane != nextLane ||
        oldDelegate.color != color;
  }
}
