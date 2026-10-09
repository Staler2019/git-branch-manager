import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../data/models/ref_snapshot.dart';
import '../../../data/models/remote_counterpart.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_field_kinds.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_ref_picker.dart';
import '../../../widgets/gbm_ref_read_only_field.dart';

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
/// **The Rebase onto mock delta (G1d) is closed as of this dialog.**
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

  /// What to rebase onto, when the caller already chose it: 05-B's "Rebase
  /// current onto here" passes a branch name, 05-E's "Rebase onto here" a
  /// commit oid. Either locks the field read-only (merge-rebase-dialogs-spec
  /// 03-B/03-C, ruling ①) -- the user is not asked again for what they just
  /// right-clicked. `git rebase` takes any committish, so an oid is a
  /// perfectly good upstream -- see gbm_capi.h's gbm_rebase_start.
  final String? target;

  @override
  ConsumerState<RebaseOntoDialogContent> createState() =>
      _RebaseOntoDialogContentState();
}

class _RebaseOntoDialogContentState
    extends ConsumerState<RebaseOntoDialogContent> {
  String? _target;

  /// The picker entry's kind. A locked target comes from a local branch row
  /// (05-B) or a commit row (05-E), so it is looked up as a local branch and
  /// otherwise -- an oid -- left as it is.
  RefKind _targetKind = RefKind.localBranch;
  bool _stashFirst = false;
  bool _rebaseMerges = true;
  bool _autosquash = false;

  @override
  void initState() {
    super.initState();
    _target = widget.target;
  }

  /// Local branches other than the current one, then every remote-tracking
  /// branch -- the list the dropdown this replaced offered.
  List<GbmRefPickerEntry> _entries(
    RepoSessionState session,
    String currentBranch,
  ) => <GbmRefPickerEntry>[
    for (final RefInfo b in session.refs.localBranches)
      if (b.shortName != currentBranch)
        GbmRefPickerEntry(name: b.shortName, kind: GbmRefKind.localBranch),
    for (final RefInfo b in session.refs.remoteBranches)
      GbmRefPickerEntry(name: b.shortName, kind: GbmRefKind.remoteBranch),
  ];

  /// How a locked [RebaseOntoDialogContent.target] is drawn: a branch by
  /// name, an oid abbreviated the way every other oid in the app is, so it
  /// reads as a commit rather than as a 40-character branch name.
  (String, GbmRefKind) _lockedTarget(RepoSessionState session, String target) {
    if (session.refs.remoteBranches.any((RefInfo b) => b.shortName == target)) {
      return (target, GbmRefKind.remoteBranch);
    }
    if (session.refs.localBranches.any((RefInfo b) => b.shortName == target)) {
      return (target, GbmRefKind.localBranch);
    }
    return (
      target.length >= 8 ? 'commit ${target.substring(0, 8)}' : target,
      GbmRefKind.commit,
    );
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

    final String? lockedTarget = widget.target;

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
      actionId: GbmActionId.branchRebaseOnto,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Start rebase',
          kind: GbmButtonKind.primary,
          onPressed: _target == null
              ? null
              : () {
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .startRebase(
                        // The full ref: git reads a bare name tag-first, so a
                        // same-named tag would be the base (verifier P4 #7).
                        session.refs
                                .findBranch(_target!, kind: _targetKind)
                                ?.fullName ??
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
            // DLGS: `ro 重新安置` then `focus 基於`; a target the caller
            // already chose is drawn `ro` too.
            GbmRefReadOnlyField(
              label: '重新安置',
              name: currentBranch,
              kind: GbmRefKind.localBranch,
            ),
            const SizedBox(height: GbmSpacing.space2),
            if (lockedTarget != null)
              Builder(
                builder: (_) {
                  final (String name, GbmRefKind kind) = _lockedTarget(
                    session,
                    lockedTarget,
                  );
                  return GbmRefReadOnlyField(
                    label: '基於',
                    name: name,
                    kind: kind,
                  );
                },
              )
            else ...<Widget>[
              Text(
                '基於',
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: GbmSpacing.space1),
              GbmRefPicker(
                entries: _entries(session, currentBranch),
                selected: _target,
                autofocus: true,
                hintText: '搜尋分支',
                emptyMessage: '沒有可以作為基準的分支。',
                maxListHeight: 160,
                onSelected: (GbmRefPickerEntry entry) => setState(() {
                  _target = entry.name;
                  _targetKind = entry.kind == GbmRefKind.remoteBranch
                      ? RefKind.remoteBranch
                      : RefKind.localBranch;
                }),
              ),
            ],
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
              // G8b: dialog-internal warnings use GbmDialogWarnField, not a
              // bare colors.warning-styled Text.
              const GbmDialogWarnField(
                message: '此分支已 push。rebase 後需 force push，共作者需重新對齊。',
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
