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
                      .startRebase(_target!, stashFirst: _stashFirst);
                  context.pop();
                },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Replay the commits of $currentBranch on top of:',
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
              hintText: 'Branch to rebase onto',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: _candidateItems(candidates),
            onChanged: (String? value) => setState(() => _target = value),
          ),
          const SizedBox(height: GbmSpacing.space2),
          Text(
            'Rebasing rewrites the commits of $currentBranch. If a commit '
            'conflicts, the rebase stops on that step and the conflict banner '
            'shows which step of how many it stopped at.',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
              height: GbmTypography.leadingNormal,
            ),
          ),
          if (isDirty) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            CheckboxListTile(
              value: _stashFirst,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Stash uncommitted changes first',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              subtitle: Text(
                '${session.workingCopyStatus.entries.length} file(s) have uncommitted changes.',
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
    );
  }
}
