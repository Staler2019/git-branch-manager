// Integration coverage for WorkspaceScreen's three "not something the user
// chose to open" auto-push dialogs (see its ref.listen block:
// credentialPrompt / checkoutChoices / deleteBranchChoices). Each is a
// state-machine transition in its own right -- null/empty -> non-null/
// non-empty pushes exactly once, and the dialog resolving (provide/cancel,
// retry/dismiss) pops back to a clean WorkspaceScreen with the field
// cleared, matching CredentialDialogContent/CheckoutRecoveryDialogContent/
// DeleteBranchRecoveryDialogContent's own doc comments.
//
// The three dialog routes are registered as top-level siblings of the
// ShellRoute in the real router (app_router.dart's `dialogRoute(...)`
// calls), not ShellRoute children -- see pumpWorkspace's `topLevelRoutes`
// doc comment for why `extraRoutes` would be the wrong param here.
//
// Every find below is scoped to inside the dialog's content widget rather
// than a bare `find.text(...)`/`find.byType(TextField)`: these dialogs are
// non-opaque overlays (dialog_route.dart's `opaque: false`), so the
// WorkspaceScreen underneath -- with its own branch-filter TextField in
// SidebarPanel and its own "Cancel"-adjacent labels -- stays mounted behind
// them, and each recovery dialog's body independently repeats every
// choice's label as plain text alongside the action-bar button carrying the
// same label (CheckoutRecoveryDialogContent/DeleteBranchRecoveryDialogContent
// both render `choice.label` twice: once as a GbmButton, once in the
// choice-detail list) -- a bare `find.text(...)` is ambiguous either way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_choice.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/dialogs/checkout_recovery/checkout_recovery_dialog.dart';
import 'package:gbm_flutter/features/dialogs/credential/credential_dialog.dart';
import 'package:gbm_flutter/features/dialogs/delete_branch_recovery/delete_branch_recovery_dialog.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

final List<RouteBase> _interruptDialogRoutes = <RouteBase>[
  dialogRoute(
    path: RoutePaths.credentialDialog,
    builder: (context, state) => CredentialDialogContent(identity: _identity),
  ),
  dialogRoute(
    path: RoutePaths.checkoutRecoveryDialog,
    builder: (context, state) =>
        CheckoutRecoveryDialogContent(identity: _identity),
  ),
  dialogRoute(
    path: RoutePaths.deleteBranchRecoveryDialog,
    builder: (context, state) =>
        DeleteBranchRecoveryDialogContent(identity: _identity),
  ),
];

// Kept short deliberately -- GbmDialogShell's action row (gbm_dialog_shell
// .dart:91) has no overflow handling, and a long label alongside "Cancel"
// inside its fixed ~448px width does overflow (a real, pre-existing layout
// gap, not something this test batch is scoped to fix; see CLAUDE.md's
// Known gaps note).
const List<OperationChoice> _checkoutChoices = <OperationChoice>[
  OperationChoice(
    kind: OperationChoiceKind.stashAndRetry,
    label: 'Stash & checkout',
    explanation: '',
    destructive: false,
  ),
];

const List<OperationChoice> _deleteBranchChoices = <OperationChoice>[
  OperationChoice(
    kind: OperationChoiceKind.forceDiscard,
    label: 'Force delete',
    explanation: 'This branch is not fully merged.',
    destructive: true,
  ),
];

/// Taps the action-bar [GbmButton] carrying [label] -- not the matching
/// plain-text row in the dialog body, which repeats the same label (see
/// this file's header comment).
Future<void> _tapActionButton(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(GbmButton, label));
  await tester.pumpAndSettle();
}

void main() {
  group('workspace interrupt overlays', () {
    testWidgets(
      'credentialPrompt null -> non-null auto-pushes the credential dialog '
      'exactly once; a further non-null value does not push a second copy',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _interruptDialogRoutes,
        );

        expect(find.byType(CredentialDialogContent), findsNothing);

        pumped.controller.emit(
          pumped.controller.state.copyWith(credentialPrompt: 'Username'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CredentialDialogContent), findsOneWidget);

        // Still non-null (previous non-null too) -- must not push again.
        pumped.controller.emit(
          pumped.controller.state.copyWith(credentialPrompt: 'Password'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CredentialDialogContent), findsOneWidget);

        // Resolve before the test ends -- CredentialDialogContent.dispose()
        // calls cancelCredential() via `ref` when popped unanswered, which
        // throws if it fires after pumpWorkspace's ProviderContainer is
        // already disposed by addTearDown. Every other test below resolves
        // its dialog before finishing for the same reason.
        await _tapActionButton(tester, 'Cancel');
      },
    );

    testWidgets('Submit dispatches provideCredential and pops the dialog', (
      tester,
    ) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        topLevelRoutes: _interruptDialogRoutes,
      );

      pumped.controller.emit(
        pumped.controller.state.copyWith(credentialPrompt: 'Username'),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.descendant(
          of: find.byType(CredentialDialogContent),
          matching: find.byType(TextField),
        ),
        'octocat',
      );
      await _tapActionButton(tester, 'Submit');

      expect(
        pumped.controller.commandLog.any((c) => c.name == 'provideCredential'),
        isTrue,
      );
      expect(find.byType(CredentialDialogContent), findsNothing);
    });

    testWidgets('Cancel dispatches cancelCredential and pops the dialog', (
      tester,
    ) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        topLevelRoutes: _interruptDialogRoutes,
      );

      pumped.controller.emit(
        pumped.controller.state.copyWith(credentialPrompt: 'Username'),
      );
      await tester.pumpAndSettle();

      await _tapActionButton(tester, 'Cancel');

      expect(
        pumped.controller.commandLog.any((c) => c.name == 'cancelCredential'),
        isTrue,
      );
      expect(find.byType(CredentialDialogContent), findsNothing);
    });

    testWidgets(
      'checkoutChoices empty -> non-empty auto-pushes the recovery dialog; '
      'picking a choice dispatches retryCheckoutWithChoice and pops',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _interruptDialogRoutes,
        );

        expect(find.byType(CheckoutRecoveryDialogContent), findsNothing);

        pumped.controller.emit(
          pumped.controller.state.copyWith(checkoutChoices: _checkoutChoices),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CheckoutRecoveryDialogContent), findsOneWidget);

        await _tapActionButton(tester, 'Stash & checkout');

        expect(
          pumped.controller.commandLog.any(
            (c) =>
                c.name == 'retryCheckoutWithChoice' &&
                c.args['kind'] == OperationChoiceKind.stashAndRetry,
          ),
          isTrue,
        );
        expect(find.byType(CheckoutRecoveryDialogContent), findsNothing);
      },
    );

    testWidgets(
      'checkout recovery Cancel dispatches dismissCheckoutChoices and pops',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _interruptDialogRoutes,
        );

        pumped.controller.emit(
          pumped.controller.state.copyWith(checkoutChoices: _checkoutChoices),
        );
        await tester.pumpAndSettle();

        await _tapActionButton(tester, 'Cancel');

        expect(
          pumped.controller.commandLog.any(
            (c) => c.name == 'dismissCheckoutChoices',
          ),
          isTrue,
        );
        expect(find.byType(CheckoutRecoveryDialogContent), findsNothing);
      },
    );

    testWidgets(
      'deleteBranchChoices empty -> non-empty auto-pushes the recovery '
      'dialog; Force delete dispatches retryDeleteBranchWithChoice and pops',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _interruptDialogRoutes,
        );

        expect(find.byType(DeleteBranchRecoveryDialogContent), findsNothing);

        pumped.controller.emit(
          pumped.controller.state.copyWith(
            deleteBranchChoices: _deleteBranchChoices,
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DeleteBranchRecoveryDialogContent), findsOneWidget);

        await _tapActionButton(tester, 'Force delete');

        expect(
          pumped.controller.commandLog.any(
            (c) =>
                c.name == 'retryDeleteBranchWithChoice' &&
                c.args['kind'] == OperationChoiceKind.forceDiscard,
          ),
          isTrue,
        );
        expect(find.byType(DeleteBranchRecoveryDialogContent), findsNothing);
      },
    );

    testWidgets(
      'delete-branch recovery Cancel dispatches dismissDeleteBranchChoices '
      'and pops',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _interruptDialogRoutes,
        );

        pumped.controller.emit(
          pumped.controller.state.copyWith(
            deleteBranchChoices: _deleteBranchChoices,
          ),
        );
        await tester.pumpAndSettle();

        await _tapActionButton(tester, 'Cancel');

        expect(
          pumped.controller.commandLog.any(
            (c) => c.name == 'dismissDeleteBranchChoices',
          ),
          isTrue,
        );
        expect(find.byType(DeleteBranchRecoveryDialogContent), findsNothing);
      },
    );
  });
}
