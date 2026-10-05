import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// `.gbm-tab`/`.gbm-tab:hover`/`.gbm-tab.active` (the spec's components
/// CSS): one tab of a tab strip. The label is `--text-secondary`, turning
/// `--text-primary` on hover and when active; an active tab carries a 2px
/// accent underline. `:hover` sets a colour and nothing else, so the ink is
/// switched off -- a hand-rolled InkWell's default `ThemeData.hoverColor`
/// is a near-invisible grey fill the spec never asked for.
///
/// Shared by the workspace [TabRow] and the Repository Settings dialog, which
/// differ in padding and weight; each passes its own rather than either one
/// being promoted to the default for both.
class GbmTab extends StatefulWidget {
  const GbmTab({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.restColor,
    this.padding = const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
    this.fontWeight = GbmTypography.weightMedium,
    this.activeFontWeight,
    this.trailing = const <Widget>[],
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  /// An inactive label colour that hover does not change -- for a tab whose
  /// mockup sets an inline colour, which outranks `.gbm-tab:hover`.
  final Color? restColor;

  final EdgeInsetsGeometry padding;
  final FontWeight fontWeight;

  /// Defaults to [fontWeight].
  final FontWeight? activeFontWeight;

  /// Drawn after the label, inside the tab (a badge, a close button).
  final List<Widget> trailing;

  @override
  State<GbmTab> createState() => _GbmTabState();
}

class _GbmTabState extends State<GbmTab> {
  bool _hovered = false;

  Color _labelColor(GbmColors colors) {
    if (widget.active) return colors.textPrimary;
    final Color? rest = widget.restColor;
    if (rest != null) return rest;
    return _hovered ? colors.textPrimary : colors.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool active = widget.active;
    return InkWell(
      onTap: widget.onTap,
      onHover: (bool hovered) => setState(() => _hovered = hovered),
      hoverColor: Colors.transparent,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: Container(
        alignment: Alignment.center,
        padding: widget.padding,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.label,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                fontWeight: active
                    ? (widget.activeFontWeight ?? widget.fontWeight)
                    : widget.fontWeight,
                color: _labelColor(colors),
              ),
            ),
            ...widget.trailing,
          ],
        ),
      ),
    );
  }
}
