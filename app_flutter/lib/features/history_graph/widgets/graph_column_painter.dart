import 'package:flutter/material.dart';

import '../../../data/models/graph_snapshot.dart';
import '../../../theme/tokens.dart';
import 'graph_edge_geometry.dart';

/// Paints one row's lane dot and its connectors (edges), consuming the real
/// edge list from [GraphSnapshotView] and drawing curved bends where needed.
/// Mirrors the behavior of `GraphColumnDelegate`/`GraphAsciiRenderer`
/// (src/app/models/GraphColumnDelegate.cpp, src/core/graph/GraphAsciiRenderer.cpp).
class GraphRowPainter extends CustomPainter {
  const GraphRowPainter({
    required this.row,
    required this.rowIndex,
    required this.graph,
    required this.laneWidth,
    required this.colors,
  });

  final GraphRow row;
  final int rowIndex;
  final GraphSnapshotView graph;
  final double laneWidth;
  final GbmColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height / 2;
    final double dotX = laneWidth * (row.lane + 0.5);

    // Compute which edges span this row and draw each
    final List<EdgeSegment> segments = computeEdgeSegments(
      graph,
      rowIndex,
      graph.rows,
    );

    for (final EdgeSegment segment in segments) {
      _paintEdgeSegment(canvas, size, segment);
    }

    // Paint the commit dot
    _paintDot(canvas, dotX, centerY);
  }

  void _paintEdgeSegment(Canvas canvas, Size size, EdgeSegment segment) {
    final double startX = laneWidth * (segment.startLane + 0.5);
    final double endX = laneWidth * (segment.endLane + 0.5);
    final double startY = size.height * segment.startYFraction;
    final double endY = size.height * segment.endYFraction;
    final int colorIndex = segment.edgeColor % colors.graphLanes.length;
    final Color segmentColor = colors.graphLanes[colorIndex];

    final Paint linePaint = Paint()
      ..color = segmentColor
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    if (!segment.hasBend) {
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), linePaint);
      return;
    }

    final double midY = (startY + endY) / 2;
    final Path path = Path()
      ..moveTo(startX, startY)
      ..cubicTo(startX, midY, endX, midY, endX, endY);
    canvas.drawPath(path, linePaint);
  }

  void _paintDot(Canvas canvas, double x, double centerY) {
    final double radius = row.isHead ? 4.5 : 3.5;
    final int colorIndex = row.color % colors.graphLanes.length;
    final Color dotColor = colors.graphLanes[colorIndex];

    final Paint dotPaint = Paint()..color = dotColor;
    canvas.drawCircle(Offset(x, centerY), radius, dotPaint);

    if (row.isHead) {
      canvas.drawCircle(
        Offset(x, centerY),
        radius + 2,
        Paint()
          ..color = dotColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(GraphRowPainter oldDelegate) {
    return oldDelegate.row != row ||
        oldDelegate.rowIndex != rowIndex ||
        oldDelegate.graph != graph;
  }
}
