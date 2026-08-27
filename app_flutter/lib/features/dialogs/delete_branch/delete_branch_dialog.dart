import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The remote [branch]'s upstream lives on: `refs/remotes/origin/feature/x`
/// -> `origin`. Empty when the branch tracks nothing, which is what hides the
/// "also delete on remote" checkbox.
///
/// Two traps, both of which this function used to fall into (#74):
///
/// 1. [RefInfo.upstream] is git's `%(upstream)` -- the **full** ref name, not
///    `%(upstream:short)`. Splitting it on the first slash yields the literal
///    string `refs`, and the dialog then dispatched
///    `git push refs --delete <branch>`. `remoteBranchParts()` is the one
///    place that knows how to take a full remote ref apart, and a remote
///    whose branch name itself contains slashes is why the naive split cannot
///    be repaired in place.
/// 2. [RefInfo.hasTrackingInfo] mirrors `%(upstream:track)`, which git leaves
///    **empty for a branch exactly in sync**. Using it to ask "does this
///    track a remote?" hid the checkbox on the commonest branch there is.
///    The question is answered by `upstream` alone.
///
/// Free rather than a private static so it can be tested without pumping the
/// dialog -- the same shape as `deleteBranchLines()` in the sibling
/// multi-branch dialog.
String deleteBranchRemoteName(RefInfo branch) {
  if (branch.upstream.isEmpty) return '';
  final (String remote, String _) = remoteBranchParts(branch.upstream);
  return remote;
}

/// Branch → Delete branch… and context menu 05-B's "Delete branch…".
///
/// Spec page 06: "複述分支名與未合併的 commit 數；可勾選一併刪遠端。主按鈕為
/// danger" -- the branch name is restated rather than assumed from context,
/// because this dialog can be reached from the menu bar where the "current"
/// branch is not visible next to the confirmation.
///
/// A delete git refuses because the branch is not fully merged comes back
/// through `deleteBranchChoices` and the delete-branch-recovery dialog,
/// which is where force-delete lives -- this dialog deliberately offers no
/// force checkbox of its own, so "delete" never silently means "force
/// delete".
///
/// Routed as `/repo/:repoId/dialogs/delete-branch`.
class DeleteBranchDialogContent extends ConsumerStatefulWidget {
  const DeleteBranchDialogContent({
    super.key,
    required this.identity,
    this.branchName,
  });

  final RepoIdentity identity;

  /// The branch to delete. When null (opened from Branch → Delete branch…
  /// with nothing selected) the dialog offers a picker over local branches.
  final String? branchName;

  @override
  ConsumerState<DeleteBranchDialogContent> createState() =>
      _DeleteBranchDialogContentState();
}

class _DeleteBranchDialogContentState
    extends ConsumerState<DeleteBranchDialogContent> {
  String? _selected;
  bool _alsoDeleteRemote = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.branchName;
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final String head = session.refs.head.branchName;

    // The current branch cannot be deleted -- git refuses, and offering it
    // would be an action that can only fail.
    final List<RefInfo> candidates = session.refs.localBranches
        .where((RefInfo b) => b.shortName != head)
        .toList(growable: false);

    RefInfo? target;
    for (final RefInfo b in candidates) {
      if (b.shortName == _selected) target = b;
    }

    final String remote = target == null ? '' : deleteBranchRemoteName(target);
    final bool canDelete = target != null;

    // One predicate, read by both the checkbox and the delete button.
    // Spelling it twice -- `_alsoDeleteRemote && !branch.isGone` on the box
    // and `_alsoDeleteRemote && remote.isNotEmpty` at the dispatch -- is the
    // second-source-of-truth shape: the two can only agree by accident, and
    // here they agreed only because the picker's onChanged happens to clear
    // the flag on every selection change. That reset is a separate mechanism
    // and the safety must not rest on it.
    final bool willDeleteRemote = switch (target) {
      RefInfo(:final bool isGone) =>
        _alsoDeleteRemote && remote.isNotEmpty && !isGone,
      null => false,
    };

    return GbmDialogShell(
      title: 'Delete Branch',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Delete branch',
          kind: GbmButtonKind.danger,
          onPressed: canDelete
              ? () {
                  final RepoSessionController notifier = ref.read(
                    repoSessionProvider(widget.identity).notifier,
                  );
                  notifier.deleteBranch(names: <String>[target!.shortName]);
                  if (willDeleteRemote) {
                    notifier.deleteBranch(
                      names: <String>[target.shortName],
                      isRemote: true,
                      remoteName: remote,
                    );
                  }
                  context.pop();
                }
              : null,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.branchName == null) ...<Widget>[
            DropdownButtonFormField<String>(
              initialValue: _selected,
              isExpanded: true,
              decoration: const InputDecoration(
                hintText: 'Branch to delete',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final RefInfo b in candidates)
                  DropdownMenuItem<String>(
                    value: b.shortName,
                    child: Text(b.shortName),
                  ),
              ],
              onChanged: (String? value) => setState(() {
                _selected = value;
                _alsoDeleteRemote = false;
              }),
            ),
            const SizedBox(height: GbmSpacing.space3),
          ],
          if (target case final RefInfo branch) ...<Widget>[
            Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
                children: <InlineSpan>[
                  const TextSpan(text: 'Delete the local branch '),
                  TextSpan(
                    text: branch.shortName,
                    style: const TextStyle(
                      fontFamily: GbmTypography.fontMono,
                      fontWeight: GbmTypography.weightSemibold,
                    ),
                  ),
                  const TextSpan(text: '?'),
                ],
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            // Ahead/behind is what the refs snapshot actually carries, so it
            // is reported as exactly that rather than dressed up as a
            // merge-base count this layer has not computed. Spec page 02
            // item 11's "永遠顯示實際數字" applies here too.
            if (branch.hasTrackingInfo)
              Text(
                branch.ahead > 0
                    ? '${branch.ahead} commit(s) on this branch are not yet on ${branch.upstream}.'
                    : 'Fully pushed to ${branch.upstream}.',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: branch.ahead > 0
                      ? colors.warning
                      : colors.textSecondary,
                ),
              )
            else
              Text(
                'This branch has no upstream — it exists only on this machine.',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.warning,
                ),
              ),
            const SizedBox(height: GbmSpacing.space1),
            Text(
              'If the branch is not fully merged, git will refuse and offer a '
              'force delete.',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
            if (remote.isNotEmpty) ...<Widget>[
              const SizedBox(height: GbmSpacing.space2),
              CheckboxListTile(
                // Disabled rather than hidden when the upstream has already
                // vanished: ticking it would push the branch back up and
                // then delete it again (#74's own closing note), and hiding
                // the row would read as "this branch has no remote", which
                // is a different and wrong statement. 隱藏會讓人以為功能不
                // 存在 -- the same rule GbmMenuItem.enabled follows.
                value: willDeleteRemote,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Also delete ${remoteBranchParts(branch.upstream).$2} '
                  'on $remote',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  branch.isGone
                      ? 'Already gone on $remote -- nothing left to delete.'
                      : 'Other people only see this after they fetch.',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
                onChanged: branch.isGone
                    ? null
                    : (bool? value) =>
                          setState(() => _alsoDeleteRemote = value ?? false),
              ),
            ],
          ] else
            Text(
              candidates.isEmpty
                  ? 'There is no other local branch to delete.'
                  : 'Choose a branch to delete.',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}
