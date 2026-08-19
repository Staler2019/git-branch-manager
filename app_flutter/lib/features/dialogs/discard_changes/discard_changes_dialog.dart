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
import 'discard_changes_request.dart';

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
/// were always in its remit. Which mode applies is decided by
/// [DiscardChangesRequest], not here: in line mode [request] holds exactly
/// one file plus the hunk and line indices, and the confirm button calls
/// `discardLines` instead of `restorePaths`. A request that asked for line
/// mode but could not be parsed into one ([DiscardChangesRequest.isMalformed])
/// gets no destructive button at all -- see that class for why falling back
/// to whole-file mode would be the wrong answer.
class DiscardChangesDialogContent extends ConsumerWidget {
  const DiscardChangesDialogContent({
    super.key,
    required this.identity,
    required this.request,
  });

  final RepoIdentity identity;
  final DiscardChangesRequest request;

  List<String> get _paths => request.paths;

  /// Untracked files are not restorable from the index -- `git restore`
  /// leaves them alone. They are called out separately so the dialog does
  /// not promise to remove something it will not touch (Clean untracked
  /// files is the action for those; see `clean_untracked/`).
  List<String> _untrackedAmong(RepoSessionState session) {
    final Set<String> selected = _paths.toSet();
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
      for (final String p in _paths)
        if (!untracked.contains(p)) p,
    ];

    final bool isLineMode = request.isLineMode;
    final int lineCount = request.lineIndices.length;
    return GbmDialogShell(
      title: switch ((request.isMalformed, isLineMode, _paths.length)) {
        (true, _, _) => 'Cannot Discard',
        (_, true, _) =>
          lineCount == 1 ? 'Discard Line' : 'Discard $lineCount Lines',
        (_, false, 1) => 'Discard Changes',
        (_, false, final int n) => 'Discard Changes in $n Files',
      },
      actions: <Widget>[
        // A malformed request gets one way out and no danger button: there
        // is no safe action to offer, and the whole-file discard this used
        // to fall through to is exactly the wrong one.
        if (request.isMalformed)
          GbmButton(label: 'Close', onPressed: () => context.pop())
        else ...<Widget>[
          GbmButton(label: 'Cancel', onPressed: () => context.pop()),
          const SizedBox(width: GbmSpacing.space2),
          GbmButton(
            label: switch ((isLineMode, restorable.length)) {
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
                    if (isLineMode) {
                      controller.discardLines(
                        restorable.first,
                        request.hunkIndex!,
                        request.lineIndices,
                      );
                    } else {
                      controller.restorePaths(restorable);
                    }
                    context.pop();
                  },
          ),
        ],
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            switch ((request.isMalformed, isLineMode)) {
              // "reverted", not "removed": a discarded `-` line is one the
              // working copy deleted, so discarding it puts the line back.
              (false, true) =>
                'These $lineCount line(s) will be reverted in the working '
                    'copy of this file. The rest of the file, and the staged '
                    'contents, are left alone:',
              (false, false) =>
                'The uncommitted changes in these files will be replaced '
                    'with their staged contents:',
              (true, _) =>
                'This link asked to discard specific lines, but its line '
                    'selection is incomplete, so it cannot be carried out. '
                    'Nothing has been changed. Reopen the menu from the diff '
                    'to try again. The request named:',
            },
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
          // Omitted when malformed -- nothing is about to happen, so the
          // irreversibility warning would be describing an action the
          // dialog is refusing to offer.
          if (!request.isMalformed) ...<Widget>[
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
        ],
      ),
    );
  }
}
