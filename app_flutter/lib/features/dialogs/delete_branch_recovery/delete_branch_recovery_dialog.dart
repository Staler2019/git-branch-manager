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

/// The Dart analog of the "not fully merged" recovery prompt
/// `DeleteBranchOperation` produces (src/core/git/ops/BranchOps.cpp): a
/// friendly explanation of why the delete was refused (drawn from
/// [RepoSessionState.lastError.message], not a choice's own text), plus a
/// "Delete anyway" choice when the branch is genuinely unmerged -- button
/// wording per `recovery_choice_copy.dart`, not read off the wire. Mirrors
/// [CheckoutRecoveryDialogContent]'s auto-open pattern exactly, just for
/// [RepoSessionState.deleteBranchChoices] instead of `checkoutChoices` --
/// routed as `/repo/:repoId/dialogs/delete-branch-recovery`, pushed
/// automatically by `workspace_screen.dart`.
class DeleteBranchRecoveryDialogContent extends ConsumerStatefulWidget {
  const DeleteBranchRecoveryDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<DeleteBranchRecoveryDialogContent> createState() =>
      _DeleteBranchRecoveryDialogContentState();
}

class _DeleteBranchRecoveryDialogContentState
    extends ConsumerState<DeleteBranchRecoveryDialogContent> {
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
      _session.dismissDeleteBranchChoices();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<OperationChoice> choices = ref.watch(
      repoSessionProvider(
        widget.identity,
      ).select((state) => state.deleteBranchChoices),
    );
    final String? message = ref.watch(
      repoSessionProvider(
        widget.identity,
      ).select((state) => state.lastError?.message),
    );

    return GbmDialogShell(
      title: 'Delete Blocked',
      actions: <Widget>[
        GbmButton(
          label: 'Cancel',
          onPressed: () {
            _resolved = true;
            ref
                .read(repoSessionProvider(widget.identity).notifier)
                .dismissDeleteBranchChoices();
            context.pop();
          },
        ),
        for (final choice in choices.where(
          (c) => c.kind != OperationChoiceKind.abort,
        )) ...<Widget>[
          const SizedBox(width: GbmSpacing.space2),
          GbmButton(
            label: recoveryChoiceLabel(choice.kind, forDeleteBranch: true),
            kind: choice.destructive
                ? GbmButtonKind.secondary
                : GbmButtonKind.primary,
            onPressed: () {
              _resolved = true;
              ref
                  .read(repoSessionProvider(widget.identity).notifier)
                  .retryDeleteBranchWithChoice(choice.kind);
              context.pop();
            },
          ),
        ],
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (message != null && message.isNotEmpty) ...<Widget>[
            Text(
              message,
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
                    recoveryChoiceLabel(choice.kind, forDeleteBranch: true),
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
                      forDeleteBranch: true,
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
