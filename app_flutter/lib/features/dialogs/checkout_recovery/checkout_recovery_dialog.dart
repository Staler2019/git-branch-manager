import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/operation_choice.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of the recovery prompt `MainWindow::checkoutBranch()`
/// shows when a checkout is refused on a dirty work tree (src/app/views/
/// MainWindow.cpp's `OperationChoice` handling): "Stash changes and
/// checkout" / "Discard changes and checkout" / Cancel, rather than a raw
/// Git error. Routed as `/repo/:repoId/dialogs/checkout-recovery`, pushed
/// automatically by `workspace_screen.dart` whenever
/// [RepoSessionState.checkoutChoices] goes from empty to non-empty --
/// mirrors [CredentialDialogContent]'s auto-open pattern, since this is
/// also not something the user chose to open.
class CheckoutRecoveryDialogContent extends ConsumerStatefulWidget {
  const CheckoutRecoveryDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<CheckoutRecoveryDialogContent> createState() =>
      _CheckoutRecoveryDialogContentState();
}

class _CheckoutRecoveryDialogContentState
    extends ConsumerState<CheckoutRecoveryDialogContent> {
  bool _resolved = false;

  @override
  void dispose() {
    if (!_resolved) {
      ref
          .read(repoSessionProvider(widget.identity).notifier)
          .dismissCheckoutChoices();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<OperationChoice> choices = ref.watch(
      repoSessionProvider(
        widget.identity,
      ).select((state) => state.checkoutChoices),
    );

    return GbmDialogShell(
      title: 'Checkout Blocked',
      actions: <Widget>[
        GbmButton(
          label: 'Cancel',
          onPressed: () {
            _resolved = true;
            ref
                .read(repoSessionProvider(widget.identity).notifier)
                .dismissCheckoutChoices();
            context.pop();
          },
        ),
        for (final choice in choices.where(
          (c) => c.kind != OperationChoiceKind.abort,
        )) ...<Widget>[
          const SizedBox(width: GbmSpacing.space2),
          GbmButton(
            label: choice.label,
            kind: choice.destructive
                ? GbmButtonKind.secondary
                : GbmButtonKind.primary,
            onPressed: () {
              _resolved = true;
              ref
                  .read(repoSessionProvider(widget.identity).notifier)
                  .retryCheckoutWithChoice(choice.kind);
              context.pop();
            },
          ),
        ],
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'This checkout needs uncommitted changes out of the way first.',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space3),
          for (final choice in choices)
            Padding(
              padding: const EdgeInsets.only(bottom: GbmSpacing.space2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    choice.label,
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      fontWeight: GbmTypography.weightMedium,
                      color: choice.destructive
                          ? colors.danger
                          : colors.textPrimary,
                    ),
                  ),
                  if (choice.explanation.isNotEmpty)
                    Text(
                      choice.explanation,
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
