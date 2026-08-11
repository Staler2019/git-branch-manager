/// Typed route path/name constants -- see app_router.dart for the actual
/// GoRouter route table this backs, and the plan's routing-table section for
/// the full design (including routes not yet implemented: diff, conflicts,
/// the ~26 remaining dialogs).
abstract final class RoutePaths {
  static const String repoList = '/';
  static const String workspace = '/repo/:repoId';
  static const String history = '/repo/:repoId/history';
  static const String workingCopy = '/repo/:repoId/working-copy';

  /// Not repo-scoped: about/keyboard-shortcuts/manage-base-folders apply
  /// app-wide (discovery isn't tied to any one open repository -- see
  /// gbm_capi.h's Discovery section).
  static const String aboutDialog = '/dialogs/about';
  static const String keyboardShortcutsDialog = '/dialogs/keyboard-shortcuts';
  static const String manageBaseFoldersDialog = '/dialogs/manage-base-folders';

  /// Repo-scoped, per the plan's `/repo/:repoId/dialogs/<name>` design.
  static const String resetBranchDialog = '/repo/:repoId/dialogs/reset-branch';
  static const String mergeDialog = '/repo/:repoId/dialogs/merge';
  static const String cherryPickDialog = '/repo/:repoId/dialogs/cherry-pick';
  static const String stashChangesDialog = '/repo/:repoId/dialogs/stash-changes';
  static const String manageStashesDialog = '/repo/:repoId/dialogs/manage-stashes';
  static const String manageWorktreesDialog = '/repo/:repoId/dialogs/manage-worktrees';
  static const String manageRemotesDialog = '/repo/:repoId/dialogs/manage-remotes';
  static const String createTagDialog = '/repo/:repoId/dialogs/create-tag';
  static const String credentialDialog = '/repo/:repoId/dialogs/credential';
  static const String operationLogDialog = '/repo/:repoId/dialogs/operation-log';

  /// Standalone top-level route, not a `/dialogs/<name>` overlay -- see
  /// `features/conflict_resolution/conflict_resolve_window.dart`'s doc
  /// comment for why.
  static const String conflicts = '/repo/:repoId/conflicts';

  static String workspaceFor(String repoId) => historyFor(repoId);
  static String historyFor(String repoId) => '/repo/$repoId/history';
  static String workingCopyFor(String repoId) => '/repo/$repoId/working-copy';
  static String resetBranchDialogFor(String repoId) => '/repo/$repoId/dialogs/reset-branch';
  static String mergeDialogFor(String repoId) => '/repo/$repoId/dialogs/merge';
  static String cherryPickDialogFor(String repoId) => '/repo/$repoId/dialogs/cherry-pick';
  static String stashChangesDialogFor(String repoId) => '/repo/$repoId/dialogs/stash-changes';
  static String manageStashesDialogFor(String repoId) => '/repo/$repoId/dialogs/manage-stashes';
  static String manageWorktreesDialogFor(String repoId) => '/repo/$repoId/dialogs/manage-worktrees';
  static String manageRemotesDialogFor(String repoId) => '/repo/$repoId/dialogs/manage-remotes';
  static String createTagDialogFor(String repoId) => '/repo/$repoId/dialogs/create-tag';
  static String credentialDialogFor(String repoId) => '/repo/$repoId/dialogs/credential';
  static String operationLogDialogFor(String repoId) => '/repo/$repoId/dialogs/operation-log';
  static String conflictsFor(String repoId) => '/repo/$repoId/conflicts';
}
