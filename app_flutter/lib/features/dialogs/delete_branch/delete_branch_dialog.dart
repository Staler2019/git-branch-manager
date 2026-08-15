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

  /// The remote a branch's upstream lives on: `origin/feature/x` -> `origin`.
  /// Empty when the branch has no upstream, which is what hides the
  /// "also delete on remote" checkbox.
  static String _remoteOf(RefInfo branch) {
    if (!branch.hasTrackingInfo || branch.upstream.isEmpty) return '';
    final int slash = branch.upstream.indexOf('/');
    return slash == -1 ? '' : branch.upstream.substring(0, slash);
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

    final String remote = target == null ? '' : _remoteOf(target);
    final bool canDelete = target != null;

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
                  if (_alsoDeleteRemote && remote.isNotEmpty) {
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
                value: _alsoDeleteRemote,
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Also delete ${branch.upstream} on $remote',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                ),
                subtitle: Text(
                  'Other people only see this after they fetch.',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
                onChanged: (bool? value) =>
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
