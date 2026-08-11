import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/undo_entry.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `MainWindow::onUndoLastOperation()`'s confirmation
/// prompt (src/app/views/MainWindow.cpp): a plain confirm/cancel over the
/// newest entry of [RepoSessionState.undoJournal]. Routed as
/// `/repo/:repoId/dialogs/undo-last` for the same deep-linkable/Esc-closable
/// consistency every other dialog gets (see dialog_route.dart), even though
/// nothing here needs to survive a restart.
class UndoLastDialogContent extends ConsumerWidget {
  const UndoLastDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    final List<UndoEntry> journal = ref.watch(repoSessionProvider(identity).select((state) => state.undoJournal));
    final UndoEntry? last = journal.isEmpty ? null : journal.last;

    return GbmDialogShell(
      title: 'Undo Last Operation',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Undo',
          kind: GbmButtonKind.primary,
          onPressed: last == null
              ? null
              : () {
                  ref.read(repoSessionProvider(identity).notifier).undoLast();
                  context.pop();
                },
        ),
      ],
      child: SizedBox(
        height: 96,
        child: Center(
          child: last == null
              ? Text('Nothing to undo yet', style: TextStyle(color: colors.textTertiary))
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Undo this operation?', style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary)),
                    const SizedBox(height: GbmSpacing.space2),
                    Text(
                      last.description,
                      style: TextStyle(
                        fontSize: GbmTypography.textMd,
                        fontWeight: GbmTypography.weightSemibold,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (last.branchBefore.isNotEmpty) ...<Widget>[
                      const SizedBox(height: GbmSpacing.space1),
                      Text(
                        'Will restore ${last.branchBefore} @ ${last.headBefore.length > 7 ? last.headBefore.substring(0, 7) : last.headBefore}',
                        style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
