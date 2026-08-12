import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// `.gbm-iconbtn`/`.gbm-iconbtn.active` (docs/design/tokens-reference.md's
/// components.css): a 28x28 square icon button, transparent by default,
/// `surfaceHover` on hover, and a persistent `accentSubtle`/`accent` fill
/// when [active] -- used for things like the current theme swatch or an
/// open menu's trigger.
class GbmIconButton extends StatelessWidget {
  const GbmIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.active = false,
    this.tooltip,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final bool active;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final Widget button = SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        onPressed: onPressed,
        icon: icon,
        padding: EdgeInsets.zero,
        style: ButtonStyle(
          shape: WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
            ),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (active) return colors.accentSubtle;
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return colors.surfaceHover;
            }
            return Colors.transparent;
          }),
          iconColor: WidgetStatePropertyAll<Color>(
            active ? colors.accent : colors.textSecondary,
          ),
          overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}
