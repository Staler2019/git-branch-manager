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
import '../recovery_choice_copy.dart';

/// The Dart analog of the recovery prompt shown when a checkout is refused,
/// whether on a dirty work tree (`CheckoutOp.cpp`'s own `OperationChoice`s:
/// "Stash and checkout" / "Discard and checkout" / Cancel) or by
/// `OperationRunner::preflight()` (an index.lock or an in-progress
/// sequencer operation, shared with every other submission -- see
/// `OperationRunner.cpp`'s `workerLoop()`): "Retry" / "Remove index.lock" /
/// Cancel. Button wording per `recovery_choice_copy.dart`, not read off the
/// wire; the body's intro sentence switches between a fixed Chinese
/// sentence (dirty-tree case) and core's own [RepoSessionState.lastError]
/// message (preflight case), keyed on which choice kinds are present --
/// see the `isDirtyWorkTreeRefusal` local below. Routed as
/// `/repo/:repoId/dialogs/checkout-recovery`, pushed automatically by
/// `workspace_screen.dart` whenever [RepoSessionState.checkoutChoices] goes
/// from empty to non-empty -- mirrors [CredentialDialogContent]'s auto-open
/// pattern, since this is also not something the user chose to open.
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
    if (!_resolved && _session.mounted) {
      _session.dismissCheckoutChoices();
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
    // `checkoutChoices` is populated by two different refusals sharing one
    // field (CheckoutOp.cpp's dirty-work-tree case, and OperationRunner's
    // preflight() -- an index.lock or an in-progress sequencer operation --
    // see [STATE-refresh-entry-point]'s "preflight runs before every
    // submission" and OperationRunner.cpp's workerLoop()). Only the dirty
    // case is what the hardcoded Chinese sentence below describes; a
    // stashAndRetry/forceDiscard choice is CheckoutOp.cpp's own signature,
    // present only on that path.
    final bool isDirtyWorkTreeRefusal = choices.any(
      (choice) =>
          choice.kind == OperationChoiceKind.stashAndRetry ||
          choice.kind == OperationChoiceKind.forceDiscard,
    );
    // For the other path, core's own message is what's accurate --
    // "Another Git process appears to be running" / "Finish or abort the
    // operation in progress first" -- the same field
    // DeleteBranchRecoveryDialogContent already reads unconditionally.
    final String? coreMessage = isDirtyWorkTreeRefusal
        ? null
        : ref.watch(
            repoSessionProvider(
              widget.identity,
            ).select((state) => state.lastError?.message),
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
          GbmButton(
            label: recoveryChoiceLabel(choice.kind, forDeleteBranch: false),
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
          if (isDirtyWorkTreeRefusal) ...<Widget>[
            Text(
              '這次 checkout 得先把未提交的變更挪開。',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space3),
          ] else if (coreMessage != null && coreMessage.isNotEmpty) ...<Widget>[
            Text(
              coreMessage,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: GbmSpacing.space3),
          ],
          // Filtered the same way the button row above is -- `abort` has no
          // button here (Cancel is the hardcoded one in `actions`), so
          // drawing its label/explanation again in this list duplicated it.
          for (final choice in choices.where(
            (c) => c.kind != OperationChoiceKind.abort,
          ))
            Padding(
              padding: const EdgeInsets.only(bottom: GbmSpacing.space2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    recoveryChoiceLabel(choice.kind, forDeleteBranch: false),
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      fontWeight: GbmTypography.weightMedium,
                      color: choice.destructive
                          ? colors.danger
                          : colors.textPrimary,
                    ),
                  ),
                  Text(
                    recoveryChoiceExplanation(
                      choice.kind,
                      forDeleteBranch: false,
                    ),
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
