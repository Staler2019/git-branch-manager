import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/working_copy_status.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// Confirmation for context menu 05-F's "Discard changes in N files…".
///
/// Spec page 06: "列出實際檔名與行數。無法復原這件事要寫明。主按鈕為 danger"
/// -- so the paths are listed in full rather than summarised as a count, and
/// the irreversibility is stated as its own line instead of being implied by
/// the button colour.
///
/// Before this dialog existed, `WorkingCopyView._discardFile` called
/// `restorePaths` straight from the context menu, destroying uncommitted
/// work with no confirmation at all -- the one flow in the app where a
/// single mis-click was unrecoverable.
///
/// Routed as `/repo/:repoId/dialogs/discard-changes?path=…` (repeatable
/// `path` parameter, so a multi-selection round-trips through the URL).
class DiscardChangesDialogContent extends ConsumerWidget {
  const DiscardChangesDialogContent({
    super.key,
    required this.identity,
    required this.paths,
  });

  final RepoIdentity identity;
  final List<String> paths;

  /// Untracked files are not restorable from the index -- `git restore`
  /// leaves them alone. They are called out separately so the dialog does
  /// not promise to remove something it will not touch (Clean untracked
  /// files is the action for those; see `clean_untracked/`).
  List<String> _untrackedAmong(RepoSessionState session) {
    final Set<String> selected = paths.toSet();
    return <String>[
      for (final WorkingCopyEntry e in session.workingCopyStatus.entries)
        if (e.untracked && selected.contains(e.path)) e.path,
    ];
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(repoSessionProvider(identity));
    final List<String> untracked = _untrackedAmong(session);
    final List<String> restorable = <String>[
      for (final String p in paths)
        if (!untracked.contains(p)) p,
    ];

    return GbmDialogShell(
      title: paths.length == 1
          ? 'Discard Changes'
          : 'Discard Changes in ${paths.length} Files',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: restorable.length == 1
              ? 'Discard changes'
              : 'Discard ${restorable.length} files',
          kind: GbmButtonKind.danger,
          onPressed: restorable.isEmpty
              ? null
              : () {
                  ref
                      .read(repoSessionProvider(identity).notifier)
                      .restorePaths(restorable);
                  context.pop();
                },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'The uncommitted changes in these files will be replaced with '
            'their staged contents:',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
              height: GbmTypography.leadingNormal,
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final String path in restorable)
                    Padding(
                      padding: const EdgeInsets.only(bottom: GbmSpacing.space1),
                      child: Text(
                        path,
                        style: TextStyle(
                          fontFamily: GbmTypography.fontMono,
                          fontSize: GbmTypography.textXs,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (untracked.isNotEmpty) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            Text(
              '${untracked.length} selected file(s) are untracked and will be '
              'left alone — use Clean untracked files to remove those.',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.warning,
                height: GbmTypography.leadingNormal,
              ),
            ),
          ],
          const SizedBox(height: GbmSpacing.space2),
          Text(
            'This cannot be undone. Discarded changes are not recoverable '
            'from the reflog or the stash.',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              fontWeight: GbmTypography.weightSemibold,
              color: colors.danger,
              height: GbmTypography.leadingNormal,
            ),
          ),
        ],
      ),
    );
  }
}
