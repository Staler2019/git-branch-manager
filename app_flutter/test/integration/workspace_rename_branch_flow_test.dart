// Integration coverage for issue #45's dispatch seam: F2 / Branch → Rename
// branch… -> the real WorkspaceScreen handler map -> the rename-branch route
// -> RenameBranchDialogContent -> RepoSessionController.renameBranch().
//
// The widget-tier test (test/features/dialogs/rename_branch_dialog_test.dart)
// pumps the dialog directly, so it cannot see whether anything actually
// reaches it -- which is exactly the shape of bug CLAUDE.md's "Intent /
// Action layer" section documents (a handler wired to null in
// _buildActionHandlers() while the in-window menu still appeared to work).
// F2 is the most exposed of the three entry points: it has no visible
// affordance at all, so a broken binding is silent.
//
// The dialog is registered via `topLevelRoutes`, not `extraRoutes`: dialog
// routes are siblings of the workspace ShellRoute, not children of it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/rename_branch/rename_branch_dialog.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_repo_session.dart';
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

const RefInfo _mainBranch = RefInfo(
  fullName: 'refs/heads/main',
  shortName: 'main',
  kind: RefKind.localBranch,
  target: 'deadbeef',
  upstream: 'refs/remotes/origin/main',
  ahead: 1,
  behind: 0,
  hasTrackingInfo: true,
  isGone: false,
  isHead: true,
  isSymbolic: false,
  worktreePath: '',
);

final RefSnapshot _refs = const RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'deadbeef',
  ),
  refs: <RefInfo>[_mainBranch],
  refCountGuardTripped: false,
  totalRefCount: 1,
);

RepoSessionState _cleanSession() => RepoSessionState(isOpen: true, refs: _refs);

RepoSessionState _conflictSession() => RepoSessionState(
  isOpen: true,
  refs: _refs,
  repoState: _mergeState(),
  workingCopyStatus: const WorkingCopyStatus(
    entries: <WorkingCopyEntry>[_conflictEntry],
  ),
);

/// The real dialog behind the real route, not a placeholder: the point of
/// this tier is that the whole chain works, and a placeholder would not
/// prove the route's `branch` query parameter reaches the dialog.
List<RouteBase> _renameDialogRoute() => <RouteBase>[
  dialogRoute(
    path: RoutePaths.renameBranchDialog,
    builder: (context, state) => RenameBranchDialogContent(
      identity: _identity,
      branchName: state.uri.queryParameters['branch']?.isEmpty ?? true
          ? null
          : state.uri.queryParameters['branch'],
    ),
  ),
];

Future<void> _pressF2(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.f2);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.f2);
  await tester.pumpAndSettle();
}

void main() {
  group('rename branch flow', () {
    testWidgets('F2 opens the rename dialog seeded with the current branch', (
      tester,
    ) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _cleanSession(),
        topLevelRoutes: _renameDialogRoute(),
      );

      expect(find.byType(RenameBranchDialogContent), findsNothing);

      await _pressF2(tester);

      expect(find.byType(RenameBranchDialogContent), findsOneWidget);
      // The dialog is a non-opaque overlay, so the workspace (and its own
      // sidebar filter TextField) stays mounted underneath -- scope the
      // field lookup to the dialog rather than using find.byType(TextField).
      final Finder nameField = find.descendant(
        of: find.byType(RenameBranchDialogContent),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(nameField).controller!.text, 'main');
    });

    testWidgets('confirming in the dialog reaches renameBranch on the real '
        'controller', (tester) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _cleanSession(),
        topLevelRoutes: _renameDialogRoute(),
      );

      await _pressF2(tester);

      final Finder nameField = find.descendant(
        of: find.byType(RenameBranchDialogContent),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'trunk');
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(RenameBranchDialogContent),
          matching: find.text('Rename'),
        ),
      );
      await tester.pumpAndSettle();

      final Iterable<FakeCommand> renames = pumped.controller.commandLog.where(
        (FakeCommand c) => c.name == 'renameBranch',
      );
      expect(renames, hasLength(1));
      expect(renames.single.args['from'], 'main');
      expect(renames.single.args['to'], 'trunk');
      // main tracks refs/remotes/origin/main, so the default choice carries
      // the rename to the remote.
      expect(renames.single.args['renameRemote'], isTrue);
      expect(renames.single.args['remoteName'], 'origin');

      // The dialog dispatches and pops rather than waiting (spec page 10:
      // progress belongs to the background-task row, "不留在 dialog 裡轉圈").
      expect(find.byType(RenameBranchDialogContent), findsNothing);
    });

    testWidgets('mid-conflict F2 opens nothing at all', (tester) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _conflictSession(),
        topLevelRoutes: _renameDialogRoute(),
      );

      await _pressF2(tester);

      expect(find.byType(RenameBranchDialogContent), findsNothing);
      expect(
        pumped.controller.commandLog.where(
          (FakeCommand c) => c.name == 'renameBranch',
        ),
        isEmpty,
      );
    });

    testWidgets('conflict -> clean round-trip: F2 works again once the '
        'conflict is resolved, with no residue from the blocked attempt', (
      tester,
    ) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _conflictSession(),
        topLevelRoutes: _renameDialogRoute(),
      );

      await _pressF2(tester);
      expect(find.byType(RenameBranchDialogContent), findsNothing);

      pumped.controller.emit(_cleanSession());
      await tester.pumpAndSettle();

      await _pressF2(tester);
      expect(find.byType(RenameBranchDialogContent), findsOneWidget);
    });
  });
}
