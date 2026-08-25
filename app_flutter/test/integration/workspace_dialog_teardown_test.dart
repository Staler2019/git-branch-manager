// Integration coverage for what happens to an interrupt dialog when the
// thing underneath it moves: the state it was opened for resolves itself,
// or the route it sits on is replaced.
//
// These are the two "sudden" endings that are not a user gesture on the
// dialog at all, and each pins a decision that is easy to get backwards:
//
//   * A dialog does NOT close just because its backing field went null.
//     CredentialDialogContent's doc comment is explicit that the dialog
//     pops itself once answered or cancelled, "not by the controller going
//     back to null" -- a credential handshake routinely clears and re-sets
//     the prompt for the follow-up (username, then password), and closing
//     on the intermediate null would blink the dialog away mid-handshake.
//   * A route change out from under an unanswered dialog must still reach
//     the cancel path, or the blocked git subprocess hangs.
//
// Both then have to leave the state machine re-armable: WorkspaceScreen
// pushes each interrupt dialog only on the null->non-null (or
// empty->non-empty) edge, so anything that ends a dialog without the field
// being cleared silences every later prompt.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/credential/credential_dialog.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart'
    show ConflictBanner;
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

final String _repoId = Uri.encodeComponent(_identity.workDir);

final List<RouteBase> _credentialRoute = <RouteBase>[
  dialogRoute(
    path: RoutePaths.credentialDialog,
    builder: (context, state) => CredentialDialogContent(identity: _identity),
  ),
];

const WorkingCopyEntry _conflictEntry = WorkingCopyEntry(
  path: 'conflict.txt',
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.bothModified,
  ancestorBlob: '',
  oursBlob: 'ours-hash',
  theirsBlob: 'theirs-hash',
  similarity: 0,
  isSubmodule: false,
  isConflicted: true,
);

RepoSessionState _cherryPickConflict() => RepoSessionState(
  isOpen: true,
  repoState: const RepoState(
    flags: RepoStateFlags.cherryPick,
    isClean: false,
    isSequencerOperation: true,
    rebaseStep: 1,
    rebaseTotal: 3,
    rebaseOntoLabel: '',
    indexLocked: false,
    indexLockAgeSeconds: null,
    describe: '',
  ),
  workingCopyStatus: const WorkingCopyStatus(
    entries: <WorkingCopyEntry>[_conflictEntry],
  ),
);

int _countOf(FakeRepoSessionController controller, String name) =>
    controller.commandLog.where((c) => c.name == name).length;

Future<void> _pressCtrlShiftF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

void main() {
  group('interrupt dialog vs the state resolving underneath it', () {
    testWidgets('credentialPrompt going back to null leaves the dialog open', (
      tester,
    ) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        topLevelRoutes: _credentialRoute,
      );

      pumped.controller.emit(
        pumped.controller.state.copyWith(credentialPrompt: 'Username'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CredentialDialogContent), findsOneWidget);

      pumped.controller.emit(
        pumped.controller.state.copyWith(clearCredentialPrompt: true),
      );
      await tester.pumpAndSettle();

      expect(
        find.byType(CredentialDialogContent),
        findsOneWidget,
        reason:
            'The dialog pops itself once answered or cancelled, never on '
            'the field clearing -- an askpass handshake clears and re-sets '
            'the prompt between username and password, and auto-closing '
            'would blink the dialog away mid-handshake.',
      );
      expect(
        _countOf(pumped.controller, 'cancelCredential'),
        0,
        reason: 'Nothing has been cancelled yet.',
      );

      await tester.tap(find.widgetWithText(GbmButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(CredentialDialogContent), findsNothing);
      expect(_countOf(pumped.controller, 'cancelCredential'), 1);
    });
  });

  group('interrupt dialog vs the route changing under it', () {
    testWidgets(
      'navigating to another tab pops the dialog and cancels exactly once',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _credentialRoute,
        );

        pumped.controller.emit(
          pumped.controller.state.copyWith(credentialPrompt: 'Username'),
        );
        await tester.pumpAndSettle();
        expect(find.byType(CredentialDialogContent), findsOneWidget);

        pumped.router.go(RoutePaths.workingCopyFor(_repoId));
        await tester.pumpAndSettle();

        expect(find.byType(CredentialDialogContent), findsNothing);
        expect(
          _countOf(pumped.controller, 'cancelCredential'),
          1,
          reason:
              'A dialog torn down by navigation is still an unanswered '
              'prompt; without this the git subprocess waits for '
              "GBM_ASKPASS's timeout.",
        );
      },
    );

    testWidgets(
      're-arm after a navigation teardown: a fresh prompt opens the dialog '
      'again from the new tab',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _credentialRoute,
        );

        pumped.controller.emit(
          pumped.controller.state.copyWith(credentialPrompt: 'Username'),
        );
        await tester.pumpAndSettle();
        pumped.router.go(RoutePaths.workingCopyFor(_repoId));
        await tester.pumpAndSettle();

        // What the real cancelCredential() publishes; the fake records
        // rather than mutating, so the test stands in for it.
        pumped.controller.emit(
          pumped.controller.state.copyWith(clearCredentialPrompt: true),
        );
        await tester.pumpAndSettle();

        pumped.controller.emit(
          pumped.controller.state.copyWith(credentialPrompt: 'Password'),
        );
        await tester.pumpAndSettle();

        expect(
          find.byType(CredentialDialogContent),
          findsOneWidget,
          reason:
              'The auto-push listener lives on WorkspaceScreen, which is the '
              'ShellRoute builder and survives the tab change -- so the '
              'null -> non-null edge must still fire from the new tab.',
        );

        await tester.tap(find.widgetWithText(GbmButton, 'Cancel'));
        await tester.pumpAndSettle();
      },
    );
  });

  group('conflict state vs tab changes', () {
    testWidgets(
      'the banner and its gates survive a History <-> Working Copy round '
      'trip with no residue',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _cherryPickConflict(),
        );

        expect(find.byType(ConflictBanner), findsOneWidget);
        await _pressCtrlShiftF(tester);
        expect(
          _countOf(pumped.controller, 'fetchRemote'),
          0,
          reason: 'Fetch is gated off mid-conflict (spec page 07 STATES).',
        );

        pumped.router.go(RoutePaths.workingCopyFor(_repoId));
        await tester.pumpAndSettle();

        expect(
          find.byType(ConflictBanner),
          findsOneWidget,
          reason:
              'The banner is rendered by the shell, not the tab, so it must '
              'neither vanish nor duplicate across a tab change.',
        );
        await _pressCtrlShiftF(tester);
        expect(_countOf(pumped.controller, 'fetchRemote'), 0);

        pumped.router.go(RoutePaths.historyFor(_repoId));
        await tester.pumpAndSettle();
        expect(find.byType(ConflictBanner), findsOneWidget);

        // And the gate lifts on the way back out, from whichever tab.
        pumped.controller.emit(const RepoSessionState(isOpen: true));
        await tester.pumpAndSettle();

        expect(find.byType(ConflictBanner), findsNothing);
        await _pressCtrlShiftF(tester);
        expect(
          _countOf(pumped.controller, 'fetchRemote'),
          1,
          reason:
              'Clean again: the shortcut must work, or the conflict gate has '
              'left residue behind.',
        );
      },
    );
  });
}
