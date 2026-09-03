import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// Context menu 05-C's "Delete remote branch…".
///
/// Spec page 06: "複述遠端與分支名，說明其他人 fetch 後才會看到。完成後
/// status bar 顯示結果訊息並提供 Undo（重新 push 同名分支）。主按鈕為
/// danger."
///
/// The dialog itself covers the restatement and the fetch-visibility note.
/// The post-completion Undo affordance belongs to the status bar's result
/// message, not here -- see `status_bar.dart`; this dialog deliberately does
/// not claim the deletion is reversible from within itself.
///
/// Routed as `/repo/:repoId/dialogs/delete-remote-branch?remote=…&branch=…`.
class DeleteRemoteBranchDialogContent extends ConsumerWidget {
  const DeleteRemoteBranchDialogContent({
    super.key,
    required this.identity,
    required this.remote,
    required this.branch,
  });

  final RepoIdentity identity;

  /// The remote's name (`origin`), not the full `origin/feature/x` ref.
  final String remote;

  /// The branch name as it exists *on the remote* -- i.e. with the remote
  /// prefix already stripped, since that prefix is a local naming
  /// convention and is not part of the ref on the server.
  final String branch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final bool valid = remote.isNotEmpty && branch.isNotEmpty;

    return GbmDialogShell(
      title: 'Delete Remote Branch',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Delete remote branch',
          kind: GbmButtonKind.danger,
          onPressed: !valid
              ? null
              : () {
                  ref
                      .read(repoSessionProvider(identity).notifier)
                      .deleteBranch(
                        names: <String>[branch],
                        isRemote: true,
                        remoteName: remote,
                      );
                  context.pop();
                },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (!valid)
            Text(
              '沒有指定遠端分支。',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textTertiary,
              ),
            )
          else ...<Widget>[
            Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                  height: GbmTypography.leadingNormal,
                ),
                children: <InlineSpan>[
                  const TextSpan(text: '刪除分支 '),
                  TextSpan(
                    text: branch,
                    style: const TextStyle(
                      fontFamily: GbmTypography.fontMono,
                      fontWeight: GbmTypography.weightSemibold,
                    ),
                  ),
                  const TextSpan(text: '（在 remote '),
                  TextSpan(
                    text: remote,
                    style: const TextStyle(
                      fontFamily: GbmTypography.fontMono,
                      fontWeight: GbmTypography.weightSemibold,
                    ),
                  ),
                  const TextSpan(text: ' 上）？'),
                ],
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            Text(
              '同名的本地分支不會被動到。',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            Text(
              '其他人要等到下次 fetch 才會看不到這個分支。',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
                height: GbmTypography.leadingNormal,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
