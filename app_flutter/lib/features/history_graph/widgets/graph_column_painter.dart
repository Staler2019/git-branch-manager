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
/// Note what a dot radius does *not* mean: SVG centres a stroke on its path
/// and paints it over the fill, so the 2px halo eats 1px of the disc and the
/// visible core is `radius - 1`. What the halo buys is that a lane line drawn
/// underneath never touches the dot's edge.
///
/// **The radius is 5.0, a user-ratified deviation from spec's `r: 4.2`.**
/// Asked for after the lane pitch went 17 -> 11, and 5.0 rather than more
/// because the ring below keeps spec's numbers: at a 1.5 stroke its *inner*
/// edge is 6.25, and a halo reaching past that would leave no background
/// between dot and ring, so HEAD's ring would read as a thick edge on the dot
/// instead of a ring. 5.0 + 1 = 6.0 leaves 0.25px of gap, and
/// `graph_dot_geometry_test.dart` is what holds the two apart. Growing the
/// dot further means growing the ring, which means moving
/// [kGraphLaneInset] -- see its own note.
const double kGraphDotRadius = 5.0;
const double kGraphDotHaloWidth = 2.0;
const double kGraphHeadRingRadius = 7.0;
const double kGraphHeadRingStrokeWidth = 1.5;
const double kGraphEdgeStrokeWidth = 1.75;

/// Where lane 0's centre sits, measured from the graph column's left edge.
///
/// **8, which is `ceil(7.75)` -- the HEAD ring's outer edge**
/// ([kGraphHeadRingRadius] plus half of [kGraphHeadRingStrokeWidth]).
/// `commit_row.dart` wraps this painter in a `ClipRect`, so a centre closer
/// to the edge than that loses the ring's left side on the one lane HEAD
/// sits in most often: the trunk.
///
/// This replaces `laneWidth * (lane + 0.5)`, which put lane 0 half a pitch
/// in and so made the ring's room a function of the pitch -- 0.75px of
/// clearance at a 17px pitch, none at all below 16, which
/// `graph_dot_geometry_test.dart` used to say out loud. Spec's own geometry
/// is the same shape as the inset, not as the half-pitch:
/// `spec_logic.js:428` is `const L0 = 15, L1 = 32`, two centres one pitch
/// apart with lane 0 nowhere near half a pitch.
///
/// The column's natural width is unaffected and stays
/// `laneWidth * (laneCount + 1)`: the trailing slack that formula leaves is
/// wider than the leading inset at every lane count, so the *last* lane's
/// ring was never the one at risk.
const double kGraphLaneInset = 8.0;

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
    final double dotX = kGraphLaneInset + laneWidth * row.lane;

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
    final double startX = kGraphLaneInset + laneWidth * segment.startLane;
    final double endX = kGraphLaneInset + laneWidth * segment.endLane;
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
    // fill, and the stroke is centred on the path, so `r: 5.0` with a 2px
    // panel-coloured stroke leaves a 4.0px coloured core inside a halo
    // reaching 6.0. Painting the halo first instead would show a 5.0 core:
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
      // bigger dot -- every dot is [kGraphDotRadius] -- and strokes it in the
      // accent colour, not the lane's, so "you are here" reads the same
      // whichever lane HEAD happens to sit in.
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
