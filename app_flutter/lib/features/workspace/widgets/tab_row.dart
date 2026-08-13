import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';

/// The History/Working Copy tab switcher plus the always-visible
/// Merge/Cherry-pick/Reset shortcuts. Presentational (no Riverpod/FFI
/// dependency, same split as MenuBarRow -- see its doc comment): active tab
/// comes from the current GoRouter location, and [pendingChangeCount] is
/// handed in rather than read from the session, so a caller test can drive
/// every state without a real repo session.
///
/// The badge on Working Copy exists so a user browsing History has a
/// standing signal that changes are waiting -- without it that state is
/// only visible after switching tabs, which is exactly the kind of hidden
/// material state a frequent user shouldn't have to check for by hand.
class TabRow extends StatelessWidget {
  const TabRow({
    super.key,
    required this.repoId,
    required this.pendingChangeCount,
  });

  final String repoId;
  final int pendingChangeCount;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String location = GoRouterState.of(context).uri.toString();
    final bool onWorkingCopy = location.endsWith('/working-copy');

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          _Tab(
            label: 'History',
            active: !onWorkingCopy,
            onTap: () => context.go(RoutePaths.historyFor(repoId)),
          ),
          const SizedBox(width: GbmSpacing.space4),
          _Tab(
            label: 'Working Copy',
            active: onWorkingCopy,
            badgeCount: pendingChangeCount,
            onTap: () => context.go(RoutePaths.workingCopyFor(repoId)),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => context.push(RoutePaths.mergeDialogFor(repoId)),
            child: Text(
              'Merge…',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                context.push(RoutePaths.cherryPickDialogFor(repoId)),
            child: Text(
              'Cherry-pick…',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                context.push(RoutePaths.resetBranchDialogFor(repoId)),
            child: Text(
              'Reset…',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
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
        PopupMenuItem<String>(
          value: RoutePaths.stashChangesDialogFor(repoId),
          child: const Text('Stash Changes…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.manageStashesDialogFor(repoId),
          child: const Text('Manage Stashes…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.createTagDialogFor(repoId),
          child: const Text('Create Tag…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.manageWorktreesDialogFor(repoId),
          child: const Text('Manage Worktrees…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.manageRemotesDialogFor(repoId),
          child: const Text('Remotes…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.operationLogDialogFor(repoId),
          child: const Text('Operation Log…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.blameDialogFor(repoId),
          child: const Text('Blame…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.fileHistoryDialogFor(repoId),
          child: const Text('File History…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.lineHistoryDialogFor(repoId),
          child: const Text('Line History…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.reflogDialogFor(repoId),
          child: const Text('Reflog…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.undoLastDialogFor(repoId),
          child: const Text('Undo Last Operation…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.interactiveRebaseDialogFor(repoId),
          child: const Text('Interactive Rebase…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.manageSubmodulesDialogFor(repoId),
          child: const Text('Submodules…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.bisectDialogFor(repoId),
          child: const Text('Bisect…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.manageLfsDialogFor(repoId),
          child: const Text('Git LFS…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.patchesDialogFor(repoId),
          child: const Text('Patches…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.cleanUntrackedDialogFor(repoId),
          child: const Text('Clean Untracked…'),
        ),
        PopupMenuItem<String>(
          value: RoutePaths.preferencesDialogFor(repoId),
          child: const Text('Preferences…'),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.active,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: active ? colors.accent : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              label,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                fontWeight: GbmTypography.weightMedium,
                color: active ? colors.textPrimary : colors.textSecondary,
              ),
            ),
            if (badgeCount > 0) ...<Widget>[
              const SizedBox(width: GbmSpacing.space1),
              Container(
                key: const Key('tab-row-pending-badge'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.accentSubtle,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$badgeCount',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    fontWeight: GbmTypography.weightSemibold,
                    color: colors.accent,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
