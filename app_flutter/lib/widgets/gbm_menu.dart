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
///
/// A submenu item (created via [GbmMenuItem.submenu]) declares [children]
/// nested one level only — recursive submenus are forbidden and asserted at
/// construction time. NOTE: the flyout itself is not yet implemented —
/// [_GbmMenuRow] currently renders a submenu trigger's label only and its
/// `onTap` is always null, so tapping one just closes the menu. Until the
/// flyout renders, callers should treat [GbmMenuItem.submenu] as
/// display-only. `menu_bar_row.dart`'s View > Graph columns / Theme are
/// visually submenu-shaped in the design doc but are built with the plain
/// constructor (a real `onTap`, not `.submenu()`), since the parent itself
/// already resolves to a working action (a columns picker dialog, cycling
/// the theme) — [GbmMenuItem.submenu] is for a future item whose only
/// affordance is its flyout.
///
/// [enabled] (default `true`) is a purely visual signal — [_GbmMenuRow]
/// renders a disabled item with a fixed dim foreground and no hover
/// highlight, mirroring `repo_switcher_popover.dart`'s `_FooterAction`. It
/// does not gate [onTap]: dispatch is unchanged either way, so a caller
/// that never sets [enabled] keeps exactly its old click behavior, and a
/// caller mapping it from real action availability (`menu_bar_row.dart`)
/// gets a menu that visually matches what clicking it will do.
class GbmMenuItem {
  const GbmMenuItem({
    required this.label,
    this.icon,
    this.shortcut,
    this.danger = false,
    this.enabled = true,
    required this.onTap,
    this.children = const <GbmMenuItem>[],
  }) : separator = false,
       _isSubmenuTrigger = false;

  const GbmMenuItem.separator()
    : label = '',
      icon = null,
      shortcut = null,
      danger = false,
      enabled = true,
      onTap = null,
      separator = true,
      children = const <GbmMenuItem>[],
      _isSubmenuTrigger = false;

  /// Creates a submenu-triggering item that will render a flyout with
  /// [children] on hover/tap. In debug mode, asserts that [children] do not
  /// themselves contain submenu items (one level of nesting only).
  GbmMenuItem.submenu({required this.label, this.icon, required this.children})
    : separator = false,
      _isSubmenuTrigger = true,
      shortcut = null,
      danger = false,
      enabled = true,
      onTap = null {
    assert(_noNestedSubmenus(children));
  }

  static bool _noNestedSubmenus(List<GbmMenuItem> items) {
    for (final item in items) {
      if (item._isSubmenuTrigger) {
        return false;
      }
    }
    return true;
  }

  final String label;
  final IconData? icon;
  final String? shortcut;
  final bool danger;
  final bool enabled;
  final bool separator;
  final bool _isSubmenuTrigger;
  final VoidCallback? onTap;
  final List<GbmMenuItem> children;

  bool get isSubmenuTrigger => _isSubmenuTrigger;
}

/// Validates menu invariants: (a) at most 8 non-separator top-level items,
/// (b) if any item has [danger: true], it must be the last non-separator item
/// with exactly one separator immediately before it.
///
/// Only called from [showGbmContextMenu], not [showGbmMenu] directly --
/// rule (a) is spec page 05's own stated scope ("共 11 種右鍵目標...最上層
/// 一律扁平、最多 8 項"), specific to right-click context menus. Spec page
/// 04's menu-bar dropdowns are a different surface with no such cap (View
/// legitimately has 11 items, Repository 9, per the MENUS table) and must
/// not be run through this check.
void validateGbmMenuItems(List<GbmMenuItem> items) {
  final nonSeparatorItems = items.where((item) => !item.separator).toList();

  assert(
    nonSeparatorItems.length <= 8,
    'Menu has ${nonSeparatorItems.length} non-separator items; max is 8',
  );

  final dangerItem = nonSeparatorItems.cast<GbmMenuItem?>().firstWhere(
    (item) => item?.danger ?? false,
    orElse: () => null,
  );

  if (dangerItem != null) {
    assert(
      nonSeparatorItems.last == dangerItem,
      'Danger item must be the last non-separator item',
    );

    final dangerIndex = items.indexOf(dangerItem);
    assert(
      dangerIndex > 0 && items[dangerIndex - 1].separator,
      'Danger item must be immediately preceded by a separator',
    );
  }
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
  validateGbmMenuItems(items);
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
        boxShadow: GbmEffects.shadowLg(context.gbmThemeVariant),
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
    // Disabled: fixed dim foreground regardless of hover, no hover
    // highlight -- mirrors repo_switcher_popover.dart's _FooterAction.
    // Dispatch itself is untouched (see GbmMenuItem.enabled's doc comment):
    // this only changes what the row looks like, not whether tapping it
    // still calls item.onTap.
    final Color foreground = !item.enabled
        ? colors.textTertiary
        : (_hovered
              ? colors.textOnAccent
              : (item.danger ? colors.danger : colors.textPrimary));

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = item.enabled),
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
