import 'package:flutter/material.dart';

import '../theme/gbm_theme.dart';
import '../theme/tokens.dart';

/// One row in a [showGbmMenu] popup: `.gbm-menu-sep` when [separator], else
/// a labeled, optionally-iconed/shortcut-annotated `.gbm-menu-item`
/// (`.gbm-menu-item.danger` when [danger]).
///
/// Not a sealed hierarchy: every menu builder in this app (menu bar,
/// context menus) constructs these as flat literal lists mixing items and
/// separators, which reads more like the design doc's own `{ sep: true }`
/// shape than a `switch` over item/separator subtypes would.
class GbmMenuItem {
  const GbmMenuItem({
    required this.label,
    this.icon,
    this.shortcut,
    this.danger = false,
    required this.onTap,
  }) : separator = false;

  const GbmMenuItem.separator()
    : label = '',
      icon = null,
      shortcut = null,
      danger = false,
      onTap = null,
      separator = true;

  final String label;
  final IconData? icon;
  final String? shortcut;
  final bool danger;
  final bool separator;
  final VoidCallback? onTap;
}

/// `.gbm-menu`/`.gbm-menu-item`/`.gbm-menu-shortcut`/`.gbm-menu-sep`
/// (docs/design/tokens-reference.md's components.css). Uses `showMenu`
/// purely as an overlay/positioning primitive -- `color: transparent`,
/// `elevation: 0`, and a single disabled [PopupMenuItem] wrapping our own
/// panel means none of Material's default menu chrome (surface tint,
/// built-in item hover/splash, default shape) ever paints.
Future<void> showGbmMenu(
  BuildContext context, {
  required RelativeRect position,
  required List<GbmMenuItem> items,
}) {
  return showMenu<void>(
    context: context,
    position: position,
    color: Colors.transparent,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
    items: <PopupMenuEntry<void>>[
      PopupMenuItem<void>(
        enabled: false,
        padding: EdgeInsets.zero,
        child: _GbmMenuPanel(items: items),
      ),
    ],
  );
}

/// Convenience for a right-click context menu: turns a raw
/// `TapDownDetails.globalPosition` (from `onSecondaryTapDown`) into the
/// `RelativeRect` [showGbmMenu] needs, anchored to the nearest [Overlay] --
/// the same idiom the Flutter cookbook uses for `showMenu` at a tap point.
/// Shared by every right-click surface (sidebar branch rows, changed-file
/// rows, repo list tiles, ...) so each doesn't re-derive the overlay math.
Future<void> showGbmContextMenu(
  BuildContext context,
  Offset globalPosition,
  List<GbmMenuItem> items,
) {
  final RenderBox overlay =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & overlay.size,
  );
  return showGbmMenu(context, position: position, items: items);
}

class _GbmMenuPanel extends StatelessWidget {
  const _GbmMenuPanel({required this.items});

  final List<GbmMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      constraints: const BoxConstraints(minWidth: 220),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceOverlay,
        border: Border.all(color: colors.borderDefault),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusMd),
        boxShadow: GbmEffects.shadowLg(_variantOf(colors)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final GbmMenuItem item in items)
            item.separator
                ? Container(
                    height: 1,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    color: colors.borderSubtle,
                  )
                : _GbmMenuRow(item: item),
        ],
      ),
    );
  }

  /// [GbmEffects.shadowLg] needs the variant only to pick a shadow alpha
  /// (deeper on dark) -- there is no reverse lookup from [GbmColors] back
  /// to [GbmThemeVariant], so this infers it the same way the app has no
  /// other place that needs to: a dark `surfaceApp` means the dark variant.
  GbmThemeVariant _variantOf(GbmColors colors) =>
      colors.surfaceApp.computeLuminance() < 0.5
      ? GbmThemeVariant.darkTechnical
      : GbmThemeVariant.lightIde;
}

class _GbmMenuRow extends StatefulWidget {
  const _GbmMenuRow({required this.item});

  final GbmMenuItem item;

  @override
  State<_GbmMenuRow> createState() => _GbmMenuRowState();
}

class _GbmMenuRowState extends State<_GbmMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final GbmMenuItem item = widget.item;
    final Color hoverBackground = item.danger ? colors.danger : colors.accent;
    final Color foreground = _hovered
        ? colors.textOnAccent
        : (item.danger ? colors.danger : colors.textPrimary);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Navigator.of(context).pop();
          item.onTap?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? hoverBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
          ),
          child: Row(
            children: <Widget>[
              if (item.icon != null) ...<Widget>[
                Icon(item.icon, size: 14, color: foreground),
                const SizedBox(width: GbmSpacing.space3),
              ],
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: foreground,
                  ),
                ),
              ),
              if (item.shortcut != null)
                Text(
                  item.shortcut!,
                  style: TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontSize: 10.5,
                    color: _hovered
                        ? foreground.withValues(alpha: 0.8)
                        : colors.textTertiary,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
