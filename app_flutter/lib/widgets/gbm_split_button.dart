import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';
import 'gbm_button.dart';
import 'gbm_menu.dart';

/// A ghost [GbmButton] with a ▾ segment beside it that opens a
/// [showGbmMenu] list under itself -- the worktree panel's `Open in
/// terminal` (open-with-apps-spec.html, screen 1).
///
/// The spec has no split button; its parts are borrowed and the borrowing is
/// declared in the spec's 推測值 list: the ▾ segment's 8px side padding is
/// `.gbm-btn-sm`'s, its 14px glyph is the menu's own chevron size
/// (`gbm_menu.dart`), and the 1×16 rule between them is P19's toolbar
/// divider. Each segment rounds only its outer corners so the pair reads as
/// one control.
///
/// [menuItems] is a builder, read when the menu opens, so the list is
/// whatever the caller's state says at that moment rather than at build.
class GbmSplitButton extends StatefulWidget {
  const GbmSplitButton({
    super.key,
    required this.label,
    required this.onPressed,
    required this.menuItems,
    required this.menuTooltip,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final List<GbmMenuItem> Function() menuItems;

  /// The ▾ segment has no label, so this is its name.
  final String menuTooltip;
  final Widget? icon;

  @override
  State<GbmSplitButton> createState() => _GbmSplitButtonState();
}

class _GbmSplitButtonState extends State<GbmSplitButton> {
  /// Keeps the ▾ segment in its hover ground while its menu is open, so it
  /// is plain which control the menu belongs to.
  bool _open = false;

  static const Radius _r = Radius.circular(GbmSpacing.radiusMd);

  Future<void> _openMenu(BuildContext segment) async {
    final List<GbmMenuItem> items = widget.menuItems();
    validateGbmMenuItems(items);
    final RenderBox box = segment.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(segment).context.findRenderObject()! as RenderBox;
    final Offset bottomLeft = box.localToGlobal(
      box.size.bottomLeft(Offset.zero),
      ancestor: overlay,
    );
    setState(() => _open = true);
    await showGbmMenu(
      segment,
      position: RelativeRect.fromRect(
        Rect.fromPoints(bottomLeft, bottomLeft),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        GbmButton(
          label: widget.label,
          kind: GbmButtonKind.ghost,
          icon: widget.icon,
          borderRadius: const BorderRadius.horizontal(left: _r),
          onPressed: widget.onPressed,
        ),
        Container(width: 1, height: 16, color: colors.borderSubtle),
        Builder(
          builder: (BuildContext segment) => Tooltip(
            message: widget.menuTooltip,
            child: Material(
              color: _open ? colors.surfaceHover : Colors.transparent,
              borderRadius: const BorderRadius.horizontal(right: _r),
              child: InkWell(
                onTap: () => _openMenu(segment),
                hoverColor: colors.surfaceHover,
                splashFactory: NoSplash.splashFactory,
                highlightColor: colors.surfaceHover,
                borderRadius: const BorderRadius.horizontal(right: _r),
                child: SizedBox(
                  height: 30,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: GbmSpacing.space2,
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      size: 14,
                      color: _open ? colors.textPrimary : colors.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
