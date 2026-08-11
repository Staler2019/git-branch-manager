import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// `.gbm-panel` (docs/design/tokens-reference.md's components.css): a
/// bordered, rounded container on `surfacePanel`.
class GbmPanel extends StatelessWidget {
  const GbmPanel({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border.all(color: colors.borderSubtle),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusLg),
      ),
      child: child,
    );
  }
}
