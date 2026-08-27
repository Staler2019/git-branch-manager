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
}
