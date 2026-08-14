/// Enum of all 52 menu action IDs in the app, as defined in the design spec page 04's MENUS table,
/// plus context-menu-only actions (e.g., diff line stage/unstage).
///
/// Grouped by menu for readability:
/// - File (8): new repo, open, clone, switch, add local, close window, preferences, exit
/// - Edit (8): undo, redo, cut, copy, paste, find-in-history, find-in-files, filter-branches
/// - View (11): history, working-copy, next-tab, file-list-as-tree, graph-columns, commit-detail,
///   toggle-sidebar, status-bar, log, reset-panel-sizes, theme
/// - Repository (10): fetch, pull, push, compare, commit, amend-last, stage-all, open-in-terminal, settings, stage-selected-lines
/// - Branch (7): new, checkout, rename-current, merge-into-current, rebase-onto, stash, delete
/// - Remote (4): add, fetch-all, prune, manage
/// - Help (4): documentation, keyboard-shortcuts, report-issue, about
enum GbmActionId {
  // File (8)
  fileNewRepository,
  fileOpenRepository,
  fileCloneRepository,
  fileSwitchRepository,
  fileAddLocalRepository,
  fileCloseWindow,
  filePreferences,
  fileExit,

  // Edit (8)
  editUndo,
  editRedo,
  editCut,
  editCopy,
  editPaste,
  editFindInHistory,
  editFindInFiles,
  editFilterBranches,

  // View (11)
  viewHistory,
  viewWorkingCopy,
  viewNextTab,
  viewFileListAsTree,
  viewGraphColumns,
  viewCommitDetail,
  viewToggleSidebar,
  viewStatusBar,
  viewLog,
  viewResetPanelSizes,
  viewTheme,

  // Repository (10)
  repositoryFetch,
  repositoryPull,
  repositoryPush,
  repositoryCompare,
  repositoryCommit,
  repositoryAmendLastCommit,
  repositoryStageAll,
  repositoryOpenInTerminal,
  repositorySettings,
  repositoryStageSelectedLines,

  // Branch (7)
  branchNewBranch,
  branchCheckout,
  branchRenameCurrentBranch,
  branchMergeIntoCurrent,
  branchRebaseOnto,
  branchStashChanges,
  branchDeleteBranch,

  // Remote (4)
  remoteAddRemote,
  remoteFetchAllRemotes,
  remotePruneRemoteBranches,
  remoteManageRemotes,

  // Help (4)
  helpDocumentation,
  helpKeyboardShortcuts,
  helpReportAnIssue,
  helpAbout,
}
