import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/repo_identity.dart';
import '../features/conflict_resolution/conflict_resolve_window.dart';
import '../features/dialogs/about/about_dialog.dart';
import '../features/dialogs/bisect/bisect_dialog.dart';
import '../features/dialogs/blame/blame_dialog.dart';
import '../features/dialogs/checkout_recovery/checkout_recovery_dialog.dart';
import '../features/dialogs/cherry_pick/cherry_pick_dialog.dart';
import '../features/dialogs/clean_untracked/clean_untracked_dialog.dart';
import '../features/dialogs/create_tag/create_tag_dialog.dart';
import '../features/dialogs/credential/credential_dialog.dart';
import '../features/dialogs/delete_branch_recovery/delete_branch_recovery_dialog.dart';
import '../features/dialogs/file_history/file_history_dialog.dart';
import '../features/dialogs/interactive_rebase/interactive_rebase_dialog.dart';
import '../features/dialogs/keyboard_shortcuts/keyboard_shortcuts_dialog.dart';
import '../features/dialogs/line_history/line_history_dialog.dart';
import '../features/dialogs/manage_base_folders/manage_base_folders_dialog.dart';
import '../features/dialogs/manage_lfs/manage_lfs_dialog.dart';
import '../features/dialogs/manage_remotes/manage_remotes_dialog.dart';
import '../features/dialogs/manage_stashes/manage_stashes_dialog.dart';
import '../features/dialogs/manage_submodules/manage_submodules_dialog.dart';
import '../features/dialogs/manage_worktrees/manage_worktrees_dialog.dart';
import '../features/dialogs/merge/merge_dialog.dart';
import '../features/dialogs/patches/patches_dialog.dart';
import '../features/dialogs/preferences/preferences_dialog.dart';
import '../features/dialogs/reflog/reflog_dialog.dart';
import '../features/dialogs/reset_branch/reset_branch_dialog.dart';
import '../features/dialogs/stash_changes/stash_changes_dialog.dart';
import '../features/dialogs/undo_last/undo_last_dialog.dart';
import '../features/history_graph/commit_graph_view.dart';
import '../features/operation_log/operation_log_dialog.dart';
import '../features/repo_list/repo_list_screen.dart';
import '../features/working_copy/working_copy_view.dart';
import '../features/workspace/workspace_screen.dart';
import 'dialog_route.dart';
import 'route_paths.dart';

/// `repoId` in the route is the URL-encoded working-directory path -- simple
/// and sufficient while a "repository" is identified by nothing more than
/// its work tree (see [RepoIdentity]); a real opaque id (matching
/// `RepoRecord.id` from the discovery database) can replace this once
/// `features/repo_list` reads from `discoveryProvider` instead of manual
/// entry (M1's known limitation, see repo_list_screen.dart).
String repoIdFor(String workDir) => Uri.encodeComponent(workDir);

RepoIdentity repoIdentityFromRouteParam(String repoId) => RepoIdentity.forWorkDir(Uri.decodeComponent(repoId));

/// `/`, `/repo/:repoId/history`, `/repo/:repoId/working-copy`, plus the
/// first four dialog routes (M3: about, keyboard shortcuts, manage base
/// folders, reset branch) -- see the plan's routing-table section for the
/// full design (`/repo/:repoId/diff/:commitId`, `/repo/:repoId/conflicts`,
/// and the ~26 remaining `/dialogs/<name>` routes), added milestone by
/// milestone as the screens behind them are implemented.
///
/// Dialog routes are top-level (not ShellRoute children): they're pushed
/// with `context.push()` on top of whatever screen is showing, rendered as
/// a non-opaque overlay page (see dialog_route.dart), and popped back to it
/// -- unlike history/working-copy, which replace the shell's main pane.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: RoutePaths.repoList,
    routes: <RouteBase>[
      GoRoute(path: RoutePaths.repoList, builder: (context, state) => const RepoListScreen()),
      GoRoute(
        path: RoutePaths.workspace,
        redirect: (context, state) {
          final String repoId = state.pathParameters['repoId']!;
          return RoutePaths.historyFor(repoId);
        },
      ),
      ShellRoute(
        builder: (context, state, child) {
          final String repoId = state.pathParameters['repoId']!;
          return WorkspaceScreen(identity: repoIdentityFromRouteParam(repoId), child: child);
        },
        routes: <RouteBase>[
          GoRoute(
            path: RoutePaths.history,
            builder: (context, state) {
              final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
              return CommitGraphView(identity: identity);
            },
          ),
          GoRoute(
            path: RoutePaths.workingCopy,
            builder: (context, state) {
              final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
              return WorkingCopyView(identity: identity);
            },
          ),
        ],
      ),
      dialogRoute(path: RoutePaths.aboutDialog, builder: (context, state) => const AboutDialogContent()),
      dialogRoute(
        path: RoutePaths.keyboardShortcutsDialog,
        builder: (context, state) => const KeyboardShortcutsDialogContent(),
      ),
      dialogRoute(
        path: RoutePaths.manageBaseFoldersDialog,
        builder: (context, state) => const ManageBaseFoldersDialogContent(),
      ),
      dialogRoute(
        path: RoutePaths.resetBranchDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return ResetBranchDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.mergeDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return MergeDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.cherryPickDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return CherryPickDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.stashChangesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return StashChangesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.manageStashesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return ManageStashesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.manageWorktreesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return ManageWorktreesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.manageRemotesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return ManageRemotesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.createTagDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return CreateTagDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.credentialDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return CredentialDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.operationLogDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return OperationLogDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.blameDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return BlameDialogContent(identity: identity, initialPath: state.uri.queryParameters['path'] ?? '');
        },
      ),
      dialogRoute(
        path: RoutePaths.fileHistoryDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return FileHistoryDialogContent(identity: identity, initialPath: state.uri.queryParameters['path'] ?? '');
        },
      ),
      dialogRoute(
        path: RoutePaths.lineHistoryDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return LineHistoryDialogContent(identity: identity, initialPath: state.uri.queryParameters['path'] ?? '');
        },
      ),
      dialogRoute(
        path: RoutePaths.reflogDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return ReflogDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.undoLastDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return UndoLastDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.interactiveRebaseDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return InteractiveRebaseDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.manageSubmodulesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return ManageSubmodulesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.bisectDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return BisectDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.manageLfsDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return ManageLfsDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.patchesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return PatchesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.cleanUntrackedDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return CleanUntrackedDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.preferencesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return PreferencesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.checkoutRecoveryDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return CheckoutRecoveryDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.deleteBranchRecoveryDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return DeleteBranchRecoveryDialogContent(identity: identity);
        },
      ),
      GoRoute(
        path: RoutePaths.conflicts,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(state.pathParameters['repoId']!);
          return ConflictResolveWindow(identity: identity);
        },
      ),
    ],
  );
});
