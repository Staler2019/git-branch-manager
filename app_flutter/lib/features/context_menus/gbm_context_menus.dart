/// Context menu specifications for all 11 context menu targets in the app.
///
/// Each group defines the exact structure, label text, and ordering of items
/// for a specific context (right-click target). Separators are not modeled
/// explicitly in the data: they are automatically inserted before any danger
/// item at render time (the "danger item is always preceded by separator"
/// invariant is enforced by menu validation in gbm_menu.dart).
///
/// Format: each group lists its top-level items in order. For groups with
/// submenus (05-E: "More actions", 05-K: "More actions"), the submenu's
/// children are listed under that item. No item may contain a nested submenu.
///
/// Danger items (marked with `isDanger: true`) must be the last top-level
/// item in their group. Non-submenu-trigger items may have an `enabled` field
/// (a compile-time predicate) for runtime filtering by the caller.
library;

enum GbmContextMenuTarget {
  /// Right-click a repository row in the repo-switcher popover (not yet wired).
  repository, // 05-A
  /// Right-click a local branch row in the sidebar.
  localBranch, // 05-B
  /// Right-click a remote-only or "gone" branch row in the sidebar. Wired via
  /// `branch_tree_item.dart`'s `_buildMenuItems()`, which distinguishes the
  /// two cases itself: a remote-only row gets its own 05-C subset, and a
  /// "gone" row goes through `_buildGoneMenuItems()`, which per the spec
  /// note leaves only "Prune this ref" and "Copy branch name" enabled with
  /// the rest disabled (not omitted).
  remoteOnlyOrGoneBranch, // 05-C
  /// Right-click a branch folder row (e.g., feature/, bugfix/) in the sidebar.
  /// Not yet wired.
  branchFolder, // 05-J
  /// Right-click a tag row in the sidebar TAGS section (not yet wired).
  tag, // 05-D
  /// Right-click a commit row in the history graph.
  /// Not yet wired. Has a submenu ("More actions").
  commit, // 05-E
  /// Right-click a file row in the working-copy panel.
  workingCopyFile, // 05-F
  /// Right-click a file row inside a historical commit's Changed Files panel.
  /// Not yet wired. Has a submenu ("More actions").
  historyCommitFile, // 05-K
  /// Right-click a line or line selection inside a diff pane.
  /// Not yet wired. First item's label becomes "Stage N lines" when multiple
  /// lines are drag-selected (not yet implemented).
  diffLine, // 05-G
  /// Right-click a stash entry in the sidebar STASH section (not yet wired).
  stashEntry, // 05-H
  /// Right-click a conflict hunk inside the conflict-resolution window.
  /// Not yet wired.
  conflictHunk, // 05-I
}

/// Describes a single item in a context menu: label, danger flag, and
/// (optionally for submenus) children list.
///
/// Separators are NOT modeled here: the render-time code infers them from
/// the "danger item must be last and have a separator before it" invariant.
class GbmContextMenuItemSpec {
  const GbmContextMenuItemSpec({
    required this.label,
    this.isDanger = false,
    this.isSubmenuTrigger = false,
    this.children = const <GbmContextMenuItemSpec>[],
    this.enabled,
  });

  /// Human-readable label for this menu item.
  final String label;

  /// True if this item is a danger action (delete/discard/etc.).
  /// If true, this must be the last non-submenu-trigger item in its group.
  final bool isDanger;

  /// True if this item triggers a submenu flyout with [children] on hover/tap.
  /// Only one level of nesting is allowed; children may not themselves have
  /// `isSubmenuTrigger: true`.
  final bool isSubmenuTrigger;

  /// Child items for submenu triggers. Only non-empty when
  /// [isSubmenuTrigger] is true.
  final List<GbmContextMenuItemSpec> children;

  /// Optional compile-time predicate for runtime filtering. The caller
  /// evaluates this at render time to disable/hide items based on state.
  /// For example, 05-C (remote-only branch) uses this to disable most items
  /// when the branch is "gone" rather than "remote-only".
  /// If null, the item is always enabled.
  final bool Function()? enabled;
}

/// Describes the structure of one context menu group.
class GbmContextMenuGroupSpec {
  const GbmContextMenuGroupSpec({
    required this.id,
    required this.target,
    required this.title,
    required this.items,
  });

  /// Spec group ID, e.g. '05-A', '05-B', etc.
  final String id;

  /// The target this menu is for (one of [GbmContextMenuTarget] enum).
  final GbmContextMenuTarget target;

  /// Human-readable title for this context menu, e.g. "Local branch".
  final String title;

  /// Top-level menu items in order. Separators are NOT included in this list;
  /// they are inferred at render time. Danger items must be last.
  final List<GbmContextMenuItemSpec> items;
}

// ============================================================================
// All 11 Context Menu Groups (in spec order 05-A through 05-I)
// ============================================================================

/// 05-A: Repository (right-click a row in the switcher popover -- EXISTS,
/// see `RepoSwitcherRow._openContextMenu`; fetch/pull/push are left off
/// there, since a repository in that list has no open session to act on)
/// 7 top-level items.
const GbmContextMenuGroupSpec _repo = GbmContextMenuGroupSpec(
  id: '05-A',
  target: GbmContextMenuTarget.repository,
  title: 'Repository',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'Open in file manager'),
    GbmContextMenuItemSpec(label: 'Open in terminal'),
    GbmContextMenuItemSpec(label: 'Fetch'),
    GbmContextMenuItemSpec(label: 'Pull'),
    GbmContextMenuItemSpec(label: 'Push'),
    GbmContextMenuItemSpec(label: 'Settings…'),
    GbmContextMenuItemSpec(label: 'Remove from list', isDanger: true),
  ],
);

/// 05-B: Local branch (right-click branch row in sidebar -- EXISTS)
/// 8 top-level items (at ceiling). No submenu.
const GbmContextMenuGroupSpec _localBranch = GbmContextMenuGroupSpec(
  id: '05-B',
  target: GbmContextMenuTarget.localBranch,
  title: 'Local branch',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'Checkout'),
    GbmContextMenuItemSpec(label: 'New branch from here…'),
    GbmContextMenuItemSpec(label: 'Rename…'),
    GbmContextMenuItemSpec(label: 'Merge into current'),
    GbmContextMenuItemSpec(label: 'Rebase current onto here'),
    GbmContextMenuItemSpec(label: 'Compare with…'),
    GbmContextMenuItemSpec(label: 'Copy branch name'),
    GbmContextMenuItemSpec(label: 'Delete branch…', isDanger: true),
  ],
);

/// 05-C: Remote-only / gone branch (right-click cloud/cloud-off row -- not yet wired)
/// 5 top-level items. Spec note: for a "gone" row specifically, only
/// "Prune this ref" and "Copy branch name" stay enabled; others disabled.
const GbmContextMenuGroupSpec _remoteOnlyOrGoneBranch = GbmContextMenuGroupSpec(
  id: '05-C',
  target: GbmContextMenuTarget.remoteOnlyOrGoneBranch,
  title: 'Remote-only / gone branch',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'Checkout as new local…'),
    GbmContextMenuItemSpec(label: 'Fetch this branch'),
    GbmContextMenuItemSpec(label: 'Copy branch name'),
    GbmContextMenuItemSpec(label: 'Prune this ref'),
    GbmContextMenuItemSpec(label: 'Delete on remote…', isDanger: true),
  ],
);

/// 05-J: Branch folder (right-click folder row like feature/ -- not yet wired)
/// 4 top-level items.
const GbmContextMenuGroupSpec _branchFolder = GbmContextMenuGroupSpec(
  id: '05-J',
  target: GbmContextMenuTarget.branchFolder,
  title: 'Branch folder',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'Expand all / Collapse all'),
    GbmContextMenuItemSpec(label: 'Fetch branches in folder'),
    GbmContextMenuItemSpec(label: 'Copy folder prefix'),
    GbmContextMenuItemSpec(label: 'Delete merged branches…', isDanger: true),
  ],
);

/// 05-D: Tag (right-click TAGS-section item -- not yet wired)
/// 5 top-level items.
const GbmContextMenuGroupSpec _tag = GbmContextMenuGroupSpec(
  id: '05-D',
  target: GbmContextMenuTarget.tag,
  title: 'Tag',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'Checkout tag (detached)'),
    GbmContextMenuItemSpec(label: 'Push tag'),
    GbmContextMenuItemSpec(label: 'Compare with…'),
    GbmContextMenuItemSpec(label: 'Copy tag name'),
    GbmContextMenuItemSpec(label: 'Delete tag…', isDanger: true),
  ],
);

/// 05-E: Commit (right-click history commit row -- not yet wired)
/// 7 top-level items, no danger at top level. Has a submenu ("More actions").
const GbmContextMenuGroupSpec _commit = GbmContextMenuGroupSpec(
  id: '05-E',
  target: GbmContextMenuTarget.commit,
  title: 'Commit',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'Checkout this commit'),
    GbmContextMenuItemSpec(label: 'Merge into current'),
    GbmContextMenuItemSpec(label: 'Cherry-pick'),
    GbmContextMenuItemSpec(label: 'Create branch here…'),
    GbmContextMenuItemSpec(label: 'Compare with…'),
    GbmContextMenuItemSpec(label: 'Copy SHA'),
    GbmContextMenuItemSpec(
      label: 'More actions',
      isSubmenuTrigger: true,
      children: <GbmContextMenuItemSpec>[
        GbmContextMenuItemSpec(label: 'Rebase onto here'),
        GbmContextMenuItemSpec(label: 'Reset branch to here…'),
        GbmContextMenuItemSpec(label: 'Revert commit'),
        GbmContextMenuItemSpec(label: 'Export as patch…'),
        GbmContextMenuItemSpec(label: 'Compare with working copy'),
      ],
    ),
  ],
);

/// 05-F: File (staged / unstaged) in working copy (right-click file row -- EXISTS)
/// 6 top-level items. Note: multi-select label pluralization (e.g. "Stage 3 files")
/// is NOT yet implemented; this defines the singular form.
const GbmContextMenuGroupSpec _workingCopyFile = GbmContextMenuGroupSpec(
  id: '05-F',
  target: GbmContextMenuTarget.workingCopyFile,
  title: 'File (staged / unstaged)',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'Stage'),
    GbmContextMenuItemSpec(label: 'Open file'),
    GbmContextMenuItemSpec(label: 'Show in file manager'),
    GbmContextMenuItemSpec(label: 'Open terminal here'),
    GbmContextMenuItemSpec(label: 'Copy path'),
    GbmContextMenuItemSpec(label: 'Discard changes', isDanger: true),
  ],
);

/// 05-K: Commit file (inside History Changed Files panel -- not yet wired)
/// 8 top-level items (at ceiling), no danger at top level. Has a submenu
/// ("More actions").
const GbmContextMenuGroupSpec _historyCommitFile = GbmContextMenuGroupSpec(
  id: '05-K',
  target: GbmContextMenuTarget.historyCommitFile,
  title: 'Commit file',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'View diff in this commit'),
    GbmContextMenuItemSpec(label: 'Compare with working copy'),
    GbmContextMenuItemSpec(label: 'Open file at this revision'),
    GbmContextMenuItemSpec(label: 'File history'),
    GbmContextMenuItemSpec(label: 'Blame at this commit'),
    GbmContextMenuItemSpec(label: 'Open terminal here'),
    GbmContextMenuItemSpec(label: 'Copy path'),
    GbmContextMenuItemSpec(
      label: 'More actions',
      isSubmenuTrigger: true,
      children: <GbmContextMenuItemSpec>[
        GbmContextMenuItemSpec(label: 'Restore file to this state'),
        GbmContextMenuItemSpec(label: 'Restore and stage'),
        GbmContextMenuItemSpec(label: 'Save this revision as…'),
        GbmContextMenuItemSpec(label: 'Export as patch…'),
      ],
    ),
  ],
);

/// 05-G: Diff line / line selection (right-click inside diff pane -- not yet wired)
/// 5 top-level items. First item's label becomes "Stage N lines" when multiple
/// lines are drag-selected (not yet implemented; use singular form for now).
const GbmContextMenuGroupSpec _diffLine = GbmContextMenuGroupSpec(
  id: '05-G',
  target: GbmContextMenuTarget.diffLine,
  title: 'Diff line',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'Stage'),
    GbmContextMenuItemSpec(label: 'Stage hunk'),
    GbmContextMenuItemSpec(label: 'Unstage hunk'),
    GbmContextMenuItemSpec(label: 'Copy lines'),
    GbmContextMenuItemSpec(label: 'Discard', isDanger: true),
  ],
);

/// 05-H: Stash entry (right-click stash row in sidebar -- not yet wired)
/// 6 top-level items.
const GbmContextMenuGroupSpec _stashEntry = GbmContextMenuGroupSpec(
  id: '05-H',
  target: GbmContextMenuTarget.stashEntry,
  title: 'Stash entry',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'Apply stash'),
    GbmContextMenuItemSpec(label: 'Pop stash'),
    GbmContextMenuItemSpec(label: 'Create branch from stash…'),
    GbmContextMenuItemSpec(label: 'View diff'),
    GbmContextMenuItemSpec(label: 'Compare with…'),
    GbmContextMenuItemSpec(label: 'Drop stash…', isDanger: true),
  ],
);

/// 05-I: Conflict hunk (right-click inside conflict-resolution window -- not yet wired)
/// 5 top-level items.
const GbmContextMenuGroupSpec _conflictHunk = GbmContextMenuGroupSpec(
  id: '05-I',
  target: GbmContextMenuTarget.conflictHunk,
  title: 'Conflict hunk',
  items: <GbmContextMenuItemSpec>[
    GbmContextMenuItemSpec(label: 'Take this side'),
    GbmContextMenuItemSpec(label: 'Take this line only'),
    GbmContextMenuItemSpec(label: 'Take both — this side first'),
    GbmContextMenuItemSpec(label: 'Open in external merge tool'),
    GbmContextMenuItemSpec(label: 'Discard from result', isDanger: true),
  ],
);

// ============================================================================
// Master Map: All 11 Groups
// ============================================================================

/// Complete map of all context menu groups, keyed by [GbmContextMenuTarget].
const Map<GbmContextMenuTarget, GbmContextMenuGroupSpec> gbmContextMenuGroups =
    <GbmContextMenuTarget, GbmContextMenuGroupSpec>{
      GbmContextMenuTarget.repository: _repo,
      GbmContextMenuTarget.localBranch: _localBranch,
      GbmContextMenuTarget.remoteOnlyOrGoneBranch: _remoteOnlyOrGoneBranch,
      GbmContextMenuTarget.branchFolder: _branchFolder,
      GbmContextMenuTarget.tag: _tag,
      GbmContextMenuTarget.commit: _commit,
      GbmContextMenuTarget.workingCopyFile: _workingCopyFile,
      GbmContextMenuTarget.historyCommitFile: _historyCommitFile,
      GbmContextMenuTarget.diffLine: _diffLine,
      GbmContextMenuTarget.stashEntry: _stashEntry,
      GbmContextMenuTarget.conflictHunk: _conflictHunk,
    };
