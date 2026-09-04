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
///
/// Whole-file mode's `DLGS` entry ("Discard changes") also notes: 「主按鈕寫出
/// 實際數量；兩個檔案以下改成寫檔名」-- at 1-2 files the primary button names
/// the file(s) rather than a count, which [_dangerLabel] implements. The
/// 2-file join format is not itself specced; joining with ", " is this
/// dialog's own reading of it, not a quoted value.
class DiscardChangesDialogContent extends ConsumerWidget {
  const DiscardChangesDialogContent({
    super.key,
    required this.identity,
    required this.request,
  });

  final RepoIdentity identity;
  final DiscardChangesRequest request;

  List<String> get _paths => request.paths;

  /// `DLGS`'s note for whole-file mode: the primary button writes the actual
  /// count, except at 1-2 files where it names the file(s) instead.
  String _dangerLabel(int lineCount, List<String> restorable) {
    if (request.isLineMode) {
      return lineCount == 1 ? 'Discard line' : 'Discard $lineCount lines';
    }
    switch (restorable.length) {
      case 1:
        return 'Discard ${restorable.single.split('/').last}';
      case 2:
        return 'Discard ${restorable.map((String p) => p.split('/').last).join(', ')}';
      default:
        return 'Discard ${restorable.length} files';
    }
  }

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
            label: _dangerLabel(lineCount, restorable),
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
      // Scrollable, like Rebase onto's and Checkout's: the untracked-files
      // note plus the irreversibility warning can push this past
      // GbmDialogShell's height cap, and every child here is non-flex
      // ([FLU-renderflex-non-flex-first]).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              switch ((request.isMalformed, isLineMode)) {
                // "復原"，不是「移除」：discard 的 `-` 行是工作區刪掉的行，
                // discard 之後這行會回來。
                (false, true) =>
                  '這 $lineCount 行將在此檔的工作區中復原。檔案其餘部分與已 '
                      'stage 的內容不受影響：',
                // DLGS 的 list 標籤，逐字引用。
                (false, false) => '丟掉這些變更：',
                (true, _) =>
                  '這個連結要求丟掉指定的行，但所選的行不完整，無法執行。'
                      '內容未被更動。請從 diff 重新開啟選單再試一次。'
                      '原始請求指定的檔案：',
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
                        padding: const EdgeInsets.only(
                          bottom: GbmSpacing.space1,
                        ),
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
                '${untracked.length} 個選取的檔案是未追蹤，將維持不變 — '
                '如需移除請用 Clean untracked files。',
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
                // DLGS 的 warn 欄位，逐字引用。
                '這些變更不進 stash、也不在 reflog，丟掉就沒了。',
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
      ),
    );
  }
}
