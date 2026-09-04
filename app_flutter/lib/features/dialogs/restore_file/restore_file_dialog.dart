import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/commit_meta.dart';
import '../../../data/models/working_copy_status.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// Context menu 05-K → More actions → "Restore file to this state" and
/// "Restore and stage".
///
/// Spec page 06: "把單一檔案還原成該 commit 當時的內容。dialog 寫出檔名、
/// 來源 commit 的 hash 與 summary，並說明目前 working copy 的該檔變更會被
/// 覆蓋（若有未提交變更則額外標紅）。Restore and stage 同時放進暫存區。不
/// 建立 commit，還原後仍可 discard。"
///
/// Both actions are offered as two buttons on one dialog rather than two
/// separate menu-driven dialogs, since they differ only in whether the
/// result also lands in the index -- the confirmation text is identical.
///
/// Routed as `/repo/:repoId/dialogs/restore-file?path=…&oid=…`.
///
/// **This dialog is only the `DLGS` "Restore file to this state" half.**
/// The spec's other half, "Restore file to before this state" (restoring to
/// the commit's *parent*, undoing just that commit's change to this file --
/// full text below), has no dialog and no menu entry at all;
/// `gbm_context_menus.dart`'s own doc comment on `_historyCommitFile`
/// already flags the missing 05-K submenu item as a pre-existing, deliberate
/// gap. Recorded as [DRIFT-restore-before-this-state-missing] rather than
/// built here: G1 is a copy-only pass over what exists, and this is a new
/// dialog plus a new context-menu entry, not a translation of one.
///
/// Even within this half, three fields from `DLGS`'s own entry are still
/// absent -- also filed under the same pin rather than added blind:
/// - the `chk`「還原前先 stash 目前的變更」checkbox (needs a stash-then-
///   restore sequencing decision, not just a label);
/// - the exact `warn` wording, which names a real line count
///   ("此檔目前有未提交的 42 行變更…") this dialog has no data for -- it
///   only knows [_hasUncommittedChanges] as a bool, so the Chinese text
///   below is phrased to match that boolean, not copied from the mock's
///   invented number (the same adaptation [DRIFT-auto-fetch-unwired]'s
///   entry calls for elsewhere: phrase to the app's real capability, not
///   the spec's as-if-working prose).
class RestoreFileDialogContent extends ConsumerWidget {
  const RestoreFileDialogContent({
    super.key,
    required this.identity,
    required this.path,
    required this.oid,
  });

  final RepoIdentity identity;
  final String path;

  /// The commit whose version of [path] is restored. Passed through the
  /// route rather than read from a selection, so the dialog names the same
  /// commit the context menu was opened on even if the selection moves.
  final String oid;

  String get _shortOid => oid.length > 7 ? oid.substring(0, 7) : oid;

  /// Whether the working copy currently has uncommitted changes to [path] --
  /// the case the spec asks to mark in red, because that is the work the
  /// restore silently overwrites.
  bool _hasUncommittedChanges(RepoSessionState session) {
    for (final WorkingCopyEntry e in session.workingCopyStatus.entries) {
      if (e.path == path) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(repoSessionProvider(identity));
    final CommitMeta? meta = session.commitMetaCache[oid];
    final bool dirty = _hasUncommittedChanges(session);

    void restore({required bool alsoStage}) {
      final RepoSessionController notifier = ref.read(
        repoSessionProvider(identity).notifier,
      );
      // Work tree first, then the index from the same source -- `staged:
      // true` alone would move the index without changing the file on disk.
      notifier.restorePaths(<String>[path], source: oid);
      if (alsoStage) {
        notifier.restorePaths(<String>[path], staged: true, source: oid);
      }
      context.pop();
    }

    return GbmDialogShell(
      title: 'Restore File',
      width: 520,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Restore and stage',
          onPressed: () => restore(alsoStage: true),
        ),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Restore',
          kind: GbmButtonKind.primary,
          onPressed: () => restore(alsoStage: false),
        ),
      ],
      // Scrollable, like Rebase onto's and Checkout's: the two ro labels
      // added above can push this past GbmDialogShell's height cap on a
      // long subject line, and every child here is non-flex
      // ([FLU-renderflex-non-flex-first]).
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // DLGS 的 ro 標籤「檔案」，逐字引用。P6 field-label treatment
            // (spec's G3) -- see add_worktree_dialog.dart's identical
            // comment on '分支'.
            Text(
              '檔案',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            Text(
              path,
              style: TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            // DLGS 的 ro 標籤「還原成」，逐字引用。P6 field-label treatment
            // (spec's G3).
            Text(
              '還原成',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _shortOid,
                  style: TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontSize: GbmTypography.textSm,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                Expanded(
                  child: Text(
                    // The subject is only known once commitMetaReady has
                    // answered for this oid; the hash above always identifies
                    // the commit, so an unresolved subject is left blank
                    // rather than filled with a guess.
                    meta?.subject ?? '',
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      color: colors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: GbmSpacing.space3),
            Text(
              // DLGS 的 warn 欄位要求寫出實際變更行數，但這個對話框只知道
              // 「有沒有未提交變更」這個布林值，沒有行數可用 -- 依現有能力
              // 改寫措辭，不照抄 mock 裡虛構的行數（見本檔案類別註解）。
              dirty ? '此檔在工作區有未提交的變更，會被覆蓋且無法復原。' : '工作區內這個檔案的版本將被取代。',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                fontWeight: dirty
                    ? GbmTypography.weightSemibold
                    : GbmTypography.weightRegular,
                color: dirty ? colors.danger : colors.textSecondary,
                height: GbmTypography.leadingNormal,
              ),
            ),
            const SizedBox(height: GbmSpacing.space1),
            Text(
              '不會建立新的 commit。還原後的檔案會像一般工作區變更一樣，'
              '之後仍可以再 discard。',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
                height: GbmTypography.leadingNormal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
