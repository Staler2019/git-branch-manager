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
  static const String repoSwitcherDialog = '/dialogs/switch-repository';

  /// App-level, not repo-scoped: spec page 11 is explicit that Preferences
  /// holds "應用層級設定" and that per-repository settings live behind
  /// Repository → Settings… instead ([repositorySettingsDialog]). It also
  /// has to open from the repo list, where there is no `:repoId` to scope to.
  static const String preferencesDialog = '/dialogs/preferences';

  /// Repo-scoped, per the plan's `/repo/:repoId/dialogs/<name>` design.
  static const String resetBranchDialog = '/repo/:repoId/dialogs/reset-branch';
  static const String mergeDialog = '/repo/:repoId/dialogs/merge';
  static const String cherryPickDialog = '/repo/:repoId/dialogs/cherry-pick';
  static const String stashChangesDialog =
      '/repo/:repoId/dialogs/stash-changes';
  static const String manageStashesDialog =
      '/repo/:repoId/dialogs/manage-stashes';
  static const String manageWorktreesDialog =
      '/repo/:repoId/dialogs/manage-worktrees';
  static const String manageRemotesDialog =
      '/repo/:repoId/dialogs/manage-remotes';
  static const String createTagDialog = '/repo/:repoId/dialogs/create-tag';
  static const String credentialDialog = '/repo/:repoId/dialogs/credential';
  static const String operationLogDialog =
      '/repo/:repoId/dialogs/operation-log';
  static const String blameDialog = '/repo/:repoId/dialogs/blame';
  static const String fileHistoryDialog = '/repo/:repoId/dialogs/file-history';
  static const String lineHistoryDialog = '/repo/:repoId/dialogs/line-history';
  static const String reflogDialog = '/repo/:repoId/dialogs/reflog';
  static const String undoLastDialog = '/repo/:repoId/dialogs/undo-last';
  static const String interactiveRebaseDialog =
      '/repo/:repoId/dialogs/interactive-rebase';
  static const String manageSubmodulesDialog =
      '/repo/:repoId/dialogs/manage-submodules';
  static const String bisectDialog = '/repo/:repoId/dialogs/bisect';
  static const String manageLfsDialog = '/repo/:repoId/dialogs/manage-lfs';
  static const String patchesDialog = '/repo/:repoId/dialogs/patches';
  static const String cleanUntrackedDialog =
      '/repo/:repoId/dialogs/clean-untracked';
  static const String checkoutRecoveryDialog =
      '/repo/:repoId/dialogs/checkout-recovery';
  static const String deleteBranchRecoveryDialog =
      '/repo/:repoId/dialogs/delete-branch-recovery';
  static const String pruneRemoteBranchesDialog =
      '/repo/:repoId/dialogs/prune-remote-branches';

  /// Spec page 06's remaining dialogs, added alongside the ones above.
  static const String repositorySettingsDialog =
      '/repo/:repoId/dialogs/repository-settings';
  static const String newBranchDialog = '/repo/:repoId/dialogs/new-branch';
  static const String checkoutDialog = '/repo/:repoId/dialogs/checkout';
  static const String deleteBranchDialog =
      '/repo/:repoId/dialogs/delete-branch';
  static const String rebaseOntoDialog = '/repo/:repoId/dialogs/rebase-onto';
  static const String forcePushDialog = '/repo/:repoId/dialogs/force-push';
  static const String deleteRemoteBranchDialog =
      '/repo/:repoId/dialogs/delete-remote-branch';
  static const String restoreFileDialog = '/repo/:repoId/dialogs/restore-file';
  static const String discardChangesDialog =
      '/repo/:repoId/dialogs/discard-changes';

  /// Standalone top-level route, not a `/dialogs/<name>` overlay -- see
  /// `features/conflict_resolution/conflict_resolve_window.dart`'s doc
  /// comment for why.
  static const String conflicts = '/repo/:repoId/conflicts';

  /// A ShellRoute child (main-pane content), like [history]/[workingCopy] --
  /// unlike [conflicts], a Compare tab is one of several tabs in the normal
  /// workspace tab strip, not a standalone window. `:tabId` selects which
  /// open `CompareTabSpec` (data/repositories/compare_tabs_repository.dart)
  /// to render; the ref pair/threeDot itself lives in that provider, not the
  /// URL.
  static const String compare = '/repo/:repoId/compare/:tabId';

  static String workspaceFor(String repoId) => historyFor(repoId);
  static String historyFor(String repoId) => '/repo/$repoId/history';
  static String workingCopyFor(String repoId) => '/repo/$repoId/working-copy';
  static String resetBranchDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/reset-branch';
  static String mergeDialogFor(String repoId) => '/repo/$repoId/dialogs/merge';
  static String cherryPickDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/cherry-pick';
  static String stashChangesDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/stash-changes';
  static String manageStashesDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/manage-stashes';
  static String manageWorktreesDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/manage-worktrees';
  static String manageRemotesDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/manage-remotes';
  static String createTagDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/create-tag';
  static String credentialDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/credential';
  static String operationLogDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/operation-log';
  static String blameDialogFor(String repoId, {String path = ''}) => Uri(
    path: '/repo/$repoId/dialogs/blame',
    queryParameters: path.isEmpty ? null : <String, String>{'path': path},
  ).toString();
  static String fileHistoryDialogFor(String repoId, {String path = ''}) => Uri(
    path: '/repo/$repoId/dialogs/file-history',
    queryParameters: path.isEmpty ? null : <String, String>{'path': path},
  ).toString();
  static String lineHistoryDialogFor(String repoId, {String path = ''}) => Uri(
    path: '/repo/$repoId/dialogs/line-history',
    queryParameters: path.isEmpty ? null : <String, String>{'path': path},
  ).toString();
  static String reflogDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/reflog';
  static String undoLastDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/undo-last';
  static String interactiveRebaseDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/interactive-rebase';
  static String manageSubmodulesDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/manage-submodules';
  static String bisectDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/bisect';
  static String manageLfsDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/manage-lfs';
  static String patchesDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/patches';
  static String cleanUntrackedDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/clean-untracked';
  static String checkoutRecoveryDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/checkout-recovery';
  static String deleteBranchRecoveryDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/delete-branch-recovery';
  static String pruneRemoteBranchesDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/prune-remote-branches';
  static String repositorySettingsDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/repository-settings';
  static String newBranchDialogFor(String repoId, {String startPoint = ''}) =>
      Uri(
        path: '/repo/$repoId/dialogs/new-branch',
        queryParameters: startPoint.isEmpty
            ? null
            : <String, String>{'startPoint': startPoint},
      ).toString();
  static String checkoutDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/checkout';
  static String deleteBranchDialogFor(String repoId, {String branch = ''}) =>
      Uri(
        path: '/repo/$repoId/dialogs/delete-branch',
        queryParameters: branch.isEmpty
            ? null
            : <String, String>{'branch': branch},
      ).toString();
  static String rebaseOntoDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/rebase-onto';
  static String forcePushDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/force-push';
  static String deleteRemoteBranchDialogFor(
    String repoId, {
    required String remote,
    required String branch,
  }) => Uri(
    path: '/repo/$repoId/dialogs/delete-remote-branch',
    queryParameters: <String, String>{'remote': remote, 'branch': branch},
  ).toString();
  static String restoreFileDialogFor(
    String repoId, {
    required String path,
    required String oid,
  }) => Uri(
    path: '/repo/$repoId/dialogs/restore-file',
    queryParameters: <String, String>{'path': path, 'oid': oid},
  ).toString();

  /// `path` repeats once per selected file, so a multi-file discard
  /// round-trips through the URL without inventing a delimiter that a real
  /// path could contain.
  static String discardChangesDialogFor(
    String repoId, {
    required List<String> paths,
  }) => Uri(
    path: '/repo/$repoId/dialogs/discard-changes',
    queryParameters: <String, List<String>>{'path': paths},
  ).toString();

  /// App-level; takes no repoId. Kept next to the repo-scoped helpers so the
  /// asymmetry with [repositorySettingsDialogFor] is visible at the call site.
  static String preferencesDialogPath() => preferencesDialog;

  static String conflictsFor(String repoId) => '/repo/$repoId/conflicts';
  static String compareFor(String repoId, String tabId) =>
      '/repo/$repoId/compare/$tabId';
}
