import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// `.gbm-row`/`.gbm-row:hover`/`.gbm-row.selected`
/// (docs/design/tokens-reference.md's components.css): a hoverable,
/// optionally-selectable list row -- shared shell for the commit list, the
/// sidebar tree, and the repo list, so hover/selected backgrounds stay
/// consistent across all three instead of each screen rolling its own
/// `Container(color: selected ? ... : null)`.
class GbmRow extends StatelessWidget {
  const GbmRow({
    super.key,
    required this.child,
    this.selected = false,
    this.height = GbmSpacing.rowHeightComfortable,
    this.onTap,
    this.onSecondaryTapDown,
    this.padding = const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
  });

  final Widget child;
  final bool selected;
  final double height;
  final VoidCallback? onTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onSecondaryTapDown: onSecondaryTapDown,
        hoverColor: colors.surfaceHover,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
        child: Container(
          height: height,
          padding: padding,
          decoration: BoxDecoration(
            color: selected ? colors.surfaceSelected : null,
            borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
          ),
          child: child,
        ),
      ),
    );
  }
}
