import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

/// How long one dash is, and how long the gap after it, in logical pixels.
///
/// **Not from the design, and not invented here either.** CSS's `dashed`
/// keyword names no pattern -- each engine picks its own -- and Flutter has
/// no dashed border at all, so 變體 B's `1px dashed var(--accent)` cannot
/// hand these over. 3/2 is what `gbm_tag_chip.dart`'s dashed remote-branch
/// chip has been drawing since it shipped, and matching it is the point: two
/// dashed outlines with different rhythms on one screen read as two
/// different kinds of line.
const double kGbmDashLength = 3;
const double kGbmDashGap = 2;

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
    this.segment = 0,
  });

  final Color color;
  final Axis axis;
  final double thickness;

  /// Which segment this line is of one longer rule cut into equal-length
  /// segments, counted from 0. Its dashes continue the rhythm the segments
  /// before it left off at, so a rule drawn one list item at a time reads as
  /// one rule; 0 starts on a dash.
  ///
  /// Equal length is the premise: the phase is `segment` times this line's
  /// own length. Segments of different lengths (soft-wrapped rows) still
  /// meet with a broken rhythm.
  final int segment;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: axis == Axis.vertical ? thickness : double.infinity,
      height: axis == Axis.horizontal ? thickness : double.infinity,
      child: CustomPaint(
        painter: _DashedLinePainter(color: color, axis: axis, segment: segment),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({
    required this.color,
    required this.axis,
    required this.segment,
  });

  final Color color;
  final Axis axis;
  final int segment;

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

    const double period = kGbmDashLength + kGbmDashGap;
    // Where the pattern would be if every earlier segment had been drawn as
    // part of this one: start that far back, and clip to this segment.
    double at = -((segment * length) % period);
    while (at < length) {
      final double start = at < 0 ? 0 : at;
      final double end = (at + kGbmDashLength).clamp(0, length).toDouble();
      if (end > start) {
        canvas.drawLine(
          axis == Axis.horizontal
              ? Offset(start, centre)
              : Offset(centre, start),
          axis == Axis.horizontal ? Offset(end, centre) : Offset(centre, end),
          paint,
        );
      }
      at += period;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter old) =>
      old.color != color || old.axis != axis || old.segment != segment;
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
