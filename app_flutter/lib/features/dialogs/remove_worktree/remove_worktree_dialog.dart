import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/worktree_info.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_banner.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// D2's pending-count clause, or empty when nothing needs saying (a
/// freshly measured, clean worktree). Free rather than a private method so
/// it is testable without pumping the dialog -- the same shape
/// `deleteBranchRemoteTarget()` uses next door.
///
/// A `switch` over the full enum rather than a null check on
/// [WorktreeInfo.pendingChanges]: `unmeasured` and `failed` must not read
/// as clean, which is the whole reason [WorktreePendingCountState] is a
/// three-state field instead of a nullable int in the first place.
String worktreePendingCountWarning(WorktreeInfo worktree) {
  switch (worktree.pendingCountState) {
    case WorktreePendingCountState.measured:
      final int count = worktree.pendingChanges ?? 0;
      if (count == 0) return '';
      return '其中有 $count 個未提交的變更，它們不進 stash、也不在 reflog。';
    case WorktreePendingCountState.unmeasured:
    case WorktreePendingCountState.failed:
      // Not pretending an unanswered count is zero --
      // [GIT-worktree-status-is-per-path]'s reason for being a three-state
      // field instead of an int applies to its UI exactly as much as its
      // cache.
      return '未提交的變更數未知。';
    case WorktreePendingCountState.notApplicable:
      // Unreached in practice: the panel disables `Remove worktree…` for a
      // prunable worktree and routes it through `Prune` instead (D2's own
      // "notApplicable -> 路徑本來就不在，改走 Prune，這張不會開"). Written
      // out anyway rather than a `default` arm, so a future case added to
      // the enum is a compile error here instead of a silent fallthrough.
      return '';
  }
}

/// D2's locked-worktree clause. Empty when the worktree is not locked.
///
/// **Deliberately not "check the box twice and it forces through anyway."**
/// Measured on a real repository: `git worktree remove --force` on a
/// *locked* worktree fails identically to a plain `remove` -- git checks
/// the lock before it checks for uncommitted changes, and its own error
/// names the only two ways past it verbatim: `use 'remove -f -f' to
/// override or unlock first`. `gbm_worktree_remove()` can only ever send
/// one `--force` (`RemoveWorktreeRequest.force` is a bool, not a count), so
/// a checkbox or a second confirmation that claimed to force through a
/// lock would be dispatching a command guaranteed to fail with the same
/// error a second time -- a control that promises what it cannot do, the
/// same shape [REF-fetch-auto-prunes] records for the deleted
/// `autoFetchPrune` switch. `Unlock` already exists as a real,
/// undialogued action one click above this one in the panel, so that is
/// the path this dialog names instead.
String worktreeLockWarning(WorktreeInfo worktree) {
  if (!worktree.isLocked) return '';
  final String reason = worktree.lockReason.isEmpty
      ? '未填寫原因'
      : worktree.lockReason;
  return '這個 worktree 已鎖定（$reason）。git 移除已鎖定的 worktree 需要 '
      '「remove -f -f」，這裡不提供這個選項——請先按 Unlock 解鎖，再回來 '
      'Remove。';
}

/// Worktrees panel's `Remove worktree…` (D2). Previously the panel
/// dispatched `removeWorktree()` straight off a button press, with no
/// confirmation of any kind.
///
/// Routed as `/repo/:repoId/dialogs/remove-worktree` -- like
/// [AddWorktreeDialogContent], not one of the spec's 22 dialogs, since the
/// Worktrees panel itself postdates the spec's own page 06 dialog list
/// ([STRUCT-panels-are-tabs]).
class RemoveWorktreeDialogContent extends ConsumerStatefulWidget {
  const RemoveWorktreeDialogContent({
    super.key,
    required this.identity,
    required this.path,
  });

  final RepoIdentity identity;
  final String path;

  @override
  ConsumerState<RemoveWorktreeDialogContent> createState() =>
      _RemoveWorktreeDialogContentState();
}

class _RemoveWorktreeDialogContentState
    extends ConsumerState<RemoveWorktreeDialogContent> {
  /// D2: "有未提交變更時仍移除" only -- never promises anything about a
  /// lock (see [worktreeLockWarning]). Unticked by default, same reasoning
  /// as spec's Force push note: a destructive action defaults no option on
  /// for the user.
  bool _forceDirty = false;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );

    WorktreeInfo? worktree;
    for (final WorktreeInfo w in session.worktrees) {
      if (w.path == widget.path) worktree = w;
    }

    if (worktree == null) {
      return GbmDialogShell(
        title: 'Remove Worktree',
        actions: <Widget>[
          GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        ],
        child: Text(
          'This worktree is no longer in the list.',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textTertiary,
          ),
        ),
      );
    }

    final String name = worktree.path.split('/').last;
    final String pendingWarning = worktreePendingCountWarning(worktree);
    final String lockWarning = worktreeLockWarning(worktree);
    final bool canRemove = !worktree.isLocked;
    final String actualCommand =
        'git worktree remove ${worktree.path}${_forceDirty ? ' --force' : ''}';

    return GbmDialogShell(
      title: 'Remove Worktree',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Remove $name',
          kind: GbmButtonKind.danger,
          onPressed: canRemove
              ? () {
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .removeWorktree(worktree!.path, force: _forceDirty);
                  context.pop();
                }
              : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text.rich(
            TextSpan(
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
              children: <InlineSpan>[
                const TextSpan(text: 'Worktree  '),
                TextSpan(
                  text: '$name · ${worktree.path}',
                  style: const TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontWeight: GbmTypography.weightSemibold,
                  ),
                ),
              ],
            ),
          ),
          if (worktree.branch.isNotEmpty) ...<Widget>[
            const SizedBox(height: GbmSpacing.space1),
            Text(
              '分支  ${worktree.branch}（分支本身不會被刪）',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: GbmSpacing.space3),
          GbmWarningBanner(
            message: pendingWarning.isEmpty
                ? '這個資料夾會從磁碟移除，不進回收筒。'
                : '這個資料夾會從磁碟移除，不進回收筒。\n$pendingWarning',
          ),
          if (lockWarning.isNotEmpty) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            GbmWarningBanner(message: lockWarning),
          ],
          if (canRemove) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            CheckboxListTile(
              value: _forceDirty,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '強制移除（--force：有未提交變更時仍移除）',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              onChanged: (bool? value) =>
                  setState(() => _forceDirty = value ?? false),
            ),
          ],
          const SizedBox(height: GbmSpacing.space2),
          Text(
            '實際執行  $actualCommand',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              fontFamily: GbmTypography.fontMono,
              color: colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
