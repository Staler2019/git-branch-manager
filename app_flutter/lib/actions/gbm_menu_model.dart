import 'package:flutter/foundation.dart';

import 'gbm_action_id.dart';

/// Represents a single menu item.
///
/// This is a pure data class independent of the widget layer.
class GbmMenuItemModel {
  /// Creates a menu item.
  const GbmMenuItemModel({
    required this.id,
    required this.label,
    this.isSubmenuParent = false,
    this.isDanger = false,
    this.children = const <GbmMenuItemModel>[],
  });

  /// The action ID this menu item triggers.
  final GbmActionId id;

  /// The human-readable label for this menu item, verbatim from spec page
  /// 04's MENUS table -- sentence case, ellipsis only where the spec's own
  /// copy has one (per docs/design/tokens-reference.md's stated convention:
  /// "Sentence case throughout, including button labels").
  final String label;

  /// Whether this item opens a submenu.
  ///
  /// Two shapes share this flag:
  ///
  /// - [GbmActionId.viewGraphColumns] and [GbmActionId.viewTheme] leave
  ///   [children] empty and have their submenu content built at the widget
  ///   layer, because it is *dynamic* (the live column set, the available
  ///   theme variants). Both also resolve to a real handler, so their parent
  ///   row stays clickable as a one-click path to the same thing.
  /// - [GbmActionId.toolsRewriteHistory] declares its [children] here,
  ///   because they are three ordinary, fixed action items (spec page 14
  ///   rule 2: "破壞性或多步驟的三項…收進 Rewrite history 第二層"). It has no
  ///   handler of its own -- "rewrite history" names a group, not an action.
  ///
  /// Declaring fixed children in the model rather than special-casing a
  /// third id at the widget layer is deliberate: the widget layer already
  /// carries two such cases, and a third would make "which submenus exist"
  /// unanswerable from the model alone.
  final bool isSubmenuParent;

  /// This item's submenu entries, for a [isSubmenuParent] whose children are
  /// static. Empty for every other item, including the two dynamic submenu
  /// parents above.
  final List<GbmMenuItemModel> children;

  /// Whether this item should be displayed with danger/error styling.
  ///
  /// Only [GbmActionId.branchDeleteBranch] should have this set to `true`.
  final bool isDanger;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GbmMenuItemModel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          label == other.label &&
          isSubmenuParent == other.isSubmenuParent &&
          isDanger == other.isDanger &&
          listEquals(children, other.children);

  @override
  int get hashCode =>
      id.hashCode ^
      label.hashCode ^
      isSubmenuParent.hashCode ^
      isDanger.hashCode ^
      Object.hashAll(children);

  @override
  String toString() =>
      'GbmMenuItemModel(id: $id, label: $label, isSubmenuParent: $isSubmenuParent, isDanger: $isDanger)';
}

/// Represents a menu with its title and items.
///
/// This is a pure data class independent of the widget layer.
class GbmMenuModel {
  /// Creates a menu.
  const GbmMenuModel({required this.title, required this.items});

  /// The menu's title (e.g., "File", "Edit", "View").
  final String title;

  /// The items in this menu, in order.
  final List<GbmMenuItemModel> items;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GbmMenuModel &&
          runtimeType == other.runtimeType &&
          title == other.title &&
          items == other.items;

  @override
  int get hashCode => title.hashCode ^ items.hashCode;

  @override
  String toString() => 'GbmMenuModel(title: $title, items: ${items.length})';
}

/// The complete menu structure for the application.
///
/// This follows the design spec page 04's MENUS table (7 menus, 51 spec items)
/// plus context-menu-only actions (repositoryStageSelectedLines): 7 menus,
/// 52 items total, in the specified order, with labels verbatim from the
/// spec (sentence case, ellipsis where the spec's own copy has one). No
/// separators are included -- the spec's own MENUS data has none.
///
/// Menu-bar dropdowns are a different UI surface from the 11 right-click
/// context-menu groups on spec page 05: the page-05 prose's "flat, max 8
/// items" rule applies only to those, not to these dropdowns (View
/// legitimately has 11 items here, matching the spec's own MENUS table).
const List<GbmMenuModel> gbmMenus = <GbmMenuModel>[
  // File (8 items)
  GbmMenuModel(
    title: 'File',
    items: <GbmMenuItemModel>[
      GbmMenuItemModel(
        id: GbmActionId.fileNewRepository,
        label: 'New repository…',
      ),
      GbmMenuItemModel(
        id: GbmActionId.fileOpenRepository,
        label: 'Open repository…',
      ),
      GbmMenuItemModel(
        id: GbmActionId.fileCloneRepository,
        label: 'Clone repository…',
      ),
      GbmMenuItemModel(
        id: GbmActionId.fileSwitchRepository,
        label: 'Switch repository…',
      ),
      GbmMenuItemModel(
        id: GbmActionId.fileAddLocalRepository,
        label: 'Add local repository…',
      ),
      GbmMenuItemModel(id: GbmActionId.fileCloseWindow, label: 'Close window'),
      GbmMenuItemModel(id: GbmActionId.filePreferences, label: 'Preferences…'),
      GbmMenuItemModel(id: GbmActionId.fileExit, label: 'Exit'),
    ],
  ),

  // Edit (8 items)
  GbmMenuModel(
    title: 'Edit',
    items: <GbmMenuItemModel>[
      GbmMenuItemModel(id: GbmActionId.editUndo, label: 'Undo'),
      GbmMenuItemModel(id: GbmActionId.editRedo, label: 'Redo'),
      GbmMenuItemModel(id: GbmActionId.editCut, label: 'Cut'),
      GbmMenuItemModel(id: GbmActionId.editCopy, label: 'Copy'),
      GbmMenuItemModel(id: GbmActionId.editPaste, label: 'Paste'),
      GbmMenuItemModel(id: GbmActionId.editSelectAll, label: 'Select all'),
      GbmMenuItemModel(
        id: GbmActionId.editFindInHistory,
        label: 'Find in history',
      ),
      GbmMenuItemModel(id: GbmActionId.editFindInFiles, label: 'Find in files'),
      GbmMenuItemModel(
        id: GbmActionId.editFilterBranches,
        label: 'Filter branches',
      ),
    ],
  ),

  // View (11 items)
  GbmMenuModel(
    title: 'View',
    items: <GbmMenuItemModel>[
      GbmMenuItemModel(id: GbmActionId.viewHistory, label: 'History'),
      GbmMenuItemModel(id: GbmActionId.viewWorkingCopy, label: 'Working copy'),
      GbmMenuItemModel(id: GbmActionId.viewNextTab, label: 'Next tab'),
      GbmMenuItemModel(
        id: GbmActionId.viewFileListAsTree,
        label: 'File list as tree',
      ),
      GbmMenuItemModel(
        id: GbmActionId.viewGraphColumns,
        label: 'Graph columns',
        isSubmenuParent: true,
      ),
      GbmMenuItemModel(
        id: GbmActionId.viewCommitDetail,
        label: 'Commit detail',
      ),
      GbmMenuItemModel(
        id: GbmActionId.viewToggleSidebar,
        label: 'Toggle sidebar',
      ),
      GbmMenuItemModel(id: GbmActionId.viewStatusBar, label: 'Status bar'),
      GbmMenuItemModel(id: GbmActionId.viewLog, label: 'Log'),
      GbmMenuItemModel(
        id: GbmActionId.viewResetPanelSizes,
        label: 'Reset panel sizes',
      ),
      GbmMenuItemModel(
        id: GbmActionId.viewTheme,
        label: 'Theme',
        isSubmenuParent: true,
      ),
    ],
  ),

  // Repository (10 items)
  GbmMenuModel(
    title: 'Repository',
    items: <GbmMenuItemModel>[
      GbmMenuItemModel(id: GbmActionId.repositoryFetch, label: 'Fetch'),
      GbmMenuItemModel(id: GbmActionId.repositoryPull, label: 'Pull'),
      GbmMenuItemModel(id: GbmActionId.repositoryPush, label: 'Push'),
      GbmMenuItemModel(id: GbmActionId.repositoryCompare, label: 'Compare…'),
      GbmMenuItemModel(id: GbmActionId.repositoryCommit, label: 'Commit'),
      GbmMenuItemModel(
        id: GbmActionId.repositoryAmendLastCommit,
        label: 'Amend last commit',
      ),
      GbmMenuItemModel(id: GbmActionId.repositoryStageAll, label: 'Stage all'),
      GbmMenuItemModel(
        id: GbmActionId.repositoryOpenInTerminal,
        label: 'Open in terminal',
      ),
      GbmMenuItemModel(id: GbmActionId.repositorySettings, label: 'Settings…'),
      GbmMenuItemModel(
        id: GbmActionId.repositoryStageSelectedLines,
        label: 'Stage selected lines',
      ),
    ],
  ),

  // Branch (7 items)
  GbmMenuModel(
    title: 'Branch',
    items: <GbmMenuItemModel>[
      GbmMenuItemModel(id: GbmActionId.branchNewBranch, label: 'New branch…'),
      GbmMenuItemModel(id: GbmActionId.branchCheckout, label: 'Checkout…'),
      GbmMenuItemModel(
        // Spec's MENUS table says "Rename branch…", and since the dialog
        // this now opens can rename a branch named by the 05-B context
        // menu rather than only HEAD, the shorter label is also the
        // accurate one. The action id keeps its original name.
        id: GbmActionId.branchRenameCurrentBranch,
        label: 'Rename branch…',
      ),
      GbmMenuItemModel(
        id: GbmActionId.branchMergeIntoCurrent,
        label: 'Merge into current…',
      ),
      GbmMenuItemModel(id: GbmActionId.branchRebaseOnto, label: 'Rebase onto…'),
      GbmMenuItemModel(
        id: GbmActionId.branchStashChanges,
        label: 'Stash changes',
      ),
      GbmMenuItemModel(
        id: GbmActionId.branchDeleteBranch,
        label: 'Delete branch…',
        isDanger: true,
      ),
    ],
  ),

  // Remote (4 items)
  GbmMenuModel(
    title: 'Remote',
    items: <GbmMenuItemModel>[
      GbmMenuItemModel(id: GbmActionId.remoteAddRemote, label: 'Add remote…'),
      GbmMenuItemModel(
        id: GbmActionId.remoteFetchAllRemotes,
        label: 'Fetch all remotes',
      ),
      GbmMenuItemModel(
        id: GbmActionId.remotePruneRemoteBranches,
        label: 'Prune remote branches',
      ),
      GbmMenuItemModel(
        id: GbmActionId.remoteManageRemotes,
        label: 'Manage remotes…',
      ),
    ],
  ),

  // Tools (8 items) -- spec page 14's new eighth menu, placed between
  // Remote and Help per its rule 1: "放在 Remote 之後、Help 之前；它是「開一個
  // 面板」而不是「對目前分支做事」，所以不塞進 Repository". Labels are verbatim
  // from that page's TOOLSMENU table.
  //
  // Every item here opens a *tab*, not a dialog: TOOLSMENU's note column
  // reads 分頁 for all seven top-level panels, and page 14's IAMAP assigns
  // them to "分頁（與 History / Working copy / Compare 同一條分頁列）". The
  // exception is Clean untracked files…, which shares the submenu but
  // belongs to IAMAP's "中型表單 / 確認框" group and stays a dialog.
  GbmMenuModel(
    title: 'Tools',
    items: <GbmMenuItemModel>[
      GbmMenuItemModel(id: GbmActionId.toolsStashes, label: 'Stashes…'),
      GbmMenuItemModel(id: GbmActionId.toolsWorktrees, label: 'Worktrees…'),
      GbmMenuItemModel(id: GbmActionId.toolsRemotes, label: 'Remotes…'),
      GbmMenuItemModel(id: GbmActionId.toolsSubmodules, label: 'Submodules…'),
      GbmMenuItemModel(
        id: GbmActionId.toolsLargeFiles,
        label: 'Large files (LFS)…',
      ),
      GbmMenuItemModel(id: GbmActionId.toolsPatches, label: 'Patches…'),
      GbmMenuItemModel(id: GbmActionId.toolsReflog, label: 'Reflog…'),
      GbmMenuItemModel(
        id: GbmActionId.toolsRewriteHistory,
        label: 'Rewrite history',
        isSubmenuParent: true,
        children: <GbmMenuItemModel>[
          GbmMenuItemModel(
            id: GbmActionId.toolsInteractiveRebase,
            label: 'Interactive rebase…',
          ),
          GbmMenuItemModel(id: GbmActionId.toolsBisect, label: 'Bisect…'),
          GbmMenuItemModel(
            id: GbmActionId.toolsCleanUntrackedFiles,
            label: 'Clean untracked files…',
            isDanger: true,
          ),
        ],
      ),
    ],
  ),

  // Help (4 items)
  GbmMenuModel(
    title: 'Help',
    items: <GbmMenuItemModel>[
      GbmMenuItemModel(
        id: GbmActionId.helpDocumentation,
        label: 'Documentation',
      ),
      GbmMenuItemModel(
        id: GbmActionId.helpKeyboardShortcuts,
        label: 'Keyboard shortcuts',
      ),
      GbmMenuItemModel(
        id: GbmActionId.helpReportAnIssue,
        label: 'Report an issue',
      ),
      // Not in the spec at all -- the 21-page design predates this app
      // having any update mechanism. Help is where every desktop client puts
      // it, and it opens a dialog, so it takes the ellipsis P14 reserves for
      // dialog-openers.
      GbmMenuItemModel(
        id: GbmActionId.helpCheckForUpdates,
        label: 'Check for updates…',
      ),
      GbmMenuItemModel(id: GbmActionId.helpAbout, label: 'About'),
    ],
  ),
];
