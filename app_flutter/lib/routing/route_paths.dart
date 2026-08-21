/// Typed route path/name constants -- see app_router.dart for the actual
/// GoRouter route table this backs, and the plan's routing-table section for
/// the full design (including routes not yet implemented: diff, conflicts,
/// the ~26 remaining dialogs).
abstract final class RoutePaths {
  /// Shown only when no repository is open -- the app's window is a
  /// repository workspace (spec pages 01-03), so this is a fallback, not a
  /// dashboard. Picking a repository is the switcher popover's job
  /// (`repo_switcher_popover.dart`), and managing where repositories are
  /// discovered from is Preferences → Repository sources'.
  static const String welcome = '/';
  static const String workspace = '/repo/:repoId';
  static const String history = '/repo/:repoId/history';
  static const String workingCopy = '/repo/:repoId/working-copy';

  /// Not repo-scoped: about/keyboard-shortcuts/manage-base-folders apply
  /// app-wide (discovery isn't tied to any one open repository -- see
  /// gbm_capi.h's Discovery section).
  static const String aboutDialog = '/dialogs/about';
  static const String keyboardShortcutsDialog = '/dialogs/keyboard-shortcuts';
  static const String manageBaseFoldersDialog = '/dialogs/manage-base-folders';

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
  static const String createTagDialog = '/repo/:repoId/dialogs/create-tag';
  static const String credentialDialog = '/repo/:repoId/dialogs/credential';
  static const String blameDialog = '/repo/:repoId/dialogs/blame';
  static const String fileHistoryDialog = '/repo/:repoId/dialogs/file-history';
  static const String lineHistoryDialog = '/repo/:repoId/dialogs/line-history';
  static const String undoLastDialog = '/repo/:repoId/dialogs/undo-last';
  static const String interactiveRebaseDialog =
      '/repo/:repoId/dialogs/interactive-rebase';
  static const String bisectDialog = '/repo/:repoId/dialogs/bisect';
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
  static const String renameBranchDialog =
      '/repo/:repoId/dialogs/rename-branch';
  static const String rebaseOntoDialog = '/repo/:repoId/dialogs/rebase-onto';
  static const String forcePushDialog = '/repo/:repoId/dialogs/force-push';

  /// Multi-branch delete confirmation (spec page 13). Separate from
  /// [deleteBranchDialog], which is 05-B's single-branch flow with its own
  /// branch picker.
  static const String deleteBranchesDialog =
      '/repo/:repoId/dialogs/delete-branches';
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

  /// One open `PanelTabSpec` (data/repositories/panel_tabs_repository.dart)
  /// -- the advanced management panels spec page 14's `IAMAP` routes to
  /// tabs rather than dialogs. A ShellRoute child, like [compare], so the
  /// menu bar / tab strip / sidebar stay mounted around it.
  static const String panel = '/repo/:repoId/panel/:tabId';

  static String workspaceFor(String repoId) => historyFor(repoId);
  static String historyFor(String repoId) => '/repo/$repoId/history';
  static String workingCopyFor(String repoId) => '/repo/$repoId/working-copy';

  /// [target] pre-fills the "Reset to" field -- 05-E's "Reset branch to
  /// here…" passes the right-clicked commit's oid. Same query-parameter
  /// shape as [renameBranchDialogFor]; empty means "no pre-fill", and the
  /// dialog keeps its own default (the current branch).
  static String resetBranchDialogFor(String repoId, {String target = ''}) =>
      Uri(
        path: '/repo/$repoId/dialogs/reset-branch',
        queryParameters: target.isEmpty
            ? null
            : <String, String>{'target': target},
      ).toString();

  static String mergeDialogFor(String repoId) => '/repo/$repoId/dialogs/merge';
  static String cherryPickDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/cherry-pick';
  static String stashChangesDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/stash-changes';

  static String createTagDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/create-tag';
  static String credentialDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/credential';
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
  static String undoLastDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/undo-last';
  static String interactiveRebaseDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/interactive-rebase';
  static String bisectDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/bisect';
  static String patchesDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/patches';
  static String cleanUntrackedDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/clean-untracked';
  static String checkoutRecoveryDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/checkout-recovery';
  static String deleteBranchRecoveryDialogFor(String repoId) =>
      '/repo/$repoId/dialogs/delete-branch-recovery';

  /// [remote] pre-selects which remote to preview -- the Remotes panel's
  /// `Prune` passes the selected row. Empty keeps the dialog's own default
  /// (the first configured remote).
  static String pruneRemoteBranchesDialogFor(
    String repoId, {
    String remote = '',
  }) => Uri(
    path: '/repo/$repoId/dialogs/prune-remote-branches',
    queryParameters: remote.isEmpty ? null : <String, String>{'remote': remote},
  ).toString();
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

  /// [branch] empty means "the current branch" -- the Branch menu and F2
  /// both leave it out; only the 05-B context menu names one.
  static String renameBranchDialogFor(String repoId, {String branch = ''}) =>
      Uri(
        path: '/repo/$repoId/dialogs/rename-branch',
        queryParameters: branch.isEmpty
            ? null
            : <String, String>{'branch': branch},
      ).toString();

  /// [names] is carried as one comma-separated `names` parameter; a branch
  /// name cannot contain a comma (git refuses it), so the split is safe.
  static String deleteBranchesDialogFor(
    String repoId, {
    required List<String> names,
  }) => Uri(
    path: '/repo/$repoId/dialogs/delete-branches',
    queryParameters: names.isEmpty
        ? null
        : <String, String>{'names': names.join(',')},
  ).toString();

  static String deleteBranchDialogFor(String repoId, {String branch = ''}) =>
      Uri(
        path: '/repo/$repoId/dialogs/delete-branch',
        queryParameters: branch.isEmpty
            ? null
            : <String, String>{'branch': branch},
      ).toString();

  /// [target] pre-selects what to rebase onto -- 05-B's "Rebase current
  /// onto here" passes a branch name, 05-E's "Rebase onto here" a commit
  /// oid. See [resetBranchDialogFor] for the shared shape.
  static String rebaseOntoDialogFor(String repoId, {String target = ''}) => Uri(
    path: '/repo/$repoId/dialogs/rebase-onto',
    queryParameters: target.isEmpty ? null : <String, String>{'target': target},
  ).toString();

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

  /// The line-level variant of [discardChangesDialogFor] (context menu
  /// 05-G's "Discard N lines…"): the same dialog, the same route, plus the
  /// one hunk and the line indices within it that `gbm_discard_lines` needs.
  /// `line` repeats for the same reason `path` does above.
  static String discardLinesDialogFor(
    String repoId, {
    required String path,
    required int hunkIndex,
    required List<int> lineIndices,
  }) => Uri(
    path: '/repo/$repoId/dialogs/discard-changes',
    queryParameters: <String, dynamic>{
      'path': <String>[path],
      'hunk': '$hunkIndex',
      'line': <String>[for (final int index in lineIndices) '$index'],
    },
  ).toString();

  /// App-level; takes no repoId. Kept next to the repo-scoped helpers so the
  /// asymmetry with [repositorySettingsDialogFor] is visible at the call site.
  static String preferencesDialogPath() => preferencesDialog;

  static String conflictsFor(String repoId) => '/repo/$repoId/conflicts';
  static String compareFor(String repoId, String tabId) =>
      '/repo/$repoId/compare/$tabId';

  /// [query] carries per-panel opening state (e.g. the stash a 05-H "View
  /// diff" should land on). It is *not* part of the tab's identity --
  /// `panelTabsProvider` keys on kind + subject -- so re-opening the same
  /// panel with a different query focuses the existing tab and hands it new
  /// state, rather than creating a second one.
  static String panelFor(
    String repoId,
    String tabId, {
    Map<String, String>? query,
  }) => Uri(
    path: '/repo/$repoId/panel/$tabId',
    queryParameters: (query == null || query.isEmpty) ? null : query,
  ).toString();
}
