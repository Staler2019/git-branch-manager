import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../actions/gbm_menu_model.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';
import 'workspace_action_shortcuts.dart';

/// The design doc's 32px menu bar: logo + seven top-level menus (File,
/// Edit, View, Repository, Branch, Remote, Help), each opening a
/// [showGbmMenu] positioned right below its label.
///
/// Purely presentational -- [onFetch]/[onPull]/[onPush] are passed in
/// rather than read from `repoSessionProvider` here, so this widget has no
/// Riverpod/FFI dependency of its own and is testable with plain
/// `VoidCallback`s (see menu_bar_row_test.dart). `workspace_screen.dart`,
/// which already holds a `WidgetRef` for the open session, wires them to
/// `RepoSessionController.fetchRemote`/`pullChanges`/`pushChanges`.
///
/// Menu items are sourced from [gbmMenus], not hardcoded. Each item's tap
/// handler is resolved via:
/// 1. For the special named callbacks (fetch/pull/push/toggle-sidebar),
///    the corresponding parameter is called.
/// 2. For all other items, [Actions.maybeInvoke] dispatches a [GbmActionIntent],
///    allowing the keyboard shortcut path and the menu-click path to reach the
///    same handler. This requires a [WorkspaceActionShortcuts] ancestor (which
///    is wired by [WorkspaceScreen]). On missing Actions ancestor, items are
///    visually clickable but do nothing (no crash).
///
/// Items with no handler (either no callback parameter and no Actions ancestor,
/// or a null handler in the Actions map) close the menu on tap but take no action.
class MenuBarRow extends StatelessWidget {
  const MenuBarRow({
    super.key,
    required this.repoId,
    required this.sidebarVisible,
    required this.onToggleSidebar,
    required this.onFetch,
    required this.onPull,
    required this.onPush,
  });

  final String repoId;
  final bool sidebarVisible;
  final VoidCallback onToggleSidebar;
  final VoidCallback? onFetch;
  final VoidCallback? onPull;
  final VoidCallback? onPush;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    // Build menu items from gbmMenus
    final Map<String, List<GbmMenuItem>> menus = _buildMenusFromModels(context);

    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: GbmSpacing.space3),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.merge_type, size: 14, color: colors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'git-branch-manager',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    fontWeight: GbmTypography.weightSemibold,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          // The seven menus don't fit an 800px-ish narrow window at once --
          // scroll horizontally rather than hard-overflow (RenderFlex
          // overflow is a thrown error in debug/test builds, not just a
          // visual clip).
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final MapEntry<String, List<GbmMenuItem>> menu
                      in menus.entries)
                    _MenuBarButton(label: menu.key, items: menu.value),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Converts [gbmMenus] to a map of menu labels to [GbmMenuItem] lists,
  /// wiring tap handlers to either the named callback params or to Actions.
  Map<String, List<GbmMenuItem>> _buildMenusFromModels(BuildContext context) {
    final Map<String, List<GbmMenuItem>> result = <String, List<GbmMenuItem>>{};

    for (final GbmMenuModel menuModel in gbmMenus) {
      result[menuModel.title] = <GbmMenuItem>[
        for (final item in menuModel.items)
          _buildMenuItemFromModel(context, item),
      ];
    }

    return result;
  }

  /// Converts a [GbmMenuItemModel] to a [GbmMenuItem] with the tap handler
  /// wired appropriately.
  GbmMenuItem _buildMenuItemFromModel(
    BuildContext context,
    GbmMenuItemModel itemModel,
  ) {
    // Submenu parents (viewGraphColumns, viewTheme) are still clickable:
    // both resolve to a real handler (a columns picker dialog, and cycling
    // the theme variant), so rendering them inert made two working actions
    // look broken. The nested submenu itself is a separate affordance; the
    // parent stays the one-click path to the same thing.
    final VoidCallback? handler = _resolveHandler(context, itemModel.id);

    return GbmMenuItem(
      label: itemModel.label,
      danger: itemModel.isDanger,
      onTap: handler,
    );
  }

  /// Resolves the tap handler for a given [GbmActionId].
  ///
  /// Priority:
  /// 1. If it's one of the special named-callback items, call that callback.
  /// 2. For all others, dispatch via [Actions.maybeInvoke] if an Actions
  ///    ancestor exists, otherwise no-op (null).
  VoidCallback? _resolveHandler(BuildContext context, GbmActionId id) {
    // Special cases: named callback parameters
    switch (id) {
      case GbmActionId.repositoryFetch:
        return onFetch;
      case GbmActionId.repositoryPull:
        return onPull;
      case GbmActionId.repositoryPush:
        return onPush;
      case GbmActionId.viewToggleSidebar:
        return onToggleSidebar;
      case GbmActionId.fileExit:
        return SystemNavigator.pop;
      default:
        break;
    }

    // For all other items, dispatch via Actions if available
    final actionsFound = Actions.maybeFind<GbmActionIntent>(context) != null;
    if (actionsFound) {
      return () => Actions.maybeInvoke(context, GbmActionIntent(id));
    }

    // No handler available
    return null;
  }
}

class _MenuBarButton extends StatelessWidget {
  const _MenuBarButton({required this.label, required this.items});

  final String label;
  final List<GbmMenuItem> items;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Builder(
      builder: (buttonContext) => InkWell(
        onTap: () => _open(buttonContext, items),
        borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext buttonContext, List<GbmMenuItem> items) {
    final RenderBox button = buttonContext.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(buttonContext).context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    showGbmMenu(buttonContext, position: position, items: items);
  }
}
