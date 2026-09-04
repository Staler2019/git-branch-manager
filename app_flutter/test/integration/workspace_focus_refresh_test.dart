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
import 'package:gbm_flutter/data/repositories/repo_identity.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

int _count(List<FakeCommand> log, String name) =>
    log.where((FakeCommand c) => c.name == name).length;

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
  });

  // The sweep's membership rule is "every zero-argument refresh* on the
  // controller", and this is what holds it to that: a new refresh* added
  // later without being wired in shows up here as a missing name rather
  // than as a surface someone notices is stale months on.
  //
  // Counted rather than `any`, for the same reason the tests above are:
  // `any` cannot see a double dispatch, and twelve refreshes fired twice
  // per alt-tab is exactly the regression this file exists to catch.
  testWidgets('regaining focus re-reads every local git fact exactly once', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();

    await _leaveAndReturn(tester);

    for (final String name in const <String>[
      'refreshRepoState',
      'refreshHasCommitGraph',
      'refreshHistory',
      'refreshWorkingCopy',
      'refreshStashes',
      'refreshWorktrees',
      'refreshRemotes',
      'refreshSubmodules',
      'refreshBisectStatus',
      'refreshLfs',
      'refreshLocalIdentity',
      'refreshEffectiveIdentity',
    ]) {
      expect(
        _count(pumped.controller.commandLog, name),
        1,
        reason: '$name must fire exactly once per focus regain',
      );
    }
  });

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
}
