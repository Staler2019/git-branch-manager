import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

enum GbmButtonKind { primary, secondary, ghost, danger }

/// `.gbm-btn-sm` (height 24, text-xs, padding 0 8) vs. the default
/// `.gbm-btn` sizing (height 30, text-sm, padding 0 12).
enum GbmButtonSize { normal, sm }

/// `.gbm-btn`/`.gbm-btn-primary`/`.gbm-btn-secondary`/`.gbm-btn-ghost`/
/// `.gbm-btn-danger`/`.gbm-btn-sm` (docs/design/tokens-reference.md's
/// components.css). Hover/pressed backgrounds are per-kind, matching the
/// design's `:hover`/`:active` rules -- not just a flat opacity overlay.
class GbmButton extends StatelessWidget {
  const GbmButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = GbmButtonKind.secondary,
    this.size = GbmButtonSize.normal,
    this.icon,
    this.lineThrough = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final GbmButtonKind kind;
  final GbmButtonSize size;
  final Widget? icon;

  /// Strikes the label through. Spec P03's 變體 B uses it on a scope card
  /// whose button a live text selection has superseded: the button stays
  /// visible so the user can see what it *would* have done, with
  /// `onPressed: null` so it cannot fire -- struck-through-but-live is the
  /// same trap as `GbmMenuItem.enabled: false` with a real `onTap`.
  final bool lineThrough;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final (
      Color background,
      Color hoverBackground,
      Color pressedBackground,
      Color foreground,
      Color? border,
    ) = switch (kind) {
      GbmButtonKind.primary => (
        colors.accent,
        colors.accentHover,
        colors.accentActive,
        colors.textOnAccent,
        null,
      ),
      GbmButtonKind.secondary => (
        colors.surfacePanelRaised,
        colors.surfaceHover,
        colors.surfaceHover,
        colors.textPrimary,
        colors.borderDefault,
      ),
      GbmButtonKind.ghost => (
        Colors.transparent,
        colors.surfaceHover,
        colors.surfaceHover,
        colors.textSecondary,
        null,
      ),
      GbmButtonKind.danger => (
        Colors.transparent,
        colors.diffDelBg,
        colors.diffDelBg,
        colors.danger,
        colors.borderDefault,
      ),
    };
    final Color hoverBorder = kind == GbmButtonKind.danger
        ? colors.danger
        : (border ?? Colors.transparent);
    final double height = size == GbmButtonSize.sm ? 24 : 30;
    final double fontSize = size == GbmButtonSize.sm
        ? GbmTypography.textXs
        : GbmTypography.textSm;
    final double horizontalPadding = size == GbmButtonSize.sm
        ? GbmSpacing.space2
        : GbmSpacing.space3;

    final ButtonStyle style = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) return pressedBackground;
        if (states.contains(WidgetState.hovered)) return hoverBackground;
        return background;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return foreground.withValues(alpha: 0.45);
        }
        return foreground;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (border == null) return null;
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)) {
          return BorderSide(color: hoverBorder);
        }
        return BorderSide(color: border);
      }),
      shape: WidgetStatePropertyAll<OutlinedBorder>(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
        ),
      ),
      padding: WidgetStatePropertyAll<EdgeInsets>(
        EdgeInsets.symmetric(horizontal: horizontalPadding),
      ),
      minimumSize: const WidgetStatePropertyAll<Size>(Size(0, 0)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
    final Text labelWidget = Text(
      label,
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: GbmTypography.weightMedium,
        decoration: lineThrough ? TextDecoration.lineThrough : null,
      ),
    );

    return SizedBox(
      height: height,
      child: icon == null
          ? TextButton(onPressed: onPressed, style: style, child: labelWidget)
          : TextButton.icon(
              onPressed: onPressed,
              icon: icon!,
              label: labelWidget,
              style: style,
            ),
    );
  }
}
