import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_input_decoration.dart';

/// The Dart analog of `CreateTagDialog` (src/app/dialogs/
/// CreateTagDialog.cpp). Routed as `/repo/:repoId/dialogs/create-tag`.
class CreateTagDialogContent extends ConsumerStatefulWidget {
  const CreateTagDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<CreateTagDialogContent> createState() =>
      _CreateTagDialogContentState();
}

class _CreateTagDialogContentState
    extends ConsumerState<CreateTagDialogContent> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  bool _force = false;

  @override
  void dispose() {
    _nameController.dispose();
    _targetController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String name = _nameController.text.trim();

    return GbmDialogShell(
      title: 'Create Tag',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        GbmButton(
          label: 'Create',
          kind: GbmButtonKind.primary,
          onPressed: name.isEmpty
              ? null
              : () {
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .createTag(
                        name,
                        target: _targetController.text.trim(),
                        message: _messageController.text.trim(),
                        force: _force,
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
            '名稱',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          SizedBox(
            height: GbmSpacing.inputHeight,
            child: TextField(
              controller: _nameController,
              onChanged: (_) => setState(() {}),
              decoration: gbmInputDecoration(
                colors: colors,
                hintText: 'v1.0.0',
              ),
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          Text(
            '指向',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          SizedBox(
            height: GbmSpacing.inputHeight,
            child: TextField(
              controller: _targetController,
              decoration: gbmInputDecoration(
                colors: colors,
                hintText: '留空表示 HEAD',
              ),
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          Text(
            '訊息',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          TextField(
            controller: _messageController,
            maxLines: 2,
            decoration: gbmMultilineInputDecoration(
              colors: colors,
              hintText: '留空則建立 lightweight tag',
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          CheckboxListTile(
            value: _force,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              '覆蓋同名的既有 tag（-f）',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
            onChanged: (value) => setState(() => _force = value ?? false),
          ),
        ],
      ),
    );
  }
}
