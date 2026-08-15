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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            path,
            style: TextStyle(
              fontFamily: GbmTypography.fontMono,
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          Text(
            'RESTORE FROM',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              fontWeight: GbmTypography.weightSemibold,
              color: colors.textTertiary,
              letterSpacing: 0.5,
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
            dirty
                ? 'This file has uncommitted changes in the working copy. '
                      'They will be overwritten.'
                : 'The working copy version of this file will be replaced.',
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
            'No commit is created. The restored file shows up as a normal '
            'working-copy change and can still be discarded afterwards.',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
              height: GbmTypography.leadingNormal,
            ),
          ),
        ],
      ),
    );
  }
}
