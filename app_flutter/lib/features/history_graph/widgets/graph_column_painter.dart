import 'package:flutter/material.dart';

import '../../../data/models/graph_snapshot.dart';
import '../../../theme/tokens.dart';
import 'graph_edge_geometry.dart';

/// Spec's graph geometry, from the mockup that draws it: the dot circles are
/// `r: 4.2` with a 2px stroke in the panel colour and HEAD gets an extra
/// `r: 7` ring stroked at 1.5 in the accent colour (`spec_logic.js:466-467`),
/// while the connectors are `stroke-width="1.75"` with a round linecap
/// (`spec_raw.html:1302`).
///
/// All four were off before this was checked against the source -- the dots
/// were 3.5 with no halo, HEAD was drawn as a *bigger* 4.5 dot with a
/// lane-coloured 6.5 ring at 1.0, and the connectors were 1.0. Same class of
/// pre-existing drift as the 34px row height and the 18px lane pitch, and
/// found the same way: by reading the mockup's own numbers rather than the
/// picture.
///
/// Note what `r: 4.2` does *not* mean: SVG centres a stroke on its path and
/// paints it over the fill, so a 2px stroke eats 1px of the disc and the
/// visible core is 3.2, not 4.2. The dot barely changed size; what it gained
/// is the halo, which is what stops a lane line drawn underneath from
/// touching the dot's edge.
const double kGraphDotRadius = 4.2;
const double kGraphDotHaloWidth = 2.0;
const double kGraphHeadRingRadius = 7.0;
const double kGraphHeadRingStrokeWidth = 1.5;
const double kGraphEdgeStrokeWidth = 1.75;

/// Paints one row's lane dot and its connectors (edges), consuming the real
/// edge list from [GraphSnapshotView] and drawing curved bends where needed.
/// Mirrors the behavior of the reference renderer,
/// src/core/graph/GraphAsciiRenderer.cpp. (This comment used to also name a
/// `GraphColumnDelegate` at src/app/models/GraphColumnDelegate.cpp; no such
/// file exists in this repository -- the ASCII renderer is the only
/// reference.)
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
      ..strokeWidth = kGraphEdgeStrokeWidth
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
    final int colorIndex = row.color % colors.graphLanes.length;
    final Color dotColor = colors.graphLanes[colorIndex];
    final Offset centre = Offset(x, centerY);

    // Fill first, then the halo *over* it -- SVG paints stroke on top of
    // fill, and the stroke is centred on the path, so spec's `r: 4.2` with a
    // 2px panel-coloured stroke leaves a 3.2px coloured core inside a halo
    // reaching 5.2. Painting the halo first instead would show a 4.2 core:
    // visibly different, and the reason this is worth a comment rather than
    // two drawCircle calls in whatever order.
    canvas.drawCircle(centre, kGraphDotRadius, Paint()..color = dotColor);
    canvas.drawCircle(
      centre,
      kGraphDotRadius,
      Paint()
        ..color = colors.surfacePanel
        ..style = PaintingStyle.stroke
        ..strokeWidth = kGraphDotHaloWidth,
    );

    if (row.isHead) {
      // Spec gives HEAD a separate ring at a fixed radius rather than a
      // bigger dot -- every dot is 4.2 -- and strokes it in the accent
      // colour, not the lane's, so "you are here" reads the same whichever
      // lane HEAD happens to sit in.
      canvas.drawCircle(
        centre,
        kGraphHeadRingRadius,
        Paint()
          ..color = colors.accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = kGraphHeadRingStrokeWidth,
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
