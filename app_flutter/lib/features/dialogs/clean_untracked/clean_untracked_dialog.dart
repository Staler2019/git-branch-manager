import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/clean_entry.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `CleanUntrackedDialog` (src/app/dialogs/
/// CleanUntrackedDialog.cpp): a read-only preview of what `git clean` would
/// remove, so the destructive sweep never runs unseen. Routed as
/// `/repo/:repoId/dialogs/clean-untracked`.
class CleanUntrackedDialogContent extends ConsumerStatefulWidget {
  const CleanUntrackedDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<CleanUntrackedDialogContent> createState() =>
      _CleanUntrackedDialogContentState();
}

class _CleanUntrackedDialogContentState
    extends ConsumerState<CleanUntrackedDialogContent> {
  bool _includeIgnored = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_preview);
  }

  void _preview() {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .requestCleanPreview(includeIgnored: _includeIgnored);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<CleanEntry> preview = ref.watch(
      repoSessionProvider(
        widget.identity,
      ).select((state) => state.lastCleanPreview),
    );
    final RepoSessionController notifier = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );

    return GbmDialogShell(
      title: 'Clean Untracked Files',
      width: 560,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label:
              'Delete ${preview.length} item${preview.length == 1 ? '' : 's'}',
          kind: GbmButtonKind.primary,
          onPressed: preview.isEmpty
              ? null
              : () {
                  notifier.cleanUntracked(includeIgnored: _includeIgnored);
                  context.pop();
                },
        ),
      ],
      child: SizedBox(
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            CheckboxListTile(
              value: _includeIgnored,
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                'Also remove ignored files',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
              ),
              onChanged: (value) {
                setState(() => _includeIgnored = value ?? false);
                _preview();
              },
            ),
            const Divider(height: GbmSpacing.space2),
            Expanded(
              child: preview.isEmpty
                  ? Center(
                      child: Text(
                        'Nothing to clean',
                        style: TextStyle(color: colors.textTertiary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: preview.length,
                      itemBuilder: (context, index) {
                        final CleanEntry entry = preview[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            entry.isDirectory
                                ? Icons.folder_outlined
                                : Icons.insert_drive_file_outlined,
                            size: 16,
                            color: colors.textTertiary,
                          ),
                          title: Text(
                            entry.path,
                            style: TextStyle(
                              fontSize: GbmTypography.textSm,
                              color: colors.textPrimary,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
