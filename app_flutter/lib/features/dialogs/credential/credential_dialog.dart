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
  ConsumerState<CredentialDialogContent> createState() =>
      _CredentialDialogContentState();
}

class _CredentialDialogContentState
    extends ConsumerState<CredentialDialogContent> {
  final TextEditingController _secretController = TextEditingController();
  bool _resolved = false;

  /// Captured up front because [dispose] cannot reach `ref`: by the time
  /// `State.dispose()` runs the element is already unmounted, and
  /// flutter_riverpod gates every `ref` member on `context.mounted`
  /// (`ConsumerStatefulElement._assertNotDisposed`). A `ref.read(...)` there
  /// therefore throws `StateError: Cannot use "ref" after the widget was
  /// disposed` **unconditionally** -- which silently broke the
  /// dispatch-on-the-way-out below for as long as it existed. Holding the
  /// notifier is the supported way to dispatch during disposal.
  late final RepoSessionController _session;

  @override
  void initState() {
    super.initState();
    _session = ref.read(repoSessionProvider(widget.identity).notifier);
  }

  @override
  void dispose() {
    // Popped some other way (e.g. Esc via the barrier) without answering --
    // treat that the same as Cancel, so the blocked git subprocess does not
    // hang until GBM_ASKPASS's own timeout.
    if (!_resolved && _session.mounted) {
      _session.cancelCredential();
    }
    _secretController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String prompt =
        ref.watch(
          repoSessionProvider(
            widget.identity,
          ).select((state) => state.credentialPrompt),
        ) ??
        '';
    final bool obscure = prompt.toLowerCase().contains('password');

    return GbmDialogShell(
      title: 'Credentials Required',
      actions: <Widget>[
        GbmButton(
          label: 'Cancel',
          onPressed: () {
            _resolved = true;
            ref
                .read(repoSessionProvider(widget.identity).notifier)
                .cancelCredential();
            context.pop();
          },
        ),
        GbmButton(
          label: 'Submit',
          kind: GbmButtonKind.primary,
          onPressed: () {
            _resolved = true;
            ref
                .read(repoSessionProvider(widget.identity).notifier)
                .provideCredential(_secretController.text);
            context.pop();
          },
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
          SizedBox(
            height: GbmSpacing.inputHeight,
            child: TextField(
              controller: _secretController,
              obscureText: obscure,
              autofocus: true,
              onSubmitted: (_) {
                _resolved = true;
                ref
                    .read(repoSessionProvider(widget.identity).notifier)
                    .provideCredential(_secretController.text);
                context.pop();
              },
              decoration: gbmInputDecoration(
                colors: colors,
                labelText: obscure ? 'Token / 密碼' : '帳號',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
