import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';

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
/// Every item wired to a real destination points at an **existing** route
/// or callback -- nothing here duplicates the sidebar's own
/// create/rename/delete-branch flows (those already have a full UI; this
/// menu bar is a second entry point into the same session, not a second
/// implementation). Items with no corresponding destination in this app
/// today (File/Edit's New/Open/Clone/Cut/Copy/Paste/Find/Undo/Redo,
/// Branch's per-name actions, Remote's "Add remote…", Repository's "Remove
/// repository") are left as visual-only entries that close the menu on tap
/// -- the same inert state the design mockup's own JS gives them
/// (`onClick: close`, no real handler), so this is not a regression against
/// the design, just an honest one.
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
  final VoidCallback onFetch;
  final VoidCallback onPull;
  final VoidCallback onPush;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    void noop() {}

    final Map<String, List<GbmMenuItem>> menus = <String, List<GbmMenuItem>>{
      'File': <GbmMenuItem>[
        GbmMenuItem(
          label: 'New repository…',
          icon: Icons.create_new_folder_outlined,
          onTap: noop,
        ),
        GbmMenuItem(
          label: 'Open repository…',
          icon: Icons.folder_open_outlined,
          onTap: noop,
        ),
        GbmMenuItem(
          label: 'Clone repository…',
          icon: Icons.call_split,
          onTap: noop,
        ),
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Add local repository…',
          icon: Icons.add,
          onTap: noop,
        ),
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Preferences',
          icon: Icons.settings_outlined,
          onTap: () => context.push(RoutePaths.preferencesDialogFor(repoId)),
        ),
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Exit',
          icon: Icons.logout,
          onTap: SystemNavigator.pop,
        ),
      ],
      'Edit': <GbmMenuItem>[
        GbmMenuItem(
          label: 'Undo',
          icon: Icons.undo,
          shortcut: '⌘Z',
          onTap: noop,
        ),
        GbmMenuItem(
          label: 'Redo',
          icon: Icons.redo,
          shortcut: '⌘⇧Z',
          onTap: noop,
        ),
        const GbmMenuItem.separator(),
        GbmMenuItem(label: 'Cut', icon: Icons.content_cut, onTap: noop),
        GbmMenuItem(label: 'Copy', icon: Icons.content_copy, onTap: noop),
        GbmMenuItem(label: 'Paste', icon: Icons.content_paste, onTap: noop),
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Find in files',
          icon: Icons.search,
          shortcut: '⌘⇧F',
          onTap: noop,
        ),
      ],
      'View': <GbmMenuItem>[
        GbmMenuItem(
          label: 'History',
          icon: Icons.timeline,
          onTap: () => context.go(RoutePaths.historyFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Working Copy',
          icon: Icons.dashboard_outlined,
          onTap: () => context.go(RoutePaths.workingCopyFor(repoId)),
        ),
        // The design doc's "Repository Settings" is per-repo identity
        // override + performance settings -- exactly what this app's
        // (repo-scoped) Preferences dialog already holds, so it maps
        // there rather than to a separate "Repository" tab that doesn't
        // exist in this scope. "Diff" has no standalone destination in
        // this app (it's an inline pane within Working Copy/stash views,
        // not a routed page) and is deliberately omitted rather than
        // pointing at a dead end.
        GbmMenuItem(
          label: 'Repository Settings',
          icon: Icons.settings_outlined,
          onTap: () => context.push(RoutePaths.preferencesDialogFor(repoId)),
        ),
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Toggle sidebar',
          icon: sidebarVisible
              ? Icons.view_sidebar
              : Icons.view_sidebar_outlined,
          onTap: onToggleSidebar,
        ),
        GbmMenuItem(
          label: 'Preferences…',
          icon: Icons.tune,
          onTap: () => context.push(RoutePaths.preferencesDialogFor(repoId)),
        ),
      ],
      'Repository': <GbmMenuItem>[
        GbmMenuItem(
          label: 'Fetch',
          icon: Icons.cloud_download_outlined,
          onTap: onFetch,
        ),
        GbmMenuItem(
          label: 'Pull',
          icon: Icons.arrow_downward,
          shortcut: '⌘⇧P',
          onTap: onPull,
        ),
        GbmMenuItem(
          label: 'Push',
          icon: Icons.arrow_upward,
          shortcut: '⌘P',
          onTap: onPush,
        ),
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Repository settings…',
          icon: Icons.settings_outlined,
          onTap: () => context.push(RoutePaths.preferencesDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Open in terminal',
          icon: Icons.terminal,
          onTap: noop,
        ),
      ],
      'Branch': <GbmMenuItem>[
        GbmMenuItem(label: 'New branch…', icon: Icons.add, onTap: noop),
        GbmMenuItem(
          label: 'Rename current branch',
          icon: Icons.edit_outlined,
          onTap: noop,
        ),
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Merge into current branch',
          icon: Icons.call_merge,
          onTap: () => context.push(RoutePaths.mergeDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Rebase current branch onto…',
          icon: Icons.alt_route,
          onTap: () =>
              context.push(RoutePaths.interactiveRebaseDialogFor(repoId)),
        ),
        const GbmMenuItem.separator(),
        GbmMenuItem(
          label: 'Delete branch…',
          icon: Icons.delete_outline,
          danger: true,
          onTap: noop,
        ),
      ],
      'Remote': <GbmMenuItem>[
        GbmMenuItem(label: 'Add remote…', icon: Icons.add, onTap: noop),
        GbmMenuItem(
          label: 'Fetch all remotes',
          icon: Icons.cloud_download_outlined,
          onTap: onFetch,
        ),
        GbmMenuItem(
          label: 'Manage remotes…',
          icon: Icons.hub_outlined,
          onTap: () => context.push(RoutePaths.manageRemotesDialogFor(repoId)),
        ),
      ],
      'Help': <GbmMenuItem>[
        GbmMenuItem(
          label: 'Keyboard shortcuts',
          icon: Icons.keyboard_outlined,
          onTap: () => context.push(RoutePaths.keyboardShortcutsDialog),
        ),
        GbmMenuItem(
          label: 'About',
          icon: Icons.info_outline,
          onTap: () => context.push(RoutePaths.aboutDialog),
        ),
      ],
    };

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
