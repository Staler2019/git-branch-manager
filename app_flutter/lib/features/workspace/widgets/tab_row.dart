import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/compare_tabs_repository.dart';
import '../../../routing/route_paths.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_badge.dart';
import '../../../widgets/gbm_menu.dart';
import 'workspace_tab.dart';

/// Builds the [WorkspaceTab] a [CompareTabSpec] renders as in the tab strip
/// -- closable, unlike the two fixed tabs (see [WorkspaceTab.closable]'s
/// doc comment).
WorkspaceTab compareWorkspaceTab(CompareTabSpec spec, String repoId) {
  return WorkspaceTab(
    kind: WorkspaceTabKind.compare,
    label: '${spec.left} vs ${spec.right ?? 'Working Copy'}',
    route: RoutePaths.compareFor(repoId, spec.id),
    closable: true,
  );
}

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
    this.compareTabs = const <CompareTabSpec>[],
    this.onCloseCompareTab,
  });

  final String repoId;
  final int pendingChangeCount;

  /// Open Compare tabs (compare_tabs_repository.dart), rendered after the
  /// two fixed tabs -- empty by default so existing callers/tests that only
  /// care about History/Working Copy are unaffected.
  final List<CompareTabSpec> compareTabs;
  final ValueChanged<String>? onCloseCompareTab;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String location = GoRouterState.of(context).uri.toString();
    final List<WorkspaceTab> tabs = <WorkspaceTab>[
      ...defaultWorkspaceTabs(repoId, pendingChangeCount: pendingChangeCount),
      for (final CompareTabSpec spec in compareTabs)
        compareWorkspaceTab(spec, repoId),
    ];
    // Fixed tabs (History, Working Copy) have no backing spec -- only
    // entries from `compareTabs` do, in the same order they were appended
    // above, so this pads the front with two nulls to keep `tabs`/`tabIds`
    // index-aligned without re-deriving which tab is which from its route.
    final List<String?> tabIds = <String?>[
      null,
      null,
      for (final CompareTabSpec spec in compareTabs) spec.id,
    ];
    final int activeIndex = activeWorkspaceTabIndex(tabs, location);

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          // Scrollable, unlike the trailing action buttons below: dynamic
          // Compare tabs (each carrying a "left vs right" label) can push
          // the fixed row width past what History/Working Copy/Merge/
          // Cherry-pick/Reset/More alone ever needed, and those trailing
          // actions must stay reachable rather than get squeezed off-screen.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final (int index, WorkspaceTab tab)
                      in tabs.indexed) ...<Widget>[
                    if (index > 0) const SizedBox(width: GbmSpacing.space4),
                    _Tab(
                      label: tab.label,
                      active: index == activeIndex,
                      badgeCount: tab.badgeCount,
                      onTap: () => context.go(tab.route),
                      onClose: !tab.closable || onCloseCompareTab == null
                          ? null
                          : () => onCloseCompareTab!(tabIds[index]!),
                    ),
                  ],
                ],
              ),
            ),
          ),
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
    return Builder(
      builder: (buttonContext) => IconButton(
        tooltip: 'More',
        icon: Icon(Icons.more_horiz, size: 18, color: colors.textSecondary),
        onPressed: () => _open(buttonContext),
      ),
    );
  }

  /// Positions [showGbmMenu] below this button, mirroring
  /// `menu_bar_row.dart`'s `_MenuBarButton._open` -- this is a menu-bar-style
  /// menu anchored to a button, not a right-click context menu, so it goes
  /// through `showGbmMenu` directly rather than `showGbmContextMenu` (whose
  /// `validateGbmMenuItems` ≤8-item cap is scoped to spec page 05's 11
  /// right-click groups only, not this button's 18 dialog shortcuts).
  void _open(BuildContext buttonContext) {
    final RenderBox button = buttonContext.findRenderObject()! as RenderBox;
    final RenderBox overlay =
        Overlay.of(buttonContext).context.findRenderObject()! as RenderBox;
    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(Offset(0, button.size.height), ancestor: overlay),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );
    showGbmMenu(
      buttonContext,
      position: position,
      items: <GbmMenuItem>[
        GbmMenuItem(
          label: 'Stash Changes…',
          onTap: () =>
              buttonContext.push(RoutePaths.stashChangesDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Manage Stashes…',
          onTap: () =>
              buttonContext.push(RoutePaths.manageStashesDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Create Tag…',
          onTap: () =>
              buttonContext.push(RoutePaths.createTagDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Manage Worktrees…',
          onTap: () =>
              buttonContext.push(RoutePaths.manageWorktreesDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Remotes…',
          onTap: () =>
              buttonContext.push(RoutePaths.manageRemotesDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Operation Log…',
          onTap: () =>
              buttonContext.push(RoutePaths.operationLogDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Blame…',
          onTap: () => buttonContext.push(RoutePaths.blameDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'File History…',
          onTap: () =>
              buttonContext.push(RoutePaths.fileHistoryDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Line History…',
          onTap: () =>
              buttonContext.push(RoutePaths.lineHistoryDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Reflog…',
          onTap: () => buttonContext.push(RoutePaths.reflogDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Undo Last Operation…',
          onTap: () => buttonContext.push(RoutePaths.undoLastDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Interactive Rebase…',
          onTap: () =>
              buttonContext.push(RoutePaths.interactiveRebaseDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Submodules…',
          onTap: () =>
              buttonContext.push(RoutePaths.manageSubmodulesDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Bisect…',
          onTap: () => buttonContext.push(RoutePaths.bisectDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Git LFS…',
          onTap: () =>
              buttonContext.push(RoutePaths.manageLfsDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Patches…',
          onTap: () => buttonContext.push(RoutePaths.patchesDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Clean Untracked…',
          onTap: () =>
              buttonContext.push(RoutePaths.cleanUntrackedDialogFor(repoId)),
        ),
        GbmMenuItem(
          label: 'Preferences…',
          onTap: () =>
              buttonContext.push(RoutePaths.preferencesDialogFor(repoId)),
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
    this.onClose,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final int badgeCount;

  /// Non-null only for closable tabs (Compare) -- see [WorkspaceTab.closable].
  final VoidCallback? onClose;

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
              GbmBadge(
                key: const Key('tab-row-pending-badge'),
                label: '$badgeCount',
              ),
            ],
            if (onClose != null) ...<Widget>[
              const SizedBox(width: GbmSpacing.space1),
              InkWell(
                onTap: onClose,
                child: Icon(Icons.close, size: 14, color: colors.textTertiary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
