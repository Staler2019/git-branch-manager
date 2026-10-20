import 'package:flutter/material.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';
import '../../../widgets/gbm_input_decoration.dart';

/// The credential prompt both askpass owners draw: a repository session's
/// (`CredentialDialogContent`) and a clone job's
/// (`CloneCredentialDialogContent`). Who answers is the caller's; what is
/// shown, and what is masked, is decided here once.
class CredentialFormBody extends StatelessWidget {
  const CredentialFormBody({
    super.key,
    required this.prompt,
    required this.controller,
    required this.onSubmit,
    required this.onCancel,
  });

  /// git's own prompt text, as asked.
  final String prompt;
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    // Masked unless this is git's own Username prompt. Matching "password"
    // instead left an SSH key passphrase ("Enter passphrase for key …") in
    // plain sight; a prompt nobody recognises is safer hidden.
    final bool obscure = !prompt.startsWith('Username for');

    return GbmDialogShell(
      title: 'Credentials Required',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: onCancel),
        GbmButton(
          label: 'Submit',
          kind: GbmButtonKind.primary,
          onPressed: onSubmit,
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            liveRegion: true,
            child: Text(
              prompt,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          Text(
            obscure ? 'Token / 密碼' : '帳號',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space1),
          SizedBox(
            height: GbmSpacing.inputHeight,
            child: TextField(
              key: const Key('credential-secret-field'),
              controller: controller,
              obscureText: obscure,
              autofocus: true,
              onSubmitted: (_) => onSubmit(),
              decoration: gbmInputDecoration(colors: colors),
            ),
          ),
        ],
      ),
    );
  }
}
