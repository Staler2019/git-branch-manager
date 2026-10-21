import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../data/models/branch_deletion_probe.dart';
import '../../../data/models/git_error.dart';
import '../../../data/models/ref_snapshot.dart';
import '../../../data/models/remote_counterpart.dart';
import '../../../data/models/remote_prune_preview_entry.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../sidebar/gone_marking.dart';
import '../branch_deletion_probe_copy.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_field_kinds.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_input_decoration.dart';

/// The remote name and the branch name *as the remote knows it* for
/// [branch], or two empty strings when it has no remote side. Empty is what
/// hides the "also delete on remote" checkbox.
///
/// Four traps, all of which this resolution used to fall into:
///
/// 1. [RefInfo.upstream] is git's `%(upstream)` -- the **full** ref name, not
///    `%(upstream:short)`. Splitting it on the first slash yields the literal
///    string `refs`, and the dialog then dispatched
///    `git push refs --delete <branch>` (#74). `remoteBranchParts()` is the
///    one place that knows how to take a full remote ref apart, and a remote
///    whose branch name itself contains slashes is why the naive split cannot
///    be repaired in place.
/// 2. [RefInfo.hasTrackingInfo] mirrors `%(upstream:track)`, which git leaves
///    **empty for a branch exactly in sync**. Using it to ask "does this
///    track a remote?" hid the checkbox on the commonest branch there is.
/// 3. `upstream` alone does not answer "does this have a remote side"
///    either: `git push origin HEAD` leaves `branch.<name>.merge` empty while
///    putting the branch on the remote. That is the same premise that made
///    the sidebar draw two rows for one branch, so the answer comes from the
///    same place the sidebar's does -- [remoteCounterpartOf].
/// 4. The remote's name for the branch is not the local one. `feature/x` may
///    track `origin/renamed-x`, and a dispatch built from `shortName` then
///    deletes a different branch from the one the dialog named. Both the
///    label and the dispatch read this function's second field.
///
/// Free rather than a private static so it can be tested without pumping the
/// dialog -- the same shape as `deleteBranchLines()` in the sibling
/// multi-branch dialog.
(String remote, String branch) deleteBranchRemoteTarget(
  RefInfo branch,
  List<RefInfo> remoteBranches,
) {
  final String counterpart = remoteCounterpartOf(branch, remoteBranches);
  if (counterpart.isEmpty) return ('', '');
  return remoteBranchParts(counterpart);
}

/// Branch → Delete branch… and context menu 05-B's "Delete branch…".
///
/// Spec page 06: "複述分支名與未合併的 commit 數；可勾選一併刪遠端。主按鈕為
/// danger" -- the branch name is restated rather than assumed from context,
/// because this dialog can be reached from the menu bar where the "current"
/// branch is not visible next to the confirmation.
///
/// The warning comes before the confirmation, and the confirmation is final
/// (issue 5, ruled 2026-10-21): the dialog reads what deleting would lose
/// before enabling its button, and a branch with commits its upstream lacks,
/// or with no upstream to compare against, is sent as `-D` at the tip that
/// read counted -- after the warning, never silently. A branch fully in its
/// upstream goes as plain `-d`. The recovery dialog remains the fallback
/// when core and the read disagree (the branch moved: `StaleBranchTip`).
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

  /// The read for [_readFor] at snapshot tip [_readAtTarget]; null while it
  /// is in flight. A newer read supersedes an older one by [_readSeq].
  BranchDeletionProbeReply? _read;
  String? _readFor;
  String? _readAtTarget;
  int _readSeq = 0;

  /// Reads [branch] again whenever the snapshot shows a different branch or a
  /// different tip from the one the current read was taken at: the count
  /// describes that tip, and a refresh that moved it makes the count stale.
  /// Called from build; it changes no provider state and the read's reply
  /// arrives through `setState` later.
  void _readIfStale(RefInfo branch) {
    if (branch.shortName == _readFor && branch.target == _readAtTarget) return;
    final int seq = ++_readSeq;
    _read = null;
    _readFor = branch.shortName;
    _readAtTarget = branch.target;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .probeBranchDeletion(<String>[branch.shortName])
        .then((BranchDeletionProbeReply reply) {
          if (!mounted || seq != _readSeq) return;
          setState(() => _read = reply);
        });
  }

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

    // Resolved once, in one place. The label, the enabled state and the
    // dispatch are three readings of one fact, and every defect this function
    // has had came from two of them being derived separately.
    final (String remote, String remoteBranch) = switch (target) {
      final RefInfo branch => deleteBranchRemoteTarget(
        branch,
        session.refs.remoteBranches,
      ),
      null => ('', ''),
    };
    if (target != null) _readIfStale(target);
    final BranchDeletionProbeReply? read = _read;
    final GitError? readError = read?.error;
    final BranchDeletionProbe? probe = switch (target) {
      final RefInfo branch when read != null && readError == null =>
        read.probes
            .where((BranchDeletionProbe p) => p.name == branch.shortName)
            .firstOrNull,
      _ => null,
    };
    // Plain `-d` only where the read found nothing its upstream lacks (git
    // compares against that same upstream, so it cannot refuse); everything
    // else was warned about above and goes as `-D` at the counted tip.
    final DeleteBranchEntry? entry = switch (probe) {
      ProbeCounted(:final String name, unsyncedCount: 0) =>
        DeleteBranchEntry.plain(name),
      ProbeCounted(:final String name, :final String tipOid) ||
      ProbeNoReference(
        :final String name,
        :final String tipOid,
      ) => DeleteBranchEntry.forced(name, expectedTipOid: tipOid),
      ProbeNotFound() || null => null,
    };
    final bool canDelete = target != null && entry != null;

    // `isGone` is only ever true *after* a prune; between the fetch that
    // discovers a deleted branch and the prune that records it, gone-ness
    // lives in the preview alone. `isEffectivelyGone` is the single source
    // the sidebar rows, the bulk-select set and the status bar all read, so
    // the checkbox reads it too rather than asking a narrower question.
    final bool remoteAlreadyGone = switch (target) {
      final RefInfo branch => isEffectivelyGone(
        branch,
        session.gonePendingRefs,
        // `gonePendingRefs` holds full ref names; the two parts rejoin to
        // exactly the counterpart they came from, since a remote name is a
        // single path segment by `remoteBranchParts`' construction.
        remoteCounterpart: remote.isEmpty
            ? ''
            : fullRemoteRefName('$remote/$remoteBranch'),
      ),
      null => false,
    };

    // One predicate, read by both the checkbox and the delete button.
    // Spelling it twice -- `_alsoDeleteRemote && !remoteAlreadyGone` on the
    // box and `_alsoDeleteRemote && remote.isNotEmpty` at the dispatch -- is
    // the second-source-of-truth shape: the two can only agree by accident,
    // and here they agreed only because the picker's onChanged happens to
    // clear the flag on every selection change. That reset is a separate
    // mechanism and the safety must not rest on it.
    final bool willDeleteRemote =
        _alsoDeleteRemote && remote.isNotEmpty && !remoteAlreadyGone;

    return GbmDialogShell(
      // The mock's header: `Delete branch`, as the primary button reads.
      title: 'Delete branch',
      actionId: GbmActionId.branchDeleteBranch,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Delete branch',
          kind: GbmButtonKind.danger,
          onPressed: canDelete
              ? () {
                  final RepoSessionController notifier = ref.read(
                    repoSessionProvider(widget.identity).notifier,
                  );
                  // The remote half rides on the local request and is sent
                  // only once the local delete succeeds.
                  notifier.deleteBranch(
                    entries: <DeleteBranchEntry>[entry],
                    thenDeleteRemote: <RemoteBranchDeletion>[
                      if (willDeleteRemote)
                        RemoteBranchDeletion(
                          remoteName: remote,
                          names: <String>[remoteBranch],
                        ),
                    ],
                  );
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
            SizedBox(
              height: GbmSpacing.inputHeight,
              child: DropdownButtonFormField<String>(
                initialValue: _selected,
                isExpanded: true,
                decoration: gbmInputDecoration(
                  colors: colors,
                  hintText: '要刪除的分支',
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
                  // The mock: 「刪除本機分支 feature/graph-lanes。」
                  const TextSpan(text: '刪除本機分支 '),
                  TextSpan(
                    text: branch.shortName,
                    style: const TextStyle(
                      fontFamily: GbmTypography.fontMono,
                      fontWeight: GbmTypography.weightSemibold,
                    ),
                  ),
                  const TextSpan(text: '。'),
                ],
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            // Spec 06: 「複述分支名與未合併的 commit 數」, counted against the
            // upstream per the 2026-10-21 ruling. The two cases that lead to
            // `-D` draw inside GbmDialogWarnField (G8b); "fully synced" is
            // informational and stays plain text.
            switch (probe) {
              ProbeCounted(unsyncedCount: 0, :final String upstream) => Text(
                '已完整同步到 ${shortRemoteRefName(upstream)}。',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textSecondary,
                ),
              ),
              ProbeCounted(:final int unsyncedCount, :final String upstream) =>
                GbmDialogWarnField(
                  message:
                      '這個分支有 $unsyncedCount 個 commit 尚未同步到 '
                      '${shortRemoteRefName(upstream)}。',
                ),
              ProbeNoReference() => const GbmDialogWarnField(
                message: '沒有 upstream（或已 gone），無法確認是否已同步。',
              ),
              ProbeNotFound() => _note(colors, '這個分支已經不存在。'),
              null => _note(
                colors,
                readError != null
                    ? branchDeletionProbeFailedText(readError)
                    : '正在計算尚未同步的 commit…',
              ),
            },
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
                  // The mock: 「同時刪除遠端 origin/feature/graph-lanes」.
                  '同時刪除遠端 $remote/$remoteBranch',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  remoteAlreadyGone
                      ? '在 $remote 上已經不存在，沒有東西可以刪。'
                      : '其他人要等到下次 fetch 才會看不到這個分支。',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
                onChanged: remoteAlreadyGone
                    ? null
                    : (bool? value) =>
                          setState(() => _alsoDeleteRemote = value ?? false),
              ),
            ],
          ] else
            Text(
              candidates.isEmpty ? '沒有其他本地分支可以刪除。' : '選擇要刪除的分支。',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _note(GbmColors colors, String text) => Text(
    text,
    style: TextStyle(
      fontSize: GbmTypography.textXs,
      color: colors.textSecondary,
    ),
  );
}
