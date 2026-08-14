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
  });

  /// The action ID this menu item triggers.
  final GbmActionId id;

  /// The human-readable label for this menu item, verbatim from spec page
  /// 04's MENUS table -- sentence case, ellipsis only where the spec's own
  /// copy has one (per docs/design/tokens-reference.md's stated convention:
  /// "Sentence case throughout, including button labels").
  final String label;

  /// Whether this item is a submenu parent (not directly clickable).
  ///
  /// Only [GbmActionId.viewGraphColumns] and [GbmActionId.viewTheme] should
  /// have this set to `true`. Their actual submenu content is built at the
  /// widget layer.
  final bool isSubmenuParent;

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
          isDanger == other.isDanger;

  @override
  int get hashCode =>
      id.hashCode ^
      label.hashCode ^
      isSubmenuParent.hashCode ^
      isDanger.hashCode;

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
        id: GbmActionId.branchRenameCurrentBranch,
        label: 'Rename current branch…',
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
      GbmMenuItemModel(id: GbmActionId.helpAbout, label: 'About'),
    ],
  ),
];
