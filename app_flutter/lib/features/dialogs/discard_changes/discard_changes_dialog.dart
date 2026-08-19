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
///
/// Also serves context menu 05-G's line-level "Discard N lines…" -- spec
/// page 06's entry for this dialog is "列出實際檔名與行數", so line counts
/// were always in its remit. That mode is selected by [lineIndices] being
/// non-empty, in which case [paths] holds exactly one file, [hunkIndex] says
/// which hunk the indices are relative to, and the confirm button calls
/// `discardLines` instead of `restorePaths`.
class DiscardChangesDialogContent extends ConsumerWidget {
  const DiscardChangesDialogContent({
    super.key,
    required this.identity,
    required this.paths,
    this.hunkIndex,
    this.lineIndices = const <int>[],
  });

  final RepoIdentity identity;
  final List<String> paths;

  /// The hunk [lineIndices] index into, or null in whole-file mode.
  final int? hunkIndex;

  /// Line indices within [hunkIndex]'s `lines` array. Empty means whole-file
  /// mode; non-empty selects the line-level mode described above.
  final List<int> lineIndices;

  bool get _isLineMode => lineIndices.isNotEmpty && hunkIndex != null;

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

    final int lineCount = lineIndices.length;
    return GbmDialogShell(
      title: switch ((_isLineMode, paths.length)) {
        (true, _) =>
          lineCount == 1 ? 'Discard Line' : 'Discard $lineCount Lines',
        (false, 1) => 'Discard Changes',
        (false, final int n) => 'Discard Changes in $n Files',
      },
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: switch ((_isLineMode, restorable.length)) {
            (true, _) =>
              lineCount == 1 ? 'Discard line' : 'Discard $lineCount lines',
            (false, 1) => 'Discard changes',
            (false, final int n) => 'Discard $n files',
          },
          kind: GbmButtonKind.danger,
          onPressed: restorable.isEmpty
              ? null
              : () {
                  final RepoSessionController controller = ref.read(
                    repoSessionProvider(identity).notifier,
                  );
                  if (_isLineMode) {
                    controller.discardLines(
                      restorable.first,
                      hunkIndex!,
                      lineIndices,
                    );
                  } else {
                    controller.restorePaths(restorable);
                  }
                  context.pop();
                },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            _isLineMode
                ? 'These $lineCount line(s) will be removed from the working '
                      'copy of this file. The rest of the file, and the '
                      'staged contents, are left alone:'
                : 'The uncommitted changes in these files will be replaced '
                      'with their staged contents:',
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
