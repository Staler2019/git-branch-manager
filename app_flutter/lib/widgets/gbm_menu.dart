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
/// construction time. [_GbmMenuRow] renders such a row with a trailing
/// chevron and opens the flyout **on tap**, not on hover: `showGbmMenu` is
/// built on Material's `showMenu`, which inserts a modal barrier over
/// everything beneath it, so a hover-opened flyout would immediately make
/// the parent menu it came from unhoverable and unclickable. Tapping is the
/// affordance the chevron advertises, and it is what widget tests can drive.
/// `menu_bar_row.dart`'s View > Graph columns / Theme are visually
/// submenu-shaped in the design doc but are built with the plain
/// constructor (a real `onTap`, not `.submenu()`), since the parent itself
/// already resolves to a working action (a columns picker dialog, cycling
/// the theme) — [GbmMenuItem.submenu] is for an item whose only affordance
/// is its flyout.
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
    this.tooltip,
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
      tooltip = null,
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
      tooltip = null,
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

  /// Hover text explaining *why* an item is in the state it is in -- spec
  /// page 13's multi-select rule is explicit that a single-item-only action
  /// stays visible but disabled "並附 tooltip 說明原因，不隱藏" (kept with a
  /// tooltip giving the reason, not hidden), because hiding it reads as
  /// "this feature does not exist". Null means no tooltip.
  final String? tooltip;

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
  String? title,
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
        child: _GbmMenuPanel(items: items, title: title),
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
  List<GbmMenuItem> items, {
  String? title,
}) {
  validateGbmMenuItems(items);
  final RenderBox overlay =
      Overlay.of(context).context.findRenderObject()! as RenderBox;
  final RelativeRect position = RelativeRect.fromRect(
    Rect.fromPoints(globalPosition, globalPosition),
    Offset.zero & overlay.size,
  );
  return showGbmMenu(context, position: position, items: items, title: title);
}

class _GbmMenuPanel extends StatelessWidget {
  const _GbmMenuPanel({required this.items, this.title});

  final List<GbmMenuItem> items;

  /// Optional non-interactive header. Spec page 13 requires a multi-select
  /// context menu to name how many items it is about to act on ("選單標題
  /// 顯示數量"), so a right-click on a selection of three commits opens a
  /// menu headed "3 items" rather than looking identical to a single-row
  /// menu. It is a label, never a row: it takes no hover, no tap, and is
  /// deliberately not counted by [validateGbmMenuItems]'s 8-item cap, which
  /// is spec page 05's limit on *actions*.
  final String? title;

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (title case final String header) ...<Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Text(
                header,
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  fontWeight: GbmTypography.weightSemibold,
                  color: colors.textTertiary,
                ),
              ),
            ),
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              color: colors.borderSubtle,
            ),
          ],
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

  /// Opens this row's flyout to the right of the row, leaving the parent
  /// menu standing underneath it.
  ///
  /// Each child's callback is wrapped so that choosing one closes the parent
  /// too — the child row pops its own route, and this pops what is then the
  /// topmost route, the parent. **Order matters**: the parent is popped
  /// *before* the child's real action runs, because that action routinely
  /// pushes a dialog, and popping afterwards would take the dialog down
  /// instead of the menu. A child with no callback (a disabled item) is left
  /// alone, so tapping it closes only the flyout and changes nothing.
  void _openSubmenu() {
    final RenderBox row = context.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final Offset anchor = row.localToGlobal(
      row.size.topRight(Offset.zero),
      ancestor: overlay,
    );
    final NavigatorState parentNavigator = Navigator.of(context);

    void closeParent() {
      if (parentNavigator.canPop()) {
        parentNavigator.pop();
      }
    }

    showGbmMenu(
      context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(anchor, anchor),
        Offset.zero & overlay.size,
      ),
      items: <GbmMenuItem>[
        for (final GbmMenuItem child in widget.item.children)
          if (child.separator)
            const GbmMenuItem.separator()
          else
            GbmMenuItem(
              label: child.label,
              icon: child.icon,
              shortcut: child.shortcut,
              danger: child.danger,
              enabled: child.enabled,
              tooltip: child.tooltip,
              onTap: child.onTap == null
                  ? null
                  : () {
                      closeParent();
                      child.onTap!.call();
                    },
            ),
      ],
    );
  }

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

    final Widget row = MouseRegion(
      onEnter: (_) => setState(() => _hovered = item.enabled),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        // A submenu trigger opens its flyout and leaves this menu standing;
        // every other row closes the menu and then acts.
        onTap: item.isSubmenuTrigger
            ? _openSubmenu
            : () {
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
              if (item.isSubmenuTrigger)
                Icon(Icons.chevron_right, size: 14, color: foreground)
              else if (item.shortcut != null)
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

    // Wrapped outside MouseRegion, not inside the Container: a disabled row
    // is exactly the case a tooltip exists to explain, and Tooltip needs to
    // receive the pointer for the whole row to answer "why is this greyed
    // out?" rather than only over the label text.
    if (item.tooltip case final String message) {
      return Tooltip(message: message, child: row);
    }
    return row;
  }
}
