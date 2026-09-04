import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_input_decoration.dart';

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
      actionId: GbmActionId.branchStashChanges,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
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
            '訊息',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          SizedBox(
            height: GbmSpacing.inputHeight,
            child: TextField(
              controller: _messageController,
              decoration: gbmInputDecoration(
                colors: colors,
                // 「(optional)」 left the label, so the information it
                // carried moves here rather than being dropped -- the spec
                // states it as a hint: 「空白時使用預設的 WIP on <branch>」.
                hintText: '空白時使用預設的 WIP on <branch>',
              ),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          CheckboxListTile(
            value: _includeUntracked,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              '包含 untracked 檔案',
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
              '保留已 stage 的內容在工作區',
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
