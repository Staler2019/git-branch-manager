import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

enum GbmButtonKind { primary, secondary, ghost }

/// `.gbm-btn`/`.gbm-btn-primary`/`.gbm-btn-secondary`/`.gbm-btn-ghost`
/// (docs/design/tokens-reference.md's components.css).
class GbmButton extends StatelessWidget {
  const GbmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = GbmButtonKind.secondary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final GbmButtonKind kind;
  final Widget? icon;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final (Color background, Color foreground, Color? border) = switch (kind) {
      GbmButtonKind.primary => (colors.accent, colors.textOnAccent, null),
      GbmButtonKind.secondary => (colors.surfacePanelRaised, colors.textPrimary, colors.borderDefault),
      GbmButtonKind.ghost => (Colors.transparent, colors.textSecondary, null),
    };

    final ButtonStyle style = TextButton.styleFrom(
      backgroundColor: background,
      foregroundColor: foreground,
      disabledForegroundColor: foreground.withValues(alpha: 0.45),
      side: border == null ? null : BorderSide(color: border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(GbmSpacing.radiusMd)),
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
    );
    final Text labelWidget = Text(
      label,
      style: TextStyle(fontSize: GbmTypography.textSm, fontWeight: GbmTypography.weightMedium),
    );

    return SizedBox(
      height: 30,
      child: icon == null
          ? TextButton(onPressed: onPressed, style: style, child: labelWidget)
          : TextButton.icon(onPressed: onPressed, icon: icon!, label: labelWidget, style: style),
    );
  }
}
