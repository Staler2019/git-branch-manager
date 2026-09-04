import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/worktree_info.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// Worktrees panel's `Lock…` (D3). `lockWorktree(path, {String reason = ''})`
/// has accepted a reason since it was written, and the detail pane already
/// draws a 「鎖定原因」 row for it (`worktrees_panel.dart`), but no call site
/// ever passed one -- a [CULT-orphan-wiring] instance the button's own
/// unconditional `_session.lockWorktree(selected.path)` call reproduced
/// exactly: always the default empty string.
///
/// `Unlock` deliberately gets no dialog of its own -- it destroys nothing
/// and needs no input, so the panel keeps dispatching it directly.
///
/// Routed as `/repo/:repoId/dialogs/lock-worktree` -- like
/// [AddWorktreeDialogContent] and `RemoveWorktreeDialogContent`, not one of
/// the spec's 22 dialogs, since the Worktrees panel itself postdates the
/// spec's own page 06 dialog list ([STRUCT-panels-are-tabs]).
class LockWorktreeDialogContent extends ConsumerStatefulWidget {
  const LockWorktreeDialogContent({
    super.key,
    required this.identity,
    required this.path,
  });

  final RepoIdentity identity;
  final String path;

  @override
  ConsumerState<LockWorktreeDialogContent> createState() =>
      _LockWorktreeDialogContentState();
}

class _LockWorktreeDialogContentState
    extends ConsumerState<LockWorktreeDialogContent> {
  final TextEditingController _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

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
        title: 'Lock Worktree',
        actions: <Widget>[
          GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        ],
        child: Text(
          '這個 worktree 已經不在清單裡了。',
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            color: colors.textTertiary,
          ),
        ),
      );
    }

    final String name = worktree.path.split('/').last;

    return GbmDialogShell(
      title: 'Lock Worktree',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Lock',
          onPressed: () {
            ref
                .read(repoSessionProvider(widget.identity).notifier)
                .lockWorktree(
                  worktree!.path,
                  reason: _reasonController.text.trim(),
                );
            context.pop();
          },
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
                const TextSpan(text: 'worktree  '),
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
          const SizedBox(height: GbmSpacing.space3),
          TextField(
            controller: _reasonController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '原因',
              hintText: '外接碟，平常不掛載',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          Text(
            '會顯示在明細的「鎖定原因」，git worktree list 也印。可留空。',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          // Not decoration -- [GIT-worktree-prune-has-no-expire]: `git
          // worktree prune` takes no `--expire`, so a lock is the only
          // thing standing between a temporarily-absent worktree and
          // deletion. A path-invalidated worktree is now pruned
          // automatically in the background ([REF-fetch-auto-prunes]'s
          // extension to worktrees), and a lock is the only thing that
          // stops it. The user should know what pressing Lock buys them.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(GbmSpacing.space2),
            decoration: BoxDecoration(
              color: colors.surfaceSunken,
              border: Border.all(color: colors.borderSubtle),
              borderRadius: BorderRadius.circular(GbmSpacing.radiusSm),
            ),
            child: Text(
              '鎖定唯一的作用是擋掉 prune。路徑失效的 worktree 現在是背景自動 '
              'prune 掉的，鎖定是唯一攔得住它的東西。',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
