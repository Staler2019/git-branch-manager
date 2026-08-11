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

  static String workspaceFor(String repoId) => historyFor(repoId);
  static String historyFor(String repoId) => '/repo/$repoId/history';
  static String workingCopyFor(String repoId) => '/repo/$repoId/working-copy';
  static String resetBranchDialogFor(String repoId) => '/repo/$repoId/dialogs/reset-branch';
}
