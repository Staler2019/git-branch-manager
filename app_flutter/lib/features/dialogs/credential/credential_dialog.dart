import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `CredentialDialog` (src/app/dialogs/
/// CredentialDialog.cpp), the askpass UI half of gbm_capi's credential
/// handshake -- see GBM_EVENT_CREDENTIAL_REQUESTED's doc comment in
/// gbm_capi.h. Routed as `/repo/:repoId/dialogs/credential`, pushed
/// automatically by `workspace_screen.dart` whenever
/// [RepoSessionState.credentialPrompt] goes from null to non-null, and
/// popped by this dialog itself once answered or cancelled (not by the
/// controller going back to null -- see [dispose]).
class CredentialDialogContent extends ConsumerStatefulWidget {
  const CredentialDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<CredentialDialogContent> createState() => _CredentialDialogContentState();
}

class _CredentialDialogContentState extends ConsumerState<CredentialDialogContent> {
  final TextEditingController _secretController = TextEditingController();
  bool _resolved = false;

  @override
  void dispose() {
    // Popped some other way (e.g. Esc via the barrier) without answering --
    // treat that the same as Cancel, so the blocked git subprocess does not
    // hang until GBM_ASKPASS's own timeout.
    if (!_resolved) {
      ref.read(repoSessionProvider(widget.identity).notifier).cancelCredential();
    }
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String prompt = ref.watch(repoSessionProvider(widget.identity).select((state) => state.credentialPrompt)) ?? '';
    final bool obscure = prompt.toLowerCase().contains('password');

    return GbmDialogShell(
      title: 'Credentials Required',
      actions: <Widget>[
        GbmButton(
          label: 'Cancel',
          onPressed: () {
            _resolved = true;
            ref.read(repoSessionProvider(widget.identity).notifier).cancelCredential();
            context.pop();
          },
        ),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Submit',
          kind: GbmButtonKind.primary,
          onPressed: () {
            _resolved = true;
            ref.read(repoSessionProvider(widget.identity).notifier).provideCredential(_secretController.text);
            context.pop();
          },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(prompt, style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textSecondary)),
          const SizedBox(height: GbmSpacing.space2),
          TextField(
            controller: _secretController,
            obscureText: obscure,
            autofocus: true,
            onSubmitted: (_) {
              _resolved = true;
              ref.read(repoSessionProvider(widget.identity).notifier).provideCredential(_secretController.text);
              context.pop();
            },
            decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          ),
        ],
      ),
    );
  }
}
