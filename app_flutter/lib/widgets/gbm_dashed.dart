import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// How long one dash is, and how long the gap after it, in logical pixels.
///
/// **Unsourced, and deliberately recorded as such.** 變體 B writes
/// `1px dashed var(--accent)` and CSS does not name a pattern -- each engine
/// picks its own, and Flutter has no dashed border at all, so a number had to
/// be chosen rather than read. 3/3 is what a 1px CSS dash looks closest to in
/// Chrome at this scale. Every other value in these widgets comes from the
/// design; these two do not.
const double kGbmDashLength = 3;
const double kGbmDashGap = 3;

/// A dashed straight line, one logical pixel thick along its cross axis.
///
/// [Axis.horizontal] draws left-to-right and takes its parent's width;
/// [Axis.vertical] draws top-to-bottom and takes its parent's height. Both
/// size themselves to 1px on the other axis, so this drops into a `Column` or
/// a `Row` the way a `Border` side would -- which is exactly what it replaces,
/// since Flutter's `BorderSide` has no dash.
class GbmDashedLine extends StatelessWidget {
  const GbmDashedLine({
    super.key,
    required this.color,
    this.axis = Axis.horizontal,
    this.thickness = 1,
  });

  final Color color;
  final Axis axis;
  final double thickness;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: axis == Axis.vertical ? thickness : double.infinity,
      height: axis == Axis.horizontal ? thickness : double.infinity,
      child: CustomPaint(
        painter: _DashedLinePainter(color: color, axis: axis),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color, required this.axis});

  final Color color;
  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = axis == Axis.horizontal ? size.height : size.width
      ..strokeCap = StrokeCap.butt;

    final double length = axis == Axis.horizontal ? size.width : size.height;
    final double centre = axis == Axis.horizontal
        ? size.height / 2
        : size.width / 2;

    double at = 0;
    while (at < length) {
      final double end = (at + kGbmDashLength).clamp(0, length);
      canvas.drawLine(
        axis == Axis.horizontal ? Offset(at, centre) : Offset(centre, at),
        axis == Axis.horizontal ? Offset(end, centre) : Offset(centre, end),
        paint,
      );
      at = end + kGbmDashGap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) =>
      old.color != color || old.axis != axis;
}

/// A dashed rounded-rectangle outline around [child].
///
/// The one thing this is *not* is a `Border` with a dash property -- Flutter
/// has none, which is why it exists at all. It paints the outline as a
/// foreground so the child keeps its own background and clipping; the outline
/// sits on the box's edge, half a stroke in, the way a CSS border does.
class GbmDashedBorder extends StatelessWidget {
  const GbmDashedBorder({
    super.key,
    required this.color,
    required this.child,
    this.radius = 0,
    this.strokeWidth = 1,
  });

  final Color color;
  final double radius;
  final double strokeWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      foregroundPainter: _DashedBoxPainter(
        color: color,
        radius: radius,
        strokeWidth: strokeWidth,
      ),
      child: child,
    );
  }
}

class _DashedBoxPainter extends CustomPainter {
  const _DashedBoxPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
  });

  final Color color;
  final double radius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;

    final Path outline = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            strokeWidth / 2,
            strokeWidth / 2,
            size.width - strokeWidth,
            size.height - strokeWidth,
          ),
          Radius.circular(radius),
        ),
      );

    // Walked with a PathMetric rather than drawn as four dashed lines: the
    // corners are arcs, and four straight runs would either overshoot them or
    // leave the radius undrawn.
    for (final PathMetric metric in outline.computeMetrics()) {
      double at = 0;
      while (at < metric.length) {
        final double end = (at + kGbmDashLength).clamp(0, metric.length);
        canvas.drawPath(metric.extractPath(at, end), paint);
        at = end + kGbmDashGap;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBoxPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}
