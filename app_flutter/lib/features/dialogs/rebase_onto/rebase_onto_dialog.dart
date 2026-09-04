import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../data/models/remote_counterpart.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// Branch → Rebase onto… (Ctrl/Cmd+Shift+R), and context menu 05-B's
/// "Rebase current onto here".
///
/// Spec page 06: "目標分支與 commit 數預覽。說明衝突時會停在第幾步" -- the
/// commit count comes from the current branch's `behind` relative to the
/// chosen target where tracking info exists, and is simply omitted when it
/// does not, rather than guessed.
///
/// Distinct from the interactive-rebase dialog (`interactive_rebase/`),
/// which edits a todo plan. This is the plain "replay my commits on top of
/// that branch" flow spec page 04's Branch menu lists.
///
/// **[DRIFT-rebase-onto-missing-capi-flags] is closed as of this dialog.**
/// The mock's two checkboxes (chk-on 「保留 merge commit（--rebase-merges）」
/// and chk 「自動 squash 標記過的 fixup commit」) and its "already pushed"
/// warn banner are all drawn now. The checkboxes needed the capi change
/// this pin called for: `RebaseRequest` gained `rebaseMerges`/`autosquash`
/// fields, `gbm_rebase_start` two more `int32_t` parameters, and
/// `startRebase()` two more named bools -- see RebaseOps.cpp's measurement
/// comment for why both flags work on this plain, non-interactive call with
/// no `-i` of our own. The warn banner reads whether the *current* branch
/// has a remote counterpart via [remoteCounterpartOf] -- the same single
/// source `delete_branch_dialog.dart`'s own doc comment names traps for:
/// `hasTrackingInfo` is empty for a branch exactly in sync, and `upstream`
/// alone misses a `git push origin HEAD` branch with no tracking config.
///
/// Routed as `/repo/:repoId/dialogs/rebase-onto`.
class RebaseOntoDialogContent extends ConsumerStatefulWidget {
  const RebaseOntoDialogContent({
    super.key,
    required this.identity,
    this.target,
  });

  final RepoIdentity identity;

  /// Pre-selects what to rebase onto. 05-B's "Rebase current onto here"
  /// passes a branch name, which is already one of the dropdown's own
  /// options; 05-E's "Rebase onto here" passes a commit oid, which is not,
  /// so [_candidateItems] adds it as an extra option rather than dropping a
  /// target the user explicitly picked. `git rebase` takes any committish,
  /// so an oid is a perfectly good upstream -- see gbm_capi.h's
  /// gbm_rebase_start.
  final String? target;

  @override
  ConsumerState<RebaseOntoDialogContent> createState() =>
      _RebaseOntoDialogContentState();
}

class _RebaseOntoDialogContentState
    extends ConsumerState<RebaseOntoDialogContent> {
  String? _target;
  bool _stashFirst = false;
  bool _rebaseMerges = true;
  bool _autosquash = false;

  @override
  void initState() {
    super.initState();
    _target = widget.target;
  }

  /// The branch list, plus [RebaseOntoDialogContent.target] itself when it
  /// is not one of those branches (a commit oid). Without that extra entry
  /// `DropdownButtonFormField` would assert on an `initialValue` that is
  /// not among its items, and silently dropping the pre-fill would send the
  /// user back to picking a target they already chose.
  List<DropdownMenuItem<String>> _candidateItems(List<RefInfo> candidates) {
    final String? target = widget.target;
    final bool targetIsBranch = candidates.any(
      (RefInfo b) => b.shortName == target,
    );
    return <DropdownMenuItem<String>>[
      if (target != null && !targetIsBranch)
        DropdownMenuItem<String>(
          value: target,
          // Abbreviated the way every other oid in the app is, so the row
          // reads as a commit rather than as a 40-character branch name.
          child: Text(
            target.length >= 8 ? 'commit ${target.substring(0, 8)}' : target,
          ),
        ),
      for (final RefInfo b in candidates)
        DropdownMenuItem<String>(value: b.shortName, child: Text(b.shortName)),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final String currentBranch = session.refs.head.branchName.isNotEmpty
        ? session.refs.head.branchName
        : 'HEAD';

    final List<RefInfo> candidates = <RefInfo>[
      for (final RefInfo b in session.refs.localBranches)
        if (b.shortName != currentBranch) b,
      ...session.refs.remoteBranches,
    ];

    final bool isDirty = session.workingCopyStatus.entries.isNotEmpty;

    // DLGS's warn field applies only when the branch being rebased has
    // already been pushed -- remoteCounterpartOf() is the single source
    // that answers "does this local branch have a remote side", never
    // re-derived from hasTrackingInfo or upstream alone (see this class's
    // doc comment for why).
    RefInfo? currentBranchRef;
    for (final RefInfo b in session.refs.localBranches) {
      if (b.shortName == currentBranch) currentBranchRef = b;
    }
    final bool hasRemoteCounterpart =
        currentBranchRef != null &&
        remoteCounterpartOf(
          currentBranchRef,
          session.refs.remoteBranches,
        ).isNotEmpty;

    return GbmDialogShell(
      title: 'Rebase',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Start rebase',
          kind: GbmButtonKind.primary,
          onPressed: _target == null
              ? null
              : () {
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .startRebase(
                        _target!,
                        stashFirst: _stashFirst,
                        rebaseMerges: _rebaseMerges,
                        autosquash: _autosquash,
                      );
                  context.pop();
                },
        ),
      ],
      // Scrollable, like New branch's and Checkout's: the two new checkboxes
      // plus the warn banner can exceed GbmDialogShell's 560px cap, and
      // every child here is non-flex ([FLU-renderflex-non-flex-first]).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '重新安置 $currentBranch 到：',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            DropdownButtonFormField<String>(
              initialValue: _target,
              isExpanded: true,
              decoration: const InputDecoration(
                hintText: '基於',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: _candidateItems(candidates),
              onChanged: (String? value) => setState(() => _target = value),
            ),
            const SizedBox(height: GbmSpacing.space2),
            Text(
              'Rebase 會重寫 $currentBranch 的 commit。若某筆 commit 衝突，'
              'rebase 會停在該步驟，衝突橫幅會顯示目前停在第幾步、共幾步。',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
                height: GbmTypography.leadingNormal,
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            // DLGS's chk-on/chk pair, quoted verbatim.
            CheckboxListTile(
              value: _rebaseMerges,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '保留 merge commit（--rebase-merges）',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              onChanged: (bool? value) =>
                  setState(() => _rebaseMerges = value ?? _rebaseMerges),
            ),
            CheckboxListTile(
              value: _autosquash,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                '自動 squash 標記過的 fixup commit',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              onChanged: (bool? value) =>
                  setState(() => _autosquash = value ?? _autosquash),
            ),
            if (hasRemoteCounterpart) ...<Widget>[
              const SizedBox(height: GbmSpacing.space2),
              Text(
                '此分支已 push。rebase 後需 force push，共作者需重新對齊。',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.warning,
                  height: GbmTypography.leadingNormal,
                ),
              ),
            ],
            if (isDirty) ...<Widget>[
              const SizedBox(height: GbmSpacing.space2),
              CheckboxListTile(
                value: _stashFirst,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  '先 stash 未提交的變更',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  '${session.workingCopyStatus.pendingChangeCount} 個檔案有未提交的變更。',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
                onChanged: (bool? value) =>
                    setState(() => _stashFirst = value ?? false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
