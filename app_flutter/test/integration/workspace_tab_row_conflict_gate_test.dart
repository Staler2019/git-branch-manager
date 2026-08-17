// Integration coverage for the TabRow Merge/Cherry-pick/Reset gap this
// branch fixes: CLAUDE.md's "Known gaps" flagged these three TextButtons as
// bypassing isActionEnabled() entirely (a fourth dispatch surface beyond
// menu click / keyboard / macOS system menu -- see
// workspace_intent_dispatch_parity_test.dart for why the real dispatch path
// matters, not just a hand-fed handler map). Drives the real WorkspaceScreen
// via pumpWorkspace/FakeRepoSessionController.emit(), mirroring
// workspace_conflict_transition_test.dart's pattern.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

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

RepoSessionState _cleanSession() => const RepoSessionState(isOpen: true);

RepoSessionState _conflictSession() => RepoSessionState(
  isOpen: true,
  repoState: _mergeState(),
  workingCopyStatus: const WorkingCopyStatus(entries: [_conflictEntry]),
);

List<RouteBase> _dialogPlaceholderRoutes() => <RouteBase>[
  GoRoute(
    path: RoutePaths.mergeDialog,
    builder: (context, state) => const Scaffold(body: Text('merge-dialog')),
  ),
  GoRoute(
    path: RoutePaths.cherryPickDialog,
    builder: (context, state) =>
        const Scaffold(body: Text('cherry-pick-dialog')),
  ),
  GoRoute(
    path: RoutePaths.resetBranchDialog,
    builder: (context, state) =>
        const Scaffold(body: Text('reset-branch-dialog')),
  ),
];

void main() {
  group('TabRow Merge/Cherry-pick/Reset vs conflictActive', () {
    testWidgets(
      'clean: Merge/Cherry-pick/Reset all reach their dialog routes',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _cleanSession(),
          topLevelRoutes: _dialogPlaceholderRoutes(),
        );

        for (final (String label, String dialogText)
            in const <(String, String)>[
              ('Merge…', 'merge-dialog'),
              ('Cherry-pick…', 'cherry-pick-dialog'),
              ('Reset…', 'reset-branch-dialog'),
            ]) {
          await tester.tap(find.text(label));
          await tester.pumpAndSettle();
          expect(find.text(dialogText), findsOneWidget, reason: label);
          // Each dialog is pushed on top of TabRow, not swapped in --
          // pop back before the next iteration so the following button is
          // visible again.
          pumped.router.pop();
          await tester.pumpAndSettle();
        }
      },
    );

    testWidgets('conflict: Merge/Cherry-pick/Reset render disabled and do not '
        'navigate', (tester) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _conflictSession(),
        topLevelRoutes: _dialogPlaceholderRoutes(),
      );

      for (final String label in const <String>[
        'Merge…',
        'Cherry-pick…',
        'Reset…',
      ]) {
        final TextButton button = tester.widget<TextButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(TextButton),
          ),
        );
        expect(
          button.onPressed,
          isNull,
          reason:
              '$label must be disabled while conflictActive is true, '
              'mirroring isActionEnabled(branchMergeIntoCurrent, ...).',
        );
      }

      final String startLocation = pumped
          .router
          .routerDelegate
          .currentConfiguration
          .uri
          .toString();
      for (final String label in const <String>[
        'Merge…',
        'Cherry-pick…',
        'Reset…',
      ]) {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }
      expect(
        pumped.router.routerDelegate.currentConfiguration.uri.toString(),
        startLocation,
      );
    });

    testWidgets(
      'conflict -> clean round trip: buttons re-enable with no residue',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession(),
          topLevelRoutes: _dialogPlaceholderRoutes(),
        );

        expect(
          tester
              .widget<TextButton>(
                find.ancestor(
                  of: find.text('Merge…'),
                  matching: find.byType(TextButton),
                ),
              )
              .onPressed,
          isNull,
        );

        pumped.controller.emit(_cleanSession());
        await tester.pumpAndSettle();

        expect(
          tester
              .widget<TextButton>(
                find.ancestor(
                  of: find.text('Merge…'),
                  matching: find.byType(TextButton),
                ),
              )
              .onPressed,
          isNotNull,
          reason:
              'The gate must reopen the moment conflictActive flips back '
              'to false -- no stale null captured from the conflicted '
              'build.',
        );

        await tester.tap(find.text('Merge…'));
        await tester.pumpAndSettle();
        expect(find.text('merge-dialog'), findsOneWidget);
      },
    );
  });
}
