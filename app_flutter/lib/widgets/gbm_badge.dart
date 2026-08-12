import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// `.gbm-badge-added`/`.gbm-badge-removed`/`.gbm-badge-neutral`
/// (docs/design/tokens-reference.md's components.css).
enum GbmBadgeKind { added, removed, neutral }

/// `.gbm-badge` (docs/design/tokens-reference.md's components.css): a small
/// pill for a `+N`/`-N` diff line count or a neutral count/label, mono
/// font, min 18x18.
class GbmBadge extends StatelessWidget {
  const GbmBadge({
    super.key,
    required this.label,
    this.kind = GbmBadgeKind.neutral,
  });

  final String label;
  final GbmBadgeKind kind;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final (Color background, Color foreground) = switch (kind) {
      GbmBadgeKind.added => (colors.diffAddBg, colors.diffAddText),
      GbmBadgeKind.removed => (colors.diffDelBg, colors.diffDelText),
      GbmBadgeKind.neutral => (colors.surfaceSunken, colors.textSecondary),
    };
    return Container(
      constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(GbmSpacing.radiusFull),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: GbmTypography.fontMono,
          fontSize: 10.5,
          fontWeight: GbmTypography.weightSemibold,
          color: foreground,
        ),
      ),
    );
  }
}
