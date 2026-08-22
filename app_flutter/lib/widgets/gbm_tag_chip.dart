import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../data/models/ref_snapshot.dart';
import '../theme/gbm_theme.dart';
import '../theme/ref_chip_colors.dart';
import '../theme/tokens.dart';
import 'lucide_icon.dart';

/// `.gbm-tag`/`.gbm-tag-branch`/`.gbm-tag-branch.current`/`.gbm-tag-tag`
/// (docs/design/tokens-reference.md's components.css).
class GbmTagChip extends StatelessWidget {
  const GbmTagChip({
    super.key,
    required this.label,
    required this.kind,
    this.isCurrent = false,
    this.showCloudIcon = false,
    this.isDashed = false,
  });

  final String label;
  final RefKind kind;
  final bool isCurrent;

  /// Trailing cloud icon marking a local branch chip whose upstream remote
  /// branch is synced to the same commit (`graph_ref_chips.dart`'s
  /// `RefChipData.showCloudIcon`) -- spec page 02: "local 與 origin 在同一
  /// 個 commit 時只出一個 chip，尾端加一個雲朵圖示".
  final bool showCloudIcon;

  /// Dashed outline marking a remote branch chip whose tracking local
  /// branch has diverged (`RefChipData.isDashed`) -- spec page 02: "虛線外
  /// 框＝只有在分歧時才會出現，標出遠端落在哪個 commit".
  final bool isDashed;

  @override
  Widget build(BuildContext context) {
    final RefChipColors chip = refChipColorsFor(
      context.gbmColors,
      kind,
      isCurrent: isCurrent,
    );
    final BorderRadius radius = BorderRadius.circular(GbmSpacing.radiusFull);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            label,
            style: TextStyle(
              fontFamily: GbmTypography.fontMono,
              fontSize: GbmTypography.textXs,
              fontWeight: GbmTypography.weightMedium,
              color: chip.text,
            ),
          ),
          if (showCloudIcon) ...<Widget>[
            const SizedBox(width: 3),
            LucideIcon('cloud', size: 9.5, color: chip.text),
          ],
        ],
      ),
    );

    if (isDashed) {
      // Flutter's Border has no dashed style, so the dashed outline is
      // painted separately over a border-less fill instead of going through
      // BoxDecoration.border like the solid case below.
      return CustomPaint(
        painter: _DashedRRectPainter(radius: radius, color: chip.border),
        child: DecoratedBox(
          decoration: BoxDecoration(color: chip.fill, borderRadius: radius),
          child: content,
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: chip.fill,
        border: Border.all(color: chip.border),
        borderRadius: radius,
        // Spec's `CHIP_HEAD` is `CHIP_LOCAL` plus `box-shadow:0 0 0 2px
        // var(--accent-subtle)` (`spec_logic.js:433`), and its prose reads
        // that ring as the HEAD signal itself: "實心加外光暈…＝目前 HEAD".
        // A zero-blur BoxShadow at spreadRadius 2 is the same ring; it
        // paints outside the box, so it changes nothing about layout -- the
        // strip's 4px inter-chip gap already absorbs two of them meeting.
        boxShadow: isCurrent
            ? <BoxShadow>[
                BoxShadow(
                  color: context.gbmColors.accentSubtle,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: content,
    );
  }
}

/// Paints a dashed rounded-rect outline, since [Border] has no built-in
/// dashed style. Kept private and narrowly scoped to [GbmTagChip]'s dashed
/// variant rather than a general-purpose dashed-border widget -- no other
/// caller needs one yet (YAGNI).
class _DashedRRectPainter extends CustomPainter {
  const _DashedRRectPainter({required this.radius, required this.color});

  final BorderRadius radius;
  final Color color;

  static const double _dashWidth = 3;
  static const double _dashGap = 2;

  @override
  void paint(Canvas canvas, Size size) {
    // Deflate by half the stroke width so the 1px stroke draws inside the
    // chip's bounds instead of getting clipped at the edge.
    final RRect rrect = radius.toRRect(Offset.zero & size).deflate(0.5);
    final Path path = Path()..addRRect(rrect);
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (final PathMetric metric in path.computeMetrics()) {
      double distance = 0;
      while (distance < metric.length) {
        final double next = distance + _dashWidth;
        canvas.drawPath(
          metric.extractPath(distance, next.clamp(0, metric.length)),
          paint,
        );
        distance = next + _dashGap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRRectPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.radius != radius;
}
