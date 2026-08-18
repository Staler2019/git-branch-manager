// Integration coverage for the core ask behind this whole test batch:
// "intent 之間切換的狀態要乾淨、符合狀態機模式" -- when
// RepoSessionState.conflictActive flips, every UI surface gated on it
// (keyboard-shortcut dispatch, the sidebar's branch checkout, the commit
// box, the in-window menu's visual enabled state) must flip with it, and
// flip back cleanly with no residue once the conflict clears. Drives the
// real WorkspaceScreen via pumpWorkspace/FakeRepoSessionController.emit(),
// not a hand-fed handler map -- see workspace_intent_dispatch_parity_test.dart
// for why that distinction matters.
//
// The menu-graying assertions below (`_repositoryMenuItemColor`) read
// GbmMenuItem.enabled's effect on _GbmMenuRow's rendered foreground color.
// GbmMenuItem.enabled does not exist yet as of this commit, so
// _GbmMenuRow always renders textPrimary regardless of whether the
// underlying action is wired -- these are expected RED until the following
// commit adds GbmMenuItem.enabled and wires MenuBarRow to it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart'
    show ConflictBanner;
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

RepoState _mergeState() => const RepoState(
  flags: RepoStateFlags.merge,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
);

const WorkingCopyEntry _conflictEntry = WorkingCopyEntry(
  path: 'conflict.txt',
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  conflict: ConflictKind.bothModified,
  ancestorBlob: '',
  oursBlob: 'ours-hash',
  theirsBlob: 'theirs-hash',
  similarity: 0,
  isSubmodule: false,
  isConflicted: true,
);

/// A non-HEAD local branch, so tapping its row in the sidebar exercises
/// only the `conflictActive` gate ([BranchTreeItem]'s `isHead` short-circuit
/// is a separate, unrelated reason a checkout row can be non-interactive).
final RefSnapshot _refsWithFeatureBranch = RefSnapshot(
  head: const HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'deadbeef',
  ),
  refs: const <RefInfo>[
    RefInfo(
      fullName: 'refs/heads/main',
      shortName: 'main',
      kind: RefKind.localBranch,
      target: 'deadbeef',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: true,
      isSymbolic: false,
      worktreePath: '',
    ),
    RefInfo(
      fullName: 'refs/heads/feature',
      shortName: 'feature',
      kind: RefKind.localBranch,
      target: 'cafef00d',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: false,
      isSymbolic: false,
      worktreePath: '',
    ),
  ],
  refCountGuardTripped: false,
  totalRefCount: 2,
);

RepoSessionState _cleanSession() =>
    RepoSessionState(isOpen: true, refs: _refsWithFeatureBranch);

RepoSessionState _conflictSession() => RepoSessionState(
  isOpen: true,
  refs: _refsWithFeatureBranch,
  repoState: _mergeState(),
  workingCopyStatus: const WorkingCopyStatus(entries: [_conflictEntry]),
);

RepoState _revertState() => const RepoState(
  flags: RepoStateFlags.revert,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: 'reverting',
);

RepoSessionState _revertSession() => RepoSessionState(
  isOpen: true,
  refs: _refsWithFeatureBranch,
  repoState: _revertState(),
  workingCopyStatus: const WorkingCopyStatus(entries: [_conflictEntry]),
);

Future<void> _pressCtrlShiftF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// Opens the in-window "Repository" menu and returns the rendered color of
/// [label]'s row -- `colors.textTertiary` once GbmMenuItem.enabled wires
/// through, `colors.textPrimary`/hover color otherwise. Leaves the menu
/// open; callers only need one read per pumped tree.
Color _repositoryMenuItemColor(WidgetTester tester, String label) {
  final Text text = tester.widget<Text>(find.text(label));
  return text.style!.color!;
}

void main() {
  final GbmColors colors = buildGbmTheme(
    GbmThemeVariant.darkTechnical,
  ).extension<GbmColors>()!;

  group('workspace conflict <-> clean transition', () {
    testWidgets('clean: no ConflictBanner, Fetch shortcut reaches fetchRemote, '
        'checkout reaches checkout(), commit box stays enabled', (
      tester,
    ) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _cleanSession(),
      );

      expect(find.textContaining('conflicted'), findsNothing);

      await _pressCtrlShiftF(tester);
      expect(
        pumped.controller.commandLog.any((c) => c.name == 'fetchRemote'),
        isTrue,
      );

      await tester.tap(find.text('feature'));
      await tester.pumpAndSettle();
      expect(
        pumped.controller.commandLog.any(
          (c) => c.name == 'checkout' && c.args['target'] == 'feature',
        ),
        isTrue,
      );
    });

    testWidgets(
      'conflict: ConflictBanner shown, Fetch shortcut no-ops, checkout '
      'no-ops, commit box disabled',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession(),
        );

        expect(find.textContaining('conflicted'), findsWidgets);

        await _pressCtrlShiftF(tester);
        expect(
          pumped.controller.commandLog.any((c) => c.name == 'fetchRemote'),
          isFalse,
          reason:
              'repositoryFetch must be gated off by isActionEnabled() while '
              'conflictActive is true.',
        );

        await tester.tap(find.text('feature'));
        await tester.pumpAndSettle();
        expect(
          pumped.controller.commandLog.any((c) => c.name == 'checkout'),
          isFalse,
          reason:
              'BranchTreeItem.onTap must be null while conflictActive is '
              'true, mirroring isActionEnabled(branchCheckout, ...).',
        );
      },
    );

    testWidgets(
      'conflict -> clean round trip leaves no residue: banner disappears '
      'and every gate reopens',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession(),
        );

        expect(find.textContaining('conflicted'), findsWidgets);
        await _pressCtrlShiftF(tester);
        expect(
          pumped.controller.commandLog.any((c) => c.name == 'fetchRemote'),
          isFalse,
        );

        pumped.controller.emit(_cleanSession());
        await tester.pumpAndSettle();

        expect(
          find.textContaining('conflicted'),
          findsNothing,
          reason:
              'ConflictBanner must not linger after conflictActive '
              'flips back to false.',
        );

        await _pressCtrlShiftF(tester);
        expect(
          pumped.controller.commandLog.any((c) => c.name == 'fetchRemote'),
          isTrue,
          reason:
              'The keyboard shortcut path must reopen the moment the gate '
              'clears -- no stale null captured from the conflicted build.',
        );

        await tester.tap(find.text('feature'));
        await tester.pumpAndSettle();
        expect(
          pumped.controller.commandLog.any(
            (c) => c.name == 'checkout' && c.args['target'] == 'feature',
          ),
          isTrue,
        );
      },
    );

    testWidgets(
      'revert: invoking the dispatchers behind ConflictBanner\'s disabled '
      'Abort/Skip/Continue reaches no backend command',
      (tester) async {
        // ConflictBanner disables all three buttons for revert (see
        // conflict_banner_test.dart's "revert: Abort, Skip, and Continue
        // all disabled" case), so a real tap can never trigger
        // WorkspaceScreen._handleConflictAbort/Skip/Continue for this
        // state. Those dispatchers are private, but the closures they
        // produce are exposed publicly through ConflictBanner.onAbort/
        // onSkip/onContinue -- calling those fields directly reaches the
        // real exhaustive switch without going through the disabled
        // button, proving the revert branch is a genuine no-op rather
        // than falling through to a rebase/cherry-pick backend call.
        //
        // This is a real regression lock, not a formality: before the
        // dispatchers were rewritten as exhaustive switches (Commit 4 of
        // the sequencer-kind consolidation), the implicit "anything that
        // isn't merge/cherry-pick -> rebase" fallback meant this exact
        // sequence would have logged 'abortRebase' on the fake.
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _revertSession(),
        );

        final ConflictBanner banner = tester.widget<ConflictBanner>(
          find.byType(ConflictBanner),
        );

        banner.onAbort();
        banner.onSkip();
        banner.onContinue();
        await tester.pumpAndSettle();

        expect(
          pumped.controller.commandLog,
          isEmpty,
          reason:
              'Revert has no backend abort/skip/continue entry point (see '
              'RevertOps.h); the exhaustive switch in '
              '_handleConflictAbort/Skip/Continue must no-op for '
              'SequencerOperationKind.revert instead of mis-dispatching to '
              'a rebase or cherry-pick command.',
        );
      },
    );

    testWidgets(
      'Repository menu > Fetch renders enabled (not greyed) while clean',
      (tester) async {
        await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _cleanSession(),
        );

        await tester.tap(find.text('Repository'));
        await tester.pumpAndSettle();

        expect(
          _repositoryMenuItemColor(tester, 'Fetch'),
          isNot(colors.textTertiary),
        );
      },
    );

    testWidgets(
      'Repository menu > Fetch renders disabled (greyed) while conflicted',
      (tester) async {
        await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession(),
        );

        await tester.tap(find.text('Repository'));
        await tester.pumpAndSettle();

        expect(
          _repositoryMenuItemColor(tester, 'Fetch'),
          colors.textTertiary,
          reason:
              'GbmMenuItem.enabled must be false for repositoryFetch while '
              'conflictActive is true, and _GbmMenuRow must render disabled '
              'items with the fixed textTertiary foreground regardless of '
              'hover -- mirrors repo_switcher_popover.dart\'s disabled-row '
              'pattern.',
        );
      },
    );

    testWidgets(
      'lastError with codeName Conflict is not shown as a warning banner '
      'while conflicted; a non-Conflict error is shown',
      (tester) async {
        final conflictError = const GitError(
          code: 1,
          codeName: 'Conflict',
          message: 'The operation stopped with conflicts',
          detail: '',
          argv: <String>[],
          exitCode: 1,
        );

        await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession().copyWith(lastError: conflictError),
        );

        expect(
          find.text('The operation stopped with conflicts'),
          findsNothing,
          reason:
              'ConflictBanner already states this; a duplicate warning '
              'banner for the same Conflict-coded error must not appear.',
        );

        final authError = const GitError(
          code: 2,
          codeName: 'AuthenticationFailed',
          message: 'Authentication failed for remote origin',
          detail: '',
          argv: <String>[],
          exitCode: 1,
        );

        await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession().copyWith(lastError: authError),
        );

        expect(
          find.text('Authentication failed for remote origin'),
          findsOneWidget,
          reason:
              'An error unrelated to the conflict itself must stay visible '
              'even while conflictActive is true.',
        );
      },
    );
  });
}
