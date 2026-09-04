// Integration coverage for the "cancel suddenly" half of the state-machine
// batch: what happens when one of WorkspaceScreen's three auto-pushed
// interrupt dialogs is closed *without* going through its own Cancel
// button -- a barrier tap, a system back gesture, a route change out from
// under it.
//
// All three dialogs carry the same safety net: a `_resolved` bool plus a
// `dispose()` that dispatches the cancel command when the dialog is popped
// unanswered (credential_dialog.dart:36, checkout_recovery_dialog.dart:37,
// delete_branch_recovery_dialog.dart:36). For the credential dialog that
// net is load-bearing -- without it the blocked git subprocess hangs until
// GBM_ASKPASS's own timeout.
//
// That net had no behavioural coverage at any tier before this file.
// workspace_interrupt_overlay_test.dart drives only the Cancel *button*,
// and mentions dispose() solely as a test-authoring hazard ("resolve before
// the test ends"), never as a thing that is asserted to work.
//
// Two properties are pinned per dialog, and the pair only works together:
//
//   * abrupt dismissal dispatches the cancel command EXACTLY ONCE, and
//   * resolving via the button dispatches it EXACTLY ONCE TOO.
//
// The second is what actually pins `_resolved`. Delete that flag and the
// button path fires twice (once from the handler, once from dispose) --
// invisible to a `commandLog.any(...)` assertion, which is why every count
// below goes through `.where(...).length`. `.any` cannot fail on a double
// dispatch.
//
// A third property covers the state machine's re-arm edge: WorkspaceScreen
// pushes each dialog only on the null->non-null (or empty->non-empty)
// transition, so if a dismissal left the field populated the *next* prompt
// would never surface. The fake never mutates state on its own (see
// FakeRepoSessionController's doc comment), so each test emits the cleared
// state explicitly -- exactly what the real controller's cancelCredential()
// does via `copyWith(clearCredentialPrompt: true)` -- and then asserts a
// fresh value re-opens the dialog.
//
// Finder scoping follows workspace_interrupt_overlay_test.dart's header:
// these dialogs are non-opaque (dialog_route.dart's `opaque: false`), so the
// WorkspaceScreen underneath stays mounted and a bare `find.text(...)` is
// ambiguous.
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

import '../support/fake_repo_session.dart';
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

// The wire carries only `kind`/`destructive` -- both recovery dialogs
// compose their copy in Dart from `kind` (`recovery_choice_copy.dart`).
// `_tapActionButton` calls below use those composed labels ("Stash and
// checkout" / "Delete anyway").
const List<OperationChoice> _checkoutChoices = <OperationChoice>[
  OperationChoice(kind: OperationChoiceKind.stashAndRetry, destructive: false),
];

const List<OperationChoice> _deleteBranchChoices = <OperationChoice>[
  OperationChoice(kind: OperationChoiceKind.forceDiscard, destructive: true),
];

/// Closes the topmost dialog the way a user who never touched its buttons
/// would: a tap on the modal barrier (`dialogRoute`'s
/// `barrierDismissible: true`). The offset is the top-left corner, which is
/// always barrier rather than dialog -- GbmDialogShell is centred.
///
/// This is the real gesture, so it is what the tests use. `router.pop()`
/// reaches the same `dispose()`-with-`_resolved == false` path and is the
/// recorded fallback if a future Flutter/go_router version stops honouring
/// `barrierDismissible` on a `CustomTransitionPage`.
Future<void> _dismissViaBarrier(WidgetTester tester) async {
  await tester.tapAt(const Offset(10, 10));
  await tester.pumpAndSettle();
}

/// Taps the action-bar [GbmButton] carrying [label] -- not the matching
/// plain-text row the recovery dialogs repeat in their body.
Future<void> _tapActionButton(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(GbmButton, label));
  await tester.pumpAndSettle();
}

int _countOf(FakeRepoSessionController controller, String name) =>
    controller.commandLog.where((c) => c.name == name).length;

void main() {
  group('credential dialog -- abrupt dismissal', () {
    testWidgets(
      'a barrier tap pops the dialog and dispatches cancelCredential exactly '
      'once',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _interruptDialogRoutes,
        );

        pumped.controller.emit(
          pumped.controller.state.copyWith(credentialPrompt: 'Username'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CredentialDialogContent), findsOneWidget);

        await _dismissViaBarrier(tester);

        expect(find.byType(CredentialDialogContent), findsNothing);
        expect(
          _countOf(pumped.controller, 'cancelCredential'),
          1,
          reason:
              'CredentialDialogContent.dispose() must treat an unanswered '
              'pop as a Cancel, otherwise the blocked git subprocess hangs '
              "until GBM_ASKPASS's own timeout.",
        );
      },
    );

    testWidgets(
      'resolving via the Cancel button dispatches cancelCredential exactly '
      'once -- dispose must not fire a second copy',
      (tester) async {
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
          _countOf(pumped.controller, 'cancelCredential'),
          1,
          reason:
              'The `_resolved` flag exists precisely to stop dispose() from '
              'repeating what the button already dispatched. Removing it '
              'would answer the same askpass handshake twice.',
        );
      },
    );

    testWidgets(
      'Submit then dispose: provideCredential once, no stray cancelCredential',
      (tester) async {
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

        expect(_countOf(pumped.controller, 'provideCredential'), 1);
        expect(
          _countOf(pumped.controller, 'cancelCredential'),
          0,
          reason:
              'An answered prompt must not also be cancelled on the way out '
              '-- that would tell the capi to abandon a handshake it has '
              'already been given a secret for.',
        );
      },
    );

    testWidgets(
      're-arm: after an abrupt dismissal a fresh prompt opens the dialog '
      'again',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _interruptDialogRoutes,
        );

        pumped.controller.emit(
          pumped.controller.state.copyWith(credentialPrompt: 'Username'),
        );
        await tester.pumpAndSettle();
        await _dismissViaBarrier(tester);

        // What the real cancelCredential() publishes (repo_session_
        // repository.dart:2208). The fake records instead of mutating, so
        // the test stands in for it.
        pumped.controller.emit(
          pumped.controller.state.copyWith(clearCredentialPrompt: true),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CredentialDialogContent), findsNothing);

        pumped.controller.emit(
          pumped.controller.state.copyWith(credentialPrompt: 'Password'),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(CredentialDialogContent),
          findsOneWidget,
          reason:
              'WorkspaceScreen pushes this dialog only on the null -> '
              'non-null edge, so a dismissal that left credentialPrompt '
              'populated would silence every later prompt.',
        );

        await _tapActionButton(tester, 'Cancel');
      },
    );
  });

  group('checkout recovery dialog -- abrupt dismissal', () {
    testWidgets(
      'a barrier tap pops the dialog and dispatches dismissCheckoutChoices '
      'exactly once',
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
        expect(find.byType(CheckoutRecoveryDialogContent), findsOneWidget);

        await _dismissViaBarrier(tester);

        expect(find.byType(CheckoutRecoveryDialogContent), findsNothing);
        expect(_countOf(pumped.controller, 'dismissCheckoutChoices'), 1);
      },
    );

    testWidgets(
      'resolving via Cancel dispatches dismissCheckoutChoices exactly once',
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

        expect(_countOf(pumped.controller, 'dismissCheckoutChoices'), 1);
      },
    );

    testWidgets(
      'picking a choice retries once and does not also dismiss on the way out',
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

        await _tapActionButton(tester, 'Stash and checkout');

        expect(_countOf(pumped.controller, 'retryCheckoutWithChoice'), 1);
        expect(
          _countOf(pumped.controller, 'dismissCheckoutChoices'),
          0,
          reason:
              'A retry in flight must not be followed by a dismiss -- the '
              'controller would drop the choices the retry is still using.',
        );
      },
    );

    testWidgets(
      're-arm: a second refused checkout re-opens the recovery dialog',
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
        await _dismissViaBarrier(tester);

        pumped.controller.emit(
          pumped.controller.state.copyWith(
            checkoutChoices: const <OperationChoice>[],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CheckoutRecoveryDialogContent), findsNothing);

        pumped.controller.emit(
          pumped.controller.state.copyWith(checkoutChoices: _checkoutChoices),
        );
        await tester.pumpAndSettle();

        expect(find.byType(CheckoutRecoveryDialogContent), findsOneWidget);

        await _tapActionButton(tester, 'Cancel');
      },
    );
  });

  group('delete-branch recovery dialog -- abrupt dismissal', () {
    testWidgets('a barrier tap pops the dialog and dispatches '
        'dismissDeleteBranchChoices exactly once', (tester) async {
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
      expect(find.byType(DeleteBranchRecoveryDialogContent), findsOneWidget);

      await _dismissViaBarrier(tester);

      expect(find.byType(DeleteBranchRecoveryDialogContent), findsNothing);
      expect(_countOf(pumped.controller, 'dismissDeleteBranchChoices'), 1);
    });

    testWidgets(
      'resolving via Cancel dispatches dismissDeleteBranchChoices exactly '
      'once',
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

        expect(_countOf(pumped.controller, 'dismissDeleteBranchChoices'), 1);
      },
    );

    testWidgets(
      'Force delete retries once and does not also dismiss on the way out',
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

        await _tapActionButton(tester, 'Delete anyway');

        expect(_countOf(pumped.controller, 'retryDeleteBranchWithChoice'), 1);
        expect(_countOf(pumped.controller, 'dismissDeleteBranchChoices'), 0);
      },
    );

    testWidgets(
      're-arm: a second refused delete re-opens the recovery dialog',
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
        await _dismissViaBarrier(tester);

        pumped.controller.emit(
          pumped.controller.state.copyWith(
            deleteBranchChoices: const <OperationChoice>[],
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(DeleteBranchRecoveryDialogContent), findsNothing);

        pumped.controller.emit(
          pumped.controller.state.copyWith(
            deleteBranchChoices: _deleteBranchChoices,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(DeleteBranchRecoveryDialogContent), findsOneWidget);

        await _tapActionButton(tester, 'Cancel');
      },
    );
  });
}
