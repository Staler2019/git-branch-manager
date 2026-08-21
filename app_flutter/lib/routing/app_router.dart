import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/recents_repository.dart';
import '../data/repositories/repo_identity.dart';
import '../features/compare/compare_page.dart';
import '../features/panels/panel_page.dart';
import '../features/conflict_resolution/conflict_resolve_window.dart';
import '../features/dialogs/about/about_dialog.dart';
import '../features/dialogs/bisect/bisect_dialog.dart';
import '../features/dialogs/blame/blame_dialog.dart';
import '../features/dialogs/checkout/checkout_dialog.dart';
import '../features/dialogs/checkout_recovery/checkout_recovery_dialog.dart';
import '../features/dialogs/cherry_pick/cherry_pick_dialog.dart';
import '../features/dialogs/clean_untracked/clean_untracked_dialog.dart';
import '../features/dialogs/create_tag/create_tag_dialog.dart';
import '../features/dialogs/credential/credential_dialog.dart';
import '../features/dialogs/delete_branch/delete_branch_dialog.dart';
import '../features/dialogs/delete_branches/delete_branches_dialog.dart';
import '../features/dialogs/delete_branch_recovery/delete_branch_recovery_dialog.dart';
import '../features/dialogs/delete_remote_branch/delete_remote_branch_dialog.dart';
import '../features/dialogs/discard_changes/discard_changes_dialog.dart';
import '../features/dialogs/discard_changes/discard_changes_request.dart';
import '../features/dialogs/file_history/file_history_dialog.dart';
import '../features/dialogs/force_push/force_push_dialog.dart';
import '../features/dialogs/interactive_rebase/interactive_rebase_dialog.dart';
import '../features/dialogs/keyboard_shortcuts/keyboard_shortcuts_dialog.dart';
import '../features/dialogs/line_history/line_history_dialog.dart';
import '../features/dialogs/manage_base_folders/manage_base_folders_dialog.dart';
import '../features/dialogs/manage_lfs/manage_lfs_dialog.dart';
import '../features/dialogs/manage_remotes/manage_remotes_dialog.dart';
import '../features/dialogs/manage_submodules/manage_submodules_dialog.dart';
import '../features/dialogs/merge/merge_dialog.dart';
import '../features/dialogs/new_branch/new_branch_dialog.dart';
import '../features/dialogs/patches/patches_dialog.dart';
import '../features/dialogs/preferences/preferences_dialog.dart';
import '../features/dialogs/prune_remote_branches/prune_remote_branches_dialog.dart';
import '../features/dialogs/rebase_onto/rebase_onto_dialog.dart';
import '../features/dialogs/reflog/reflog_dialog.dart';
import '../features/dialogs/rename_branch/rename_branch_dialog.dart';
import '../features/dialogs/repository_settings/repository_settings_dialog.dart';
import '../features/dialogs/reset_branch/reset_branch_dialog.dart';
import '../features/dialogs/restore_file/restore_file_dialog.dart';
import '../features/dialogs/stash_changes/stash_changes_dialog.dart';
import '../features/dialogs/undo_last/undo_last_dialog.dart';
import '../features/history_graph/history_page.dart';
import '../features/welcome/welcome_screen.dart';
import '../features/working_copy/working_copy_view.dart';
import '../features/workspace/workspace_screen.dart';
import 'dialog_route.dart';
import 'route_paths.dart';

/// `repoId` in the route is the URL-encoded working-directory path -- simple
/// and sufficient while a "repository" is identified by nothing more than
/// its work tree (see [RepoIdentity]); a real opaque id (matching
/// `RepoRecord.id` from the discovery database) could replace this, at the
/// cost of a lookup for repositories opened by path that discovery has
/// never scanned.
String repoIdFor(String workDir) => Uri.encodeComponent(workDir);

RepoIdentity repoIdentityFromRouteParam(String repoId) =>
    RepoIdentity.forWorkDir(Uri.decodeComponent(repoId));

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
///
/// The app's default page is a repository workspace, not a list of
/// repositories: the spec's window *is* a repository (pages 01-03), with
/// switching handled by the sidebar's popover rather than by navigating to a
/// dashboard. [initialLocation] is therefore computed once here (cold start
/// only) from [RecentsRepository] -- the most recently opened repository --
/// and [RoutePaths.welcome] is only reached when there is none to open, or
/// via File → Close window.
///
/// This is deliberately NOT a `redirect` on [RoutePaths.welcome]: a redirect
/// would re-fire on every navigation back to `/`, permanently breaking the
/// way out of a workspace the moment any repo has been opened once.
/// `initialLocation` only applies at [GoRouter] construction, so `/`
/// continues to mean the welcome screen for every explicit
/// `context.go(RoutePaths.welcome)` afterward.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final List<RecentRepoEntry> recents = ref
      .read(recentsRepositoryProvider)
      .read();
  final String initialLocation = recents.isEmpty
      ? RoutePaths.welcome
      : RoutePaths.workspaceFor(repoIdFor(recents.first.workDir));
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
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
          return WorkspaceScreen(
            identity: repoIdentityFromRouteParam(repoId),
            child: child,
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: RoutePaths.history,
            builder: (context, state) {
              final RepoIdentity identity = repoIdentityFromRouteParam(
                state.pathParameters['repoId']!,
              );
              return HistoryPage(identity: identity);
            },
          ),
          GoRoute(
            path: RoutePaths.workingCopy,
            builder: (context, state) {
              final RepoIdentity identity = repoIdentityFromRouteParam(
                state.pathParameters['repoId']!,
              );
              return WorkingCopyView(identity: identity);
            },
          ),
          GoRoute(
            path: RoutePaths.compare,
            builder: (context, state) {
              final RepoIdentity identity = repoIdentityFromRouteParam(
                state.pathParameters['repoId']!,
              );
              return ComparePage(
                identity: identity,
                tabId: state.pathParameters['tabId']!,
              );
            },
          ),
          GoRoute(
            path: RoutePaths.panel,
            builder: (context, state) {
              final RepoIdentity identity = repoIdentityFromRouteParam(
                state.pathParameters['repoId']!,
              );
              return PanelPage(
                identity: identity,
                tabId: state.pathParameters['tabId']!,
                query: state.uri.queryParameters,
              );
            },
          ),
        ],
      ),
      dialogRoute(
        path: RoutePaths.aboutDialog,
        builder: (context, state) => const AboutDialogContent(),
      ),
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
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          final String target = state.uri.queryParameters['target'] ?? '';
          return ResetBranchDialogContent(
            identity: identity,
            target: target.isEmpty ? null : target,
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.mergeDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return MergeDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.cherryPickDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return CherryPickDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.stashChangesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return StashChangesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.manageRemotesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return ManageRemotesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.createTagDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return CreateTagDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.credentialDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return CredentialDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.blameDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return BlameDialogContent(
            identity: identity,
            initialPath: state.uri.queryParameters['path'] ?? '',
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.fileHistoryDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return FileHistoryDialogContent(
            identity: identity,
            initialPath: state.uri.queryParameters['path'] ?? '',
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.lineHistoryDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return LineHistoryDialogContent(
            identity: identity,
            initialPath: state.uri.queryParameters['path'] ?? '',
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.reflogDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return ReflogDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.undoLastDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return UndoLastDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.interactiveRebaseDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return InteractiveRebaseDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.manageSubmodulesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return ManageSubmodulesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.bisectDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return BisectDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.manageLfsDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return ManageLfsDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.patchesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return PatchesDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.cleanUntrackedDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return CleanUntrackedDialogContent(identity: identity);
        },
      ),
      // App-level: no `:repoId` to resolve. See RoutePaths.preferencesDialog.
      dialogRoute(
        path: RoutePaths.preferencesDialog,
        builder: (context, state) => const PreferencesDialogContent(),
      ),
      dialogRoute(
        path: RoutePaths.repositorySettingsDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return RepositorySettingsDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.newBranchDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          final String startPoint =
              state.uri.queryParameters['startPoint'] ?? '';
          return NewBranchDialogContent(
            identity: identity,
            initialStartPoint: startPoint.isEmpty ? null : startPoint,
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.checkoutDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return CheckoutDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.deleteBranchDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          final String branch = state.uri.queryParameters['branch'] ?? '';
          return DeleteBranchDialogContent(
            identity: identity,
            branchName: branch.isEmpty ? null : branch,
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.renameBranchDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          final String branch = state.uri.queryParameters['branch'] ?? '';
          return RenameBranchDialogContent(
            identity: identity,
            branchName: branch.isEmpty ? null : branch,
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.rebaseOntoDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          final String target = state.uri.queryParameters['target'] ?? '';
          return RebaseOntoDialogContent(
            identity: identity,
            target: target.isEmpty ? null : target,
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.forcePushDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return ForcePushDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.deleteBranchesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          final String names = state.uri.queryParameters['names'] ?? '';
          return DeleteBranchesDialogContent(
            identity: identity,
            names: names.isEmpty ? const <String>[] : names.split(','),
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.deleteRemoteBranchDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return DeleteRemoteBranchDialogContent(
            identity: identity,
            remote: state.uri.queryParameters['remote'] ?? '',
            branch: state.uri.queryParameters['branch'] ?? '',
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.restoreFileDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return RestoreFileDialogContent(
            identity: identity,
            path: state.uri.queryParameters['path'] ?? '',
            oid: state.uri.queryParameters['oid'] ?? '',
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.discardChangesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          // Whole-file (05-F) vs line-level (05-G) discard, and the refusal
          // of anything in between, all live in the request factory --
          // see discard_changes_request.dart for why a half-parsed line
          // selection must not degrade into a whole-file one here.
          return DiscardChangesDialogContent(
            identity: identity,
            request: DiscardChangesRequest.fromQuery(
              state.uri.queryParametersAll,
            ),
          );
        },
      ),
      dialogRoute(
        path: RoutePaths.checkoutRecoveryDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return CheckoutRecoveryDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.deleteBranchRecoveryDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return DeleteBranchRecoveryDialogContent(identity: identity);
        },
      ),
      dialogRoute(
        path: RoutePaths.pruneRemoteBranchesDialog,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return PruneRemoteBranchesDialogContent(identity: identity);
        },
      ),
      GoRoute(
        path: RoutePaths.conflicts,
        builder: (context, state) {
          final RepoIdentity identity = repoIdentityFromRouteParam(
            state.pathParameters['repoId']!,
          );
          return ConflictResolveWindow(identity: identity);
        },
      ),
    ],
  );
});
