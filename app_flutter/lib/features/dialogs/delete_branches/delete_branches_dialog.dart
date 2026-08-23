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

/// One branch's line in the confirmation list.
@immutable
class DeleteBranchLine {
  const DeleteBranchLine({
    required this.name,
    required this.unpushed,
    required this.remote,
  });

  final String name;

  /// Commits on this branch its upstream does not have, or null when the
  /// branch has no upstream at all -- see [deleteBranchLines].
  final int? unpushed;

  /// The remote its upstream lives on, empty when it has none.
  final String remote;

  bool get hasUpstream => remote.isNotEmpty;
}

/// Builds the per-branch lines spec page 13 requires the confirmation to
/// show: 「破壞性批次動作（Delete branches、Drop stashes）的確認 dialog 逐項
/// 列出名稱與未 push 的 commit 數，並區分「本地」與「遠端」兩份清單，不用
/// 一句「刪除 3 個分支？」概括」.
///
/// **`ahead` only means anything when there is an upstream.** A branch that
/// never had one reports `ahead: 0`, which rendered literally would claim
/// "0 unpushed commits" -- the opposite of the truth, since *every* commit
/// on it is unpushed. Those lines carry a null [DeleteBranchLine.unpushed]
/// and say so instead.
///
/// The upstream test is `upstream.isNotEmpty`, **not** `hasTrackingInfo`:
/// the latter mirrors git's `%(upstream:track)`, which is an empty string
/// for a branch exactly in sync with its upstream (see CLAUDE.md's Tier 0c
/// note), so it would wrongly report the most common case as untracked.
///
/// The remote name comes from [remoteBranchParts], never from splitting
/// `upstream` at its first slash -- `upstream` is the *full* ref name
/// (`refs/remotes/origin/x`), so that split yields `"refs"`. That is exactly
/// the live bug tracked as #74 in `delete_branch_dialog.dart`.
List<DeleteBranchLine> deleteBranchLines(List<String> names, RefSnapshot refs) {
  final Map<String, RefInfo> byName = <String, RefInfo>{
    for (final RefInfo r in refs.refs)
      if (r.kind == RefKind.localBranch) r.shortName: r,
  };
  return <DeleteBranchLine>[
    for (final String name in names)
      if (byName[name] case final RefInfo branch)
        DeleteBranchLine(
          name: name,
          unpushed: branch.upstream.isEmpty ? null : branch.ahead,
          remote: branch.upstream.isEmpty
              ? ''
              : remoteBranchParts(branch.upstream).$1,
        )
      else
        DeleteBranchLine(name: name, unpushed: null, remote: ''),
  ];
}

/// Confirms a multi-branch delete, listing every branch by name with its
/// unpushed-commit count and splitting local from remote, per spec page 13.
///
/// Routed as `/repo/:repoId/dialogs/delete-branches?names=a,b,c`. Distinct
/// from `delete_branch_dialog.dart`, which is the single-branch 05-B flow
/// with its own branch picker.
class DeleteBranchesDialogContent extends ConsumerStatefulWidget {
  const DeleteBranchesDialogContent({
    super.key,
    required this.identity,
    required this.names,
  });

  final RepoIdentity identity;
  final List<String> names;

  @override
  ConsumerState<DeleteBranchesDialogContent> createState() =>
      _DeleteBranchesDialogContentState();
}

class _DeleteBranchesDialogContentState
    extends ConsumerState<DeleteBranchesDialogContent> {
  bool _alsoDeleteRemote = false;
  bool _force = false;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final List<DeleteBranchLine> lines = deleteBranchLines(
      widget.names,
      session.refs,
    );
    final List<DeleteBranchLine> tracked = lines
        .where((DeleteBranchLine l) => l.hasUpstream)
        .toList();

    return GbmDialogShell(
      title: 'Delete ${lines.length} branches',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Delete ${lines.length} branches',
          kind: GbmButtonKind.danger,
          onPressed: lines.isEmpty ? null : () => _delete(lines, tracked),
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _sectionTitle(context, 'Local branches'),
          for (final DeleteBranchLine line in lines) _BranchLineRow(line: line),
          if (tracked.isNotEmpty) ...<Widget>[
            const SizedBox(height: GbmSpacing.space3),
            _sectionTitle(context, 'Remote branches'),
            for (final DeleteBranchLine line in tracked)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  '${line.remote}/${line.name}',
                  style: TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontSize: GbmTypography.textXs,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            CheckboxListTile(
              value: _alsoDeleteRemote,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Also delete on the remote',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              onChanged: (bool? value) =>
                  setState(() => _alsoDeleteRemote = value ?? false),
            ),
          ],
          CheckboxListTile(
            value: _force,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Delete even if not fully merged',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
            onChanged: (bool? value) => setState(() => _force = value ?? false),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.only(bottom: GbmSpacing.space1),
    child: Text(
      text,
      style: TextStyle(
        fontSize: GbmTypography.textXs,
        fontWeight: GbmTypography.weightSemibold,
        color: context.gbmColors.textTertiary,
      ),
    ),
  );

  void _delete(List<DeleteBranchLine> lines, List<DeleteBranchLine> tracked) {
    final RepoSessionController notifier = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );
    // One call, not N: gbm_branch_delete takes every name at once, matching
    // `git branch -d`'s own multi-name support -- "a multi-select delete is
    // one operation, not N" (gbm_capi.h). N calls would also emit N
    // OPERATION_FINISHED events against spec page 10's one-background-task
    // rule.
    notifier.deleteBranch(
      names: <String>[for (final DeleteBranchLine l in lines) l.name],
      force: _force,
    );
    if (_alsoDeleteRemote) {
      // Grouped by remote: gbm_branch_delete's remote form runs
      // `git push <remoteName> --delete <names...>`, so a selection spanning
      // two remotes needs one call each rather than one call with a remote
      // name that is only right for some of them.
      final Map<String, List<String>> byRemote = <String, List<String>>{};
      for (final DeleteBranchLine line in tracked) {
        byRemote.putIfAbsent(line.remote, () => <String>[]).add(line.name);
      }
      byRemote.forEach((String remote, List<String> names) {
        notifier.deleteBranch(
          names: names,
          isRemote: true,
          remoteName: remote,
          force: _force,
        );
      });
    }
    context.pop();
  }
}

class _BranchLineRow extends StatelessWidget {
  const _BranchLineRow({required this.line});

  final DeleteBranchLine line;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String detail = switch (line.unpushed) {
      null => 'no upstream — nothing has been pushed',
      0 => 'fully pushed',
      final int n => '$n unpushed commit${n == 1 ? '' : 's'}',
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              line.name,
              style: TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textXs,
                color: colors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          Text(
            detail,
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: line.unpushed == null || line.unpushed! > 0
                  ? colors.warning
                  : colors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}
