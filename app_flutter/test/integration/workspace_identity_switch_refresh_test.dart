// Switching worktree (the worktree panel's `Switch to`) routes the same
// shell to another `repoId`, so one WorkspaceScreen element sees its
// identity change. repoSessionProvider is not autoDispose, so coming back to
// a worktree opened earlier reuses that session -- with the working-copy
// status it last read, possibly minutes ago. The user reported exactly that:
// "switch worktree, the working copy not refresh".
//
// Counted, not `any` (CLAUDE.md's count-don't-any): one switch is one sweep.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

int _count(List<FakeCommand> log, String name) =>
    log.where((FakeCommand c) => c.name == name).length;

void main() {
  const RepoIdentity main = RepoIdentity(
    workDir: '/test/repo',
    gitDir: '/test/repo/.git',
  );
  const RepoIdentity linked = RepoIdentity(
    workDir: '/test/repo-feature',
    gitDir: '/test/repo-feature/.git',
  );

  testWidgets('returning to a worktree re-reads its working copy', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: main,
      otherIdentities: const <RepoIdentity>[linked],
    );
    final FakeRepoSessionController linkedController =
        pumped.otherControllers[linked]!;

    pumped.router.go(
      RoutePaths.workspaceFor(Uri.encodeComponent(linked.workDir)),
    );
    await tester.pumpAndSettle();
    pumped.controller.commandLog.clear();
    linkedController.commandLog.clear();

    pumped.router.go(
      RoutePaths.workspaceFor(Uri.encodeComponent(main.workDir)),
    );
    await tester.pumpAndSettle();

    expect(
      _count(pumped.controller.commandLog, 'refreshWorkingCopy'),
      1,
      reason:
          'the session for the worktree switched back to is reused, so its '
          'working copy must be re-read on arrival',
    );
    expect(
      _count(pumped.controller.commandLog, 'refreshHistory'),
      1,
      reason: 'a checkout in the other worktree can move shared refs too',
    );
    expect(
      _count(linkedController.commandLog, 'refreshWorkingCopy'),
      0,
      reason: 'the worktree being left is not the one on screen',
    );
    // Drains the tier-2 fallback armed by refreshRepoStatus().
    await tester.pump(const Duration(seconds: 3));
  });

  // go_router keys a page by its route, not its parameters, so Working Copy
  // in worktree A and Working Copy in worktree B are the same element. Its
  // commit box was seeded from A's draft in initState and never again --
  // the message typed for A sat in B's box, and the first keystroke there
  // wrote it into B's draft.
  testWidgets("switching worktree does not carry one repository's commit "
      'message into the other', (WidgetTester tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: main,
      otherIdentities: const <RepoIdentity>[linked],
      workingCopyBuilder: (BuildContext context, GoRouterState state) =>
          WorkingCopyView(
            identity: state.pathParameters['repoId'] == linked.workDir
                ? linked
                : main,
          ),
    );
    String summaryText() => tester
        .widget<TextField>(
          find
              .descendant(
                of: find.byType(WorkingCopyView),
                matching: find.byType(TextField),
              )
              .first,
        )
        .controller!
        .text;

    pumped.router.go(
      RoutePaths.workingCopyFor(Uri.encodeComponent(main.workDir)),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find
          .descendant(
            of: find.byType(WorkingCopyView),
            matching: find.byType(TextField),
          )
          .first,
      'fix: only for the main worktree',
    );
    await tester.pumpAndSettle();

    pumped.router.go(
      RoutePaths.workingCopyFor(Uri.encodeComponent(linked.workDir)),
    );
    await tester.pumpAndSettle();
    expect(summaryText(), '', reason: "the linked worktree's draft is empty");

    pumped.router.go(
      RoutePaths.workingCopyFor(Uri.encodeComponent(main.workDir)),
    );
    await tester.pumpAndSettle();
    expect(summaryText(), 'fix: only for the main worktree');
    await tester.pump(const Duration(seconds: 3));
  });
}
