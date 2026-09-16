// The user reported that coming back to the window does not refresh the
// working-copy diff or the history. It was not broken -- it was never
// built: grepping app_flutter/lib for AppLifecycleState,
// WidgetsBindingObserver, AppLifecycleListener and
// didChangeAppLifecycleState returned nothing at all, so no surface in the
// app reacted to the window regaining focus.
//
// That matters because git state changes behind the app's back constantly:
// an editor saves a file, a terminal in another window commits, rebases or
// force-pushes. On desktop Flutter reports `inactive` when the window
// loses focus and `resumed` when it regains it, so that transition is the
// natural moment to re-read.
//
// Counted, not `any`: a double dispatch here means two full history walks
// per alt-tab, which is exactly the kind of regression this is otherwise
// invisible to. Both refreshes are recorded by FakeRepoSessionController
// (see its refreshHistory/refreshWorkingCopy overrides) -- unoverridden
// they would hit the real null-session guard and no-op silently, and this
// test could not tell a dead listener from a live one.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

int _count(List<FakeCommand> log, String name) =>
    log.where((FakeCommand c) => c.name == name).length;

/// The four tier-1 members -- see `workspace_intent_dispatch_parity_test.dart`
/// for the identical split and why it exists on the other dispatch path too.
const List<String> _tier1Commands = <String>[
  'refreshRepoState',
  'refreshHasCommitGraph',
  'refreshHistory',
  'refreshWorkingCopy',
];

const List<String> _tier2Commands = <String>[
  'refreshStashes',
  'refreshWorktrees',
  'refreshRemotes',
  'refreshSubmodules',
  'refreshBisectStatus',
  'refreshLfs',
  'refreshLocalIdentity',
  'refreshEffectiveIdentity',
];

WorkingCopyStatus _emptyStatus() =>
    WorkingCopyStatus.fromJson(<String, dynamic>{'entries': <dynamic>[]});

Future<void> _leaveAndReturn(WidgetTester tester) async {
  // The real desktop sequence: focus loss parks the app in `inactive`, and
  // regaining focus returns it to `resumed`.
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  await tester.pump();
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  await tester.pump();
}

void main() {
  final RepoIdentity identity = RepoIdentity(
    workDir: '/test/repo',
    gitDir: '/test/repo/.git',
  );

  testWidgets('regaining window focus refreshes history and working copy', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    await _leaveAndReturn(tester);

    expect(
      _count(pumped.controller.commandLog, 'refreshHistory'),
      1,
      reason: 'history must be re-read exactly once when the window returns',
    );
    expect(
      _count(pumped.controller.commandLog, 'refreshWorkingCopy'),
      1,
      reason:
          'the working copy must be re-read too -- an editor saving a file '
          'while the app was in the background emits no GBM event',
    );
    // Drains the tier-2 fallback armed by refreshRepoStatus() -- otherwise
    // this test ends with a pending Timer, which flutter_test's own
    // _verifyInvariants() treats as a hard failure regardless of what this
    // test is actually about.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('losing focus alone refreshes nothing', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();

    expect(_count(pumped.controller.commandLog, 'refreshHistory'), 0);
    expect(_count(pumped.controller.commandLog, 'refreshWorkingCopy'), 0);
  });

  testWidgets('rapid window switching is throttled to one refresh', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    // Alt-tabbing back and forth must not queue one full history walk per
    // bounce; the point of the feature is freshness, not a refresh storm.
    await _leaveAndReturn(tester);
    await _leaveAndReturn(tester);
    await _leaveAndReturn(tester);

    expect(
      _count(pumped.controller.commandLog, 'refreshHistory'),
      1,
      reason: 'three bounces inside the throttle window are one refresh',
    );
    await tester.pump(const Duration(seconds: 3)); // drain tier 2's fallback
  });

  testWidgets('a later return, past the throttle window, refreshes again', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    await _leaveAndReturn(tester);
    // Past the throttle: this is a genuinely new visit, and the repository
    // may well have moved since the last one.
    await tester.pump(const Duration(seconds: 3));
    await _leaveAndReturn(tester);

    expect(_count(pumped.controller.commandLog, 'refreshHistory'), 2);
    expect(_count(pumped.controller.commandLog, 'refreshWorkingCopy'), 2);
    // The second _leaveAndReturn armed its own tier-2 fallback; drain it.
    await tester.pump(const Duration(seconds: 3));
  });

  // RepoState is the half of `conflictActive` that refreshWorkingCopy() does
  // NOT cover, and until this test it was never re-read on focus at all:
  // _readRepoState() had exactly two callers, session open and the
  // operationFinished event. So a rebase started -- or aborted -- from a
  // terminal left the status bar, the conflict banner and the twelve
  // isActionEnabled() gates showing the state from whenever the app last ran
  // an operation itself.
  //
  // It is cheap enough to belong here: Session::repoState() is
  // `RepoState::read(paths_)`, which only stats a handful of .git/ paths and
  // spawns no subprocess.
  testWidgets('regaining window focus re-reads repo state', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    await _leaveAndReturn(tester);

    expect(
      _count(pumped.controller.commandLog, 'refreshRepoState'),
      1,
      reason:
          'a rebase begun or aborted from a terminal moves .git/ without '
          'emitting any GBM event, so repoState is stale until re-read',
    );
    await tester.pump(const Duration(seconds: 3)); // drain tier 2's fallback
  });

  testWidgets('the repo-state read is throttled with the rest', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    await _leaveAndReturn(tester);
    await _leaveAndReturn(tester);
    await _leaveAndReturn(tester);

    expect(
      _count(pumped.controller.commandLog, 'refreshRepoState'),
      1,
      reason:
          'the new read goes through the same throttle as the two that were '
          'already there -- not around it',
    );
    await tester.pump(const Duration(seconds: 3)); // drain tier 2's fallback
  });

  // The sweep's membership rule is "every zero-argument refresh* on the
  // controller", and this is what holds it to that: a new refresh* added
  // later without being wired in shows up here as a missing name rather
  // than as a surface someone notices is stale months on.
  //
  // Counted rather than `any`, for the same reason the tests above are:
  // `any` cannot see a double dispatch, and twelve refreshes fired twice
  // per alt-tab is exactly the regression this file exists to catch.
  //
  // Split into tier 1 / tier 2 (fix/refresh-ui-first-tiering, C4): tier 2 is
  // deferred until GBM_EVENT_WORKING_COPY_STATUS_UPDATED lands (consumed in
  // `publishWorkingCopyStatus`), so asserting all twelve immediately after
  // `_leaveAndReturn` would be a false claim about the eight -- this half is
  // also the negative case advisor flagged: a sweep genuinely in flight,
  // with tier 2 not yet triggered, must show the eight at 0, not just an
  // unrelated status update with no sweep running at all (that second case
  // is covered directly at the controller level in
  // repo_session_working_copy_diffs_test.dart).
  testWidgets('regaining focus immediately re-reads the four tier-1 facts, and '
      'defers the rest', (WidgetTester tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    await _leaveAndReturn(tester);

    for (final String name in _tier1Commands) {
      expect(
        _count(pumped.controller.commandLog, name),
        1,
        reason: '$name must fire exactly once per focus regain',
      );
    }
    for (final String name in _tier2Commands) {
      expect(
        _count(pumped.controller.commandLog, name),
        0,
        reason:
            '$name is tier 2 and must not fire before the working-copy '
            'status event lands',
      );
    }
    // The assertions above are exactly the state before tier 2 fires --
    // drain the fallback now, after they have run, so it does not fire
    // during them and so this test does not end with a pending Timer.
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets(
    'once the status transition lands, every local git fact has fired '
    'exactly once',
    (WidgetTester tester) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: identity,
      );
      await tester.pumpAndSettle();
      pumped.controller.commandLog.clear();

      await _leaveAndReturn(tester);
      pumped.controller.publishWorkingCopyStatus(_emptyStatus());
      await tester.pump(Duration.zero);

      for (final String name in <String>[
        ..._tier1Commands,
        ..._tier2Commands,
      ]) {
        expect(
          _count(pumped.controller.commandLog, name),
          1,
          reason: '$name must fire exactly once per focus regain',
        );
      }
    },
  );

  // The sweep is local-only by decree, not by accident: the user ruled that
  // regaining focus must never reach the network. Gone-marking is the one
  // refresh-shaped call that would (`git remote prune --dry-run`), so its
  // absence is asserted rather than left to a doc comment nobody re-reads.
  testWidgets('the focus sweep never reaches the network', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    await _leaveAndReturn(tester);

    expect(
      _count(pumped.controller.commandLog, 'requestRemotePrunePreview'),
      0,
      reason:
          'gone-marking contacts the remote, so it is deliberately not part '
          'of the focus sweep',
    );
    expect(
      _count(pumped.controller.commandLog, 'fetchRemote'),
      0,
      reason: 'and nothing else in the sweep fetches either',
    );
    await tester.pump(const Duration(seconds: 3)); // drain tier 2's fallback
  });

  // [STATE-refresh-entry-point] says membership is a rule, not a list:
  // *every* zero-argument `refresh*` on the controller is in the sweep, and
  // the `request*` family is excluded because each is keyed to a user
  // selection that need not still exist when the window comes back. The
  // per-worktree pending-change count is keyed to "the worktrees panel is
  // open", so it is a `request*`, and the naming is what makes the exclusion
  // structural rather than a comment a later round has to notice.
  //
  // It costs one `git status` per worktree. Folding it into the sweep would
  // put N git processes on the shared read pool every 2 seconds of
  // alt-tabbing, for a panel that is usually not even on screen.
  testWidgets('the focus sweep does not measure per-worktree pending counts', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    await _leaveAndReturn(tester);
    // refreshWorktrees is tier 2 (fix/refresh-ui-first-tiering, C4) -- drive
    // the transition before asserting it fired, or this reads a sweep still
    // waiting on tier 2 as "never swept" for the wrong reason.
    pumped.controller.publishWorkingCopyStatus(_emptyStatus());
    await tester.pump(Duration.zero);

    expect(
      _count(pumped.controller.commandLog, 'requestWorktreePendingCounts'),
      0,
      reason:
          'a request* call is keyed to an open panel, not to the window '
          'regaining focus',
    );
    expect(
      _count(pumped.controller.commandLog, 'refreshWorktrees'),
      1,
      reason:
          'the plain worktree list is still swept -- it is the counts that '
          'are not',
    );
  });

  // ...and the guard above is only worth anything if the recorder is live.
  // Unoverridden, requestWorktreePendingCounts() would hit the real
  // `if (_session == nullptr) return;` and log nothing, which makes a
  // 0-count assertion vacuously true forever ([TEST-fake-seam-fails-loudly]
  // names this reverse risk). This is the test that reds if the override
  // ever stops recording.
  testWidgets('requesting the counts directly does dispatch, exactly once', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    pumped.controller.requestWorktreePendingCounts();

    expect(
      _count(pumped.controller.commandLog, 'requestWorktreePendingCounts'),
      1,
    );
  });

  // fix/refresh-ui-first-tiering, C4: tier 2's fallback exists because a
  // failed status read reports GBM_EVENT_ERROR_OCCURRED, not
  // GBM_EVENT_WORKING_COPY_STATUS_UPDATED -- without it, tier 2 would never
  // fire on that path ([CPP-coalescer-terminal-paths]'s "every terminal
  // path" lesson, one layer up). The fake's own refreshWorkingCopy()
  // override never delivers either event, so every focus regain in this
  // file actually goes through the fallback -- this test is what pins the
  // fallback itself, rather than relying on it firing as an implicit
  // side-effect of every other test in the file.
  testWidgets(
    'with no status reply, tier 2 still fires once the fallback elapses',
    (WidgetTester tester) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: identity,
      );
      await tester.pumpAndSettle();
      pumped.controller.commandLog.clear();

      await _leaveAndReturn(tester);
      for (final String name in _tier2Commands) {
        expect(_count(pumped.controller.commandLog, name), 0);
      }

      await tester.pump(const Duration(seconds: 3));

      for (final String name in _tier2Commands) {
        expect(
          _count(pumped.controller.commandLog, name),
          1,
          reason: '$name must fire once the fallback elapses',
        );
      }
    },
  );

  // Repeated F5 before tier 2 has fired must coalesce into a single tier-2
  // dispatch -- three sweeps queued on an 8-member background tier would be
  // 24 subprocess calls on a 2-6 thread pool for one impatient user, and
  // README's own wording ("活下來的是最後那一輪") is what this pins: tier 1
  // is never gated and re-runs every time, only tier 2 coalesces.
  testWidgets(
    'repeated refreshRepoStatus() before tier 2 fires coalesces to one '
    'tier-2 dispatch, while tier 1 runs every time',
    (WidgetTester tester) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: identity,
      );
      await tester.pumpAndSettle();
      pumped.controller.commandLog.clear();

      pumped.controller.refreshRepoStatus();
      pumped.controller.refreshRepoStatus();
      pumped.controller.refreshRepoStatus();

      for (final String name in _tier1Commands) {
        expect(
          _count(pumped.controller.commandLog, name),
          3,
          reason: '$name is tier 1 and is never gated',
        );
      }
      for (final String name in _tier2Commands) {
        expect(_count(pumped.controller.commandLog, name), 0);
      }

      await tester.pump(const Duration(seconds: 3));

      for (final String name in _tier2Commands) {
        expect(
          _count(pumped.controller.commandLog, name),
          1,
          reason:
              '$name must fire exactly once, not three times, for three '
              'sweeps that all landed before the first one\'s tier 2 fired',
        );
      }
    },
  );

  // A pending tier-2 timer must not survive the controller it was scheduled
  // against -- see RepoSessionController.dispose()'s own comment for why
  // the null-session guard on each refresh* member is the backstop and not
  // the fix: `state =` inside _dispatchTier2Members() runs before any
  // member is even called.
  test(
    'a pending tier-2 timer is cancelled by dispose, and never fires',
    () async {
      final FakeRepoSessionController controller = FakeRepoSessionController(
        RepoIdentity(workDir: '/test/repo', gitDir: '/test/repo/.git'),
        const RepoSessionState(isOpen: true),
      );

      controller.refreshRepoStatus();
      controller.dispose();

      await Future<void>.delayed(const Duration(seconds: 4));

      for (final String name in _tier2Commands) {
        expect(
          _count(controller.commandLog, name),
          0,
          reason: 'dispose() must cancel the fallback before it can fire',
        );
      }
    },
  );
}
