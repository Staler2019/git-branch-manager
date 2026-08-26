// Integration coverage for the status bar's background-task Cancel button,
// driven through the real WorkspaceScreen rather than a hand-fed callback.
//
// status_bar_test.dart already covers StatusBar as a widget -- given a list
// of BackgroundTasks and an `onCancelTask` closure, does the right button
// appear and fire. What nothing covered is the layer above it: whether
// WorkspaceScreen._backgroundTasks() derives the right tasks from
// RepoSessionState in the first place, and whether _cancelTask() actually
// reaches the session. That seam is where a dead button hides -- exactly
// the shape of the dispatch-parity bug workspace_intent_dispatch_parity_test
// exists for.
//
// Cancelling the history scan has no dedicated capi entry point: it works by
// re-requesting the current snapshot (`refreshHistory()`), keeping the rows
// already loaded per spec page 10 ("取消保留已載入的部分，不清空畫面").
// FakeRepoSessionController records that call rather than no-opping on its
// null-session guard, which is what lets these tests tell a dispatched
// Cancel apart from a dead one.
//
// Harness note: never `pumpAndSettle()` while `isRefreshing` is true.
// TopBar renders an indeterminate `CircularProgressIndicator` for exactly
// that flag, and an indeterminate spinner animates forever -- pumpAndSettle
// waits for frames to stop being scheduled and therefore times out rather
// than failing on the assertion under test. Use `pump()` until the flag is
// back off.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';
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

/// A cherry-pick mid-sequence. `isSequencerOperation: true` is correct here
/// -- cherry-pick genuinely writes a `sequencer/todo` file, which is what
/// the core's flag reports (src/core/git/RepoState.h).
RepoState _cherryPickState() => const RepoState(
  flags: RepoStateFlags.cherryPick,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 2,
  rebaseTotal: 5,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
);

/// A merge conflict, built faithfully rather than copied from
/// workspace_conflict_transition_test.dart's `_mergeState()`.
///
/// That fixture sets `isSequencerOperation: true` for a merge, which the
/// core does **not**: `gbm::RepoState::isSequencerOperation()` excludes
/// merge on purpose (a plain `git commit` finishes a merge -- no todo file
/// is involved). It is harmless there, because that file only needs
/// `conflictActive`, which the conflicted entry alone satisfies. Copying it
/// here would not be harmless: `_backgroundTasks()` gates the sequencer task
/// on exactly that flag, so the borrowed fixture would manufacture a
/// "Merging" task and let the test below pin the opposite of the documented
/// behaviour.
RepoState _mergeState() => const RepoState(
  flags: RepoStateFlags.merge,
  isClean: false,
  isSequencerOperation: false,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
);

Finder _statusBarCancel() => find.descendant(
  of: find.byType(StatusBar),
  matching: find.widgetWithText(TextButton, 'Cancel'),
);

int _countOf(FakeRepoSessionController controller, String name) =>
    controller.commandLog.where((c) => c.name == name).length;

void main() {
  group('status bar background-task Cancel', () {
    testWidgets(
      'a history scan in flight shows a cancellable task whose Cancel '
      'reaches refreshHistory',
      (tester) async {
        final pumped = await pumpWorkspace(tester, identity: _identity);

        expect(
          find.descendant(
            of: find.byType(StatusBar),
            matching: find.text('Reading history'),
          ),
          findsNothing,
          reason: 'Nothing is scanning yet.',
        );

        pumped.controller.emit(
          pumped.controller.state.copyWith(isRefreshing: true),
        );
        await tester.pump();

        expect(
          find.descendant(
            of: find.byType(StatusBar),
            matching: find.text('Reading history'),
          ),
          findsOneWidget,
        );

        final TextButton cancel = tester.widget<TextButton>(_statusBarCancel());
        expect(
          cancel.onPressed,
          isNotNull,
          reason:
              'The history scan is built with cancellable: true '
              '(_backgroundTasks), so its Cancel must be live.',
        );

        await tester.tap(_statusBarCancel());
        await tester.pump();

        expect(
          _countOf(pumped.controller, 'refreshHistory'),
          1,
          reason:
              'Cancelling the scan re-requests the current snapshot -- there '
              'is no separate cancel entry point in the capi, so a Cancel '
              'that reaches nothing is indistinguishable from a dead button '
              'without this assertion.',
        );
      },
    );

    testWidgets(
      'a sequencer operation shows a non-cancellable task: Cancel renders '
      'but is disabled',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: RepoSessionState(
            isOpen: true,
            repoState: _cherryPickState(),
            workingCopyStatus: const WorkingCopyStatus(
              entries: <WorkingCopyEntry>[_conflictEntry],
            ),
          ),
        );

        expect(
          find.descendant(
            of: find.byType(StatusBar),
            matching: find.text('Cherry-picking'),
          ),
          findsOneWidget,
        );

        final TextButton cancel = tester.widget<TextButton>(_statusBarCancel());
        expect(
          cancel.onPressed,
          isNull,
          reason:
              'Spec page 10\'s TASKS table marks Checkout/Merge/Rebase '
              '"不可取消" -- interrupting a sequencer midway is more '
              'dangerous than letting it finish, so _backgroundTasks builds '
              'it with cancellable: false.',
        );

        expect(
          _countOf(pumped.controller, 'refreshHistory'),
          0,
          reason: 'A disabled Cancel must not have dispatched anything.',
        );
      },
    );

    testWidgets(
      'a merge conflict shows the banner but contributes no status-bar task',
      (tester) async {
        await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: RepoSessionState(
            isOpen: true,
            repoState: _mergeState(),
            workingCopyStatus: const WorkingCopyStatus(
              entries: <WorkingCopyEntry>[_conflictEntry],
            ),
          ),
        );

        // activeSequencerOperation() *includes* merge, so the banner (and
        // its Abort) is present...
        expect(find.byType(ConflictBanner), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(ConflictBanner),
            matching: find.text('Abort'),
          ),
          findsOneWidget,
        );

        // ...while RepoState.isSequencerOperation excludes it, so
        // _backgroundTasks() adds nothing. The two predicates are
        // deliberately different (gbm_sequencer_operation.dart's "IMPORTANT"
        // block); this test exists so a future dedup cannot quietly collapse
        // them into one.
        expect(
          _statusBarCancel(),
          findsNothing,
          reason:
              'No background task means no progress zone, hence no Cancel '
              'button at all.',
        );
        expect(
          find.descendant(
            of: find.byType(StatusBar),
            matching: find.text('Merging'),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'once the scan ends the task clears with no residue in the status bar',
      (tester) async {
        final pumped = await pumpWorkspace(tester, identity: _identity);

        pumped.controller.emit(
          pumped.controller.state.copyWith(isRefreshing: true),
        );
        await tester.pump();
        await tester.tap(_statusBarCancel());
        await tester.pump();

        pumped.controller.emit(
          pumped.controller.state.copyWith(isRefreshing: false),
        );
        await tester.pumpAndSettle();

        // StatusBar deliberately lingers the finished task for 3 seconds
        // (its `_lingerTimer`), so the row is still on screen right after
        // the transition. Drain that before asserting it is gone, otherwise
        // this would pin the linger away by accident.
        expect(
          find.descendant(
            of: find.byType(StatusBar),
            matching: find.text('Reading history'),
          ),
          findsOneWidget,
          reason: 'Still inside the 3s linger window.',
        );

        await tester.pump(const Duration(seconds: 3, milliseconds: 100));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byType(StatusBar),
            matching: find.text('Reading history'),
          ),
          findsNothing,
        );
        expect(_statusBarCancel(), findsNothing);
        expect(
          _countOf(pumped.controller, 'refreshHistory'),
          1,
          reason:
              'The scan ending must not re-dispatch the cancel a second '
              'time.',
        );
      },
    );
  });
}
