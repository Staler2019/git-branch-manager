import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `StashChangesDialog` (src/app/dialogs/
/// StashChangesDialog.cpp). Routed as `/repo/:repoId/dialogs/stash-changes`.
class StashChangesDialogContent extends ConsumerStatefulWidget {
  const StashChangesDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<StashChangesDialogContent> createState() =>
      _StashChangesDialogContentState();
}

class _StashChangesDialogContentState
    extends ConsumerState<StashChangesDialogContent> {
  final TextEditingController _messageController = TextEditingController();
  bool _includeUntracked = false;
  bool _keepIndex = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    return GbmDialogShell(
      title: 'Stash Changes',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Stash',
          kind: GbmButtonKind.primary,
          onPressed: () {
            ref
                .read(repoSessionProvider(widget.identity).notifier)
                .saveStash(
                  _messageController.text.trim(),
                  includeUntracked: _includeUntracked,
                  keepIndex: _keepIndex,
                );
            context.pop();
          },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Message (optional)',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          TextField(
            controller: _messageController,
            decoration: const InputDecoration(
              hintText: 'WIP on main…',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          CheckboxListTile(
            value: _includeUntracked,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Include untracked files',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
            onChanged: (value) =>
                setState(() => _includeUntracked = value ?? false),
          ),
          CheckboxListTile(
            value: _keepIndex,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Keep staged changes in the index',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
            onChanged: (value) => setState(() => _keepIndex = value ?? false),
          ),
        ],
      ),
    );
  }
}
