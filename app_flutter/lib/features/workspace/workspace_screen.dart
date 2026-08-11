import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/history_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_banner.dart';
import '../sidebar/sidebar_panel.dart';
import 'widgets/top_bar.dart';

/// The repository shell: sidebar + top bar + tab switcher, with `child`
/// (History or Working Copy, see routing/app_router.dart's ShellRoute) as
/// the main pane. The Dart analog of `MainWindow` (src/app/views/
/// MainWindow.cpp). Owns the session's lifetime: opening any child route
/// lazily opens the `gbm_capi` session (see
/// data/repositories/repo_session_repository.dart), and Riverpod's
/// family provider is torn down (closing the session) once nothing is
/// watching it anymore, i.e. once every child route under this shell is
/// popped.
class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key, required this.identity, required this.child});

  final RepoIdentity identity;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RepoSessionState session = ref.watch(repoSessionProvider(identity));
    final String repoId = repoIdForRoute(identity);

    // Pushed automatically -- a credential prompt is not something the user
    // chose to open, unlike every other dialog route. See
    // CredentialDialogContent's doc comment for the reverse direction
    // (answering pops it back here without waiting for this to go null).
    ref.listen(repoSessionProvider(identity).select((state) => state.credentialPrompt), (previous, next) {
      if (next != null && previous == null) {
        context.push(RoutePaths.credentialDialogFor(repoId));
      }
    });

    if (!session.isOpen) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: () => context.go(RoutePaths.repoList))),
        body: Center(
          child: Text(session.lastError?.message ?? 'Opening repository…', style: TextStyle(color: context.gbmColors.textSecondary)),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: <Widget>[
          TopBar(
            repoName: _displayName(identity.workDir),
            repoState: session.repoState,
            isRefreshing: session.isRefreshing,
            onRefresh: () => refreshRepoHistory(ref, identity),
            onBack: () => context.go(RoutePaths.repoList),
          ),
          _TabRow(repoId: repoId),
          if (session.workingCopyStatus.conflicted.isNotEmpty)
            _ConflictBanner(repoId: repoId, count: session.workingCopyStatus.conflicted.length)
          else if (session.lastError case final error?)
            GbmWarningBanner(message: error.message),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SidebarPanel(identity: identity),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _displayName(String workDir) {
    final List<String> segments = workDir.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? workDir : segments.last;
  }
}

/// Resolves the `:repoId` route segment for `identity` -- the inverse of
/// `repoIdentityFromRouteParam` in routing/app_router.dart. Kept here
/// (rather than importing app_router.dart, which would create a routing ->
/// workspace -> routing import cycle) since it is a one-line pure function.
String repoIdForRoute(RepoIdentity identity) => Uri.encodeComponent(identity.workDir);

class _TabRow extends StatelessWidget {
  const _TabRow({required this.repoId});

  final String repoId;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String location = GoRouterState.of(context).uri.toString();
    final bool onWorkingCopy = location.endsWith('/working-copy');

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      decoration: BoxDecoration(color: colors.surfacePanel, border: Border(bottom: BorderSide(color: colors.borderSubtle))),
      child: Row(
        children: <Widget>[
          _Tab(label: 'History', active: !onWorkingCopy, onTap: () => context.go(RoutePaths.historyFor(repoId))),
          const SizedBox(width: GbmSpacing.space4),
          _Tab(label: 'Working Copy', active: onWorkingCopy, onTap: () => context.go(RoutePaths.workingCopyFor(repoId))),
          const Spacer(),
          TextButton(
            onPressed: () => context.push(RoutePaths.mergeDialogFor(repoId)),
            child: Text('Merge…', style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => context.push(RoutePaths.cherryPickDialogFor(repoId)),
            child: Text('Cherry-pick…', style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => context.push(RoutePaths.resetBranchDialogFor(repoId)),
            child: Text('Reset…', style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary)),
          ),
          _MoreMenu(repoId: repoId),
        ],
      ),
    );
  }
}

/// Groups the M5 stash/tag/worktree/remote/operation-log dialogs, which are
/// used less often than merge/cherry-pick/reset, behind one icon button --
/// keeps the tab row from growing a new inline TextButton per milestone.
class _MoreMenu extends StatelessWidget {
  const _MoreMenu({required this.repoId});

  final String repoId;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: Icon(Icons.more_horiz, size: 18, color: colors.textSecondary),
      onSelected: (route) => context.push(route),
      itemBuilder: (context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(value: RoutePaths.stashChangesDialogFor(repoId), child: const Text('Stash Changes…')),
        PopupMenuItem<String>(value: RoutePaths.manageStashesDialogFor(repoId), child: const Text('Manage Stashes…')),
        PopupMenuItem<String>(value: RoutePaths.createTagDialogFor(repoId), child: const Text('Create Tag…')),
        PopupMenuItem<String>(value: RoutePaths.manageWorktreesDialogFor(repoId), child: const Text('Manage Worktrees…')),
        PopupMenuItem<String>(value: RoutePaths.manageRemotesDialogFor(repoId), child: const Text('Remotes…')),
        PopupMenuItem<String>(value: RoutePaths.operationLogDialogFor(repoId), child: const Text('Operation Log…')),
        PopupMenuItem<String>(value: RoutePaths.blameDialogFor(repoId), child: const Text('Blame…')),
        PopupMenuItem<String>(value: RoutePaths.fileHistoryDialogFor(repoId), child: const Text('File History…')),
        PopupMenuItem<String>(value: RoutePaths.lineHistoryDialogFor(repoId), child: const Text('Line History…')),
        PopupMenuItem<String>(value: RoutePaths.reflogDialogFor(repoId), child: const Text('Reflog…')),
        PopupMenuItem<String>(value: RoutePaths.undoLastDialogFor(repoId), child: const Text('Undo Last Operation…')),
        PopupMenuItem<String>(value: RoutePaths.interactiveRebaseDialogFor(repoId), child: const Text('Interactive Rebase…')),
        PopupMenuItem<String>(value: RoutePaths.manageSubmodulesDialogFor(repoId), child: const Text('Submodules…')),
        PopupMenuItem<String>(value: RoutePaths.bisectDialogFor(repoId), child: const Text('Bisect…')),
        PopupMenuItem<String>(value: RoutePaths.manageLfsDialogFor(repoId), child: const Text('Git LFS…')),
        PopupMenuItem<String>(value: RoutePaths.patchesDialogFor(repoId), child: const Text('Patches…')),
        PopupMenuItem<String>(value: RoutePaths.cleanUntrackedDialogFor(repoId), child: const Text('Clean Untracked…')),
      ],
    );
  }
}

class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.repoId, required this.count});

  final String repoId;
  final int count;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space4, vertical: GbmSpacing.space2),
      decoration: BoxDecoration(color: colors.diffDelBg, border: Border(bottom: BorderSide(color: colors.borderSubtle))),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$count file${count == 1 ? '' : 's'} conflicted',
              style: TextStyle(fontSize: GbmTypography.textSm, color: colors.diffDelText),
            ),
          ),
          TextButton(
            onPressed: () => context.go(RoutePaths.conflictsFor(repoId)),
            child: Text('Resolve…', style: TextStyle(fontSize: GbmTypography.textSm, color: colors.diffDelText, fontWeight: GbmTypography.weightSemibold)),
          ),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? colors.accent : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            fontWeight: GbmTypography.weightMedium,
            color: active ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
