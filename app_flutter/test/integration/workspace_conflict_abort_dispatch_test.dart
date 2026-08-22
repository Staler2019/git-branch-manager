// Integration coverage for the other half of the "sudden cancel" story:
// ConflictBanner's Abort/Skip/Continue, which are how a user bails out of a
// sequencer operation that has stopped on a conflict.
//
// WorkspaceScreen._handleConflictAbort/_handleConflictSkip/
// _handleConflictContinue each switch exhaustively over
// activeSequencerOperation(session.repoState) and dispatch a *different*
// backend call per kind. Only one branch of that had coverage before this
// file: workspace_conflict_transition_test.dart's revert case, which proves
// the null/revert arms no-op. The three arms that actually dispatch --
// merge, cherry-pick, rebase -- were untested through the real buttons.
//
// Two properties here are specifically about the state machine *changing*
// underneath a live banner, which is the thing this batch exists for:
//
//   * when the kind switches mid-flight, the same Abort button must
//     re-target the new kind and never repeat the old one's call, and
//   * when two flags are set at once, the documented priority ladder
//     (rebase > cherry-pick > revert > merge) decides -- a real on-disk
//     state, because a rebase using the merge backend leaves CHERRY_PICK_HEAD
//     lying around mid-step.
//
// Buttons are found through `find.descendant(of: find.byType(ConflictBanner))`
// rather than bare text: ConflictResolveWindow and the status bar render
// overlapping vocabulary, and the whole WorkspaceScreen is mounted here.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart'
    show ConflictBanner;

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
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

/// A conflicted session whose sequencer kind is decided purely by [flags].
///
/// `isSequencerOperation` mirrors the core's own predicate, which excludes
/// merge (src/core/git/RepoState.h) -- it plays no part in which kind
/// [activeSequencerOperation] derives, and `conflictActive` is satisfied by
/// the conflicted entry either way, so getting it right costs nothing and
/// keeps the fixture honest.
RepoSessionState _conflicted(int flags) => RepoSessionState(
  isOpen: true,
  repoState: RepoState(
    flags: flags,
    isClean: false,
    isSequencerOperation: flags != RepoStateFlags.merge,
    rebaseStep: 1,
    rebaseTotal: 3,
    rebaseOntoLabel: 'main',
    indexLocked: false,
    indexLockAgeSeconds: null,
    describe: '',
  ),
  workingCopyStatus: const WorkingCopyStatus(
    entries: <WorkingCopyEntry>[_conflictEntry],
  ),
);

Finder _bannerButton(String label) => find.descendant(
  of: find.byType(ConflictBanner),
  matching: find.widgetWithText(TextButton, label),
);

Future<void> _tapBanner(WidgetTester tester, String label) async {
  await tester.tap(_bannerButton(label));
  await tester.pumpAndSettle();
}

int _countOf(FakeRepoSessionController controller, String name) =>
    controller.commandLog.where((c) => c.name == name).length;

void main() {
  group('ConflictBanner dispatch by sequencer kind', () {
    testWidgets('merge: Abort reaches mergeAbort; Skip and Continue are '
        'disabled', (tester) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _conflicted(RepoStateFlags.merge),
      );

      expect(
        tester.widget<TextButton>(_bannerButton('Skip')).onPressed,
        isNull,
        reason:
            'SequencerOperationKind.merge.canSkip is false -- git has no '
            'notion of skipping one file\'s conflict during a merge.',
      );
      expect(
        tester.widget<TextButton>(_bannerButton('Continue')).onPressed,
        isNull,
        reason:
            'There is no gbm_merge_continue(); a plain commit finishes a '
            'merge.',
      );

      await _tapBanner(tester, 'Abort');

      expect(_countOf(pumped.controller, 'mergeAbort'), 1);
      expect(_countOf(pumped.controller, 'abortRebase'), 0);
      expect(_countOf(pumped.controller, 'cherryPickAbort'), 0);
    });

    testWidgets('cherry-pick: Abort, Skip and Continue each reach their own '
        'backend call', (tester) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _conflicted(RepoStateFlags.cherryPick),
      );

      await _tapBanner(tester, 'Skip');
      await _tapBanner(tester, 'Continue');
      await _tapBanner(tester, 'Abort');

      expect(_countOf(pumped.controller, 'cherryPickSkip'), 1);
      expect(_countOf(pumped.controller, 'cherryPickContinue'), 1);
      expect(_countOf(pumped.controller, 'cherryPickAbort'), 1);
      expect(
        _countOf(pumped.controller, 'skipRebase') +
            _countOf(pumped.controller, 'continueRebase') +
            _countOf(pumped.controller, 'abortRebase'),
        0,
        reason:
            'A cherry-pick must never be dispatched to rebase\'s entry '
            'points -- the implicit "anything else -> rebase" fallback these '
            'switches replaced would have done exactly that.',
      );
    });

    testWidgets('rebase: Abort, Skip and Continue each reach their own '
        'backend call', (tester) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _conflicted(RepoStateFlags.rebaseApply),
      );

      await _tapBanner(tester, 'Skip');
      await _tapBanner(tester, 'Continue');
      await _tapBanner(tester, 'Abort');

      expect(_countOf(pumped.controller, 'skipRebase'), 1);
      expect(_countOf(pumped.controller, 'continueRebase'), 1);
      expect(_countOf(pumped.controller, 'abortRebase'), 1);
      expect(
        _countOf(pumped.controller, 'cherryPickSkip') +
            _countOf(pumped.controller, 'cherryPickContinue') +
            _countOf(pumped.controller, 'cherryPickAbort'),
        0,
      );
    });

    testWidgets(
      'rebaseMerge + cherryPick set at once: the priority ladder picks '
      'rebase',
      (tester) async {
        // Not a synthetic combination: a conflicted `git rebase` on the
        // merge backend leaves CHERRY_PICK_HEAD on disk mid-step, so both
        // flags really are set at the same time. activeSequencerOperation()
        // documents rebase > cherry-pick > revert > merge as a deliberate
        // behaviour correction over the old merge-first ladders.
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflicted(
            RepoStateFlags.rebaseMerge | RepoStateFlags.cherryPick,
          ),
        );

        await _tapBanner(tester, 'Abort');

        expect(_countOf(pumped.controller, 'abortRebase'), 1);
        expect(
          _countOf(pumped.controller, 'cherryPickAbort'),
          0,
          reason:
              'Reading the flags in the wrong order would abort the '
              'cherry-pick half of a rebase, leaving the rebase itself in '
              'progress.',
        );
      },
    );
  });

  group('ConflictBanner dispatch follows a mid-flight kind change', () {
    testWidgets(
      'merge -> rebase: the same Abort button re-targets and does not repeat '
      'the previous call',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflicted(RepoStateFlags.merge),
        );

        await _tapBanner(tester, 'Abort');
        expect(_countOf(pumped.controller, 'mergeAbort'), 1);

        pumped.controller.emit(_conflicted(RepoStateFlags.rebaseApply));
        await tester.pumpAndSettle();

        await _tapBanner(tester, 'Abort');

        expect(_countOf(pumped.controller, 'abortRebase'), 1);
        expect(
          _countOf(pumped.controller, 'mergeAbort'),
          1,
          reason:
              'The banner\'s closures are rebuilt from the new session on '
              'every build; a stale capture would keep aborting the merge '
              'that is no longer in progress.',
        );
      },
    );

    testWidgets(
      'merge -> cherry-pick: Skip and Continue go from disabled to live and '
      'dispatch the new kind',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflicted(RepoStateFlags.merge),
        );

        expect(
          tester.widget<TextButton>(_bannerButton('Skip')).onPressed,
          isNull,
        );

        pumped.controller.emit(_conflicted(RepoStateFlags.cherryPick));
        await tester.pumpAndSettle();

        expect(
          tester.widget<TextButton>(_bannerButton('Skip')).onPressed,
          isNotNull,
          reason:
              'canSkip flips with the kind, so the button must flip with it '
              '-- a gate that only reads the initial state would leave Skip '
              'permanently dead for the rest of the session.',
        );

        await _tapBanner(tester, 'Skip');
        expect(_countOf(pumped.controller, 'cherryPickSkip'), 1);
      },
    );

    testWidgets(
      'conflict -> clean: the banner goes away and its buttons take nothing '
      'with them',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflicted(RepoStateFlags.cherryPick),
        );

        await _tapBanner(tester, 'Abort');
        expect(_countOf(pumped.controller, 'cherryPickAbort'), 1);

        pumped.controller.emit(const RepoSessionState(isOpen: true));
        await tester.pumpAndSettle();

        expect(find.byType(ConflictBanner), findsNothing);
        expect(
          pumped.controller.commandLog.where((c) => c.name.contains('Abort')),
          hasLength(1),
          reason:
              'Clearing the conflict must not replay the abort -- the '
              'operation is already over.',
        );
      },
    );
  });
}
