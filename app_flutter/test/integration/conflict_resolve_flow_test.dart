// Integration coverage for the full conflict-resolution loop, entered the
// way a real user does it: ConflictBanner's "Resolve…" button inside the
// real WorkspaceScreen, not by pumping ConflictResolveWindow directly at
// `/repo/:repoId/conflicts` the way conflict_resolve_window_test.dart's
// widget-level tests do (see that file for the exhaustive per-interaction
// coverage of the editor itself -- take/reset/undo/drag/badges/etc; this
// file is scoped to the state-machine seam between WorkspaceScreen and
// ConflictResolveWindow: does the "Resolve…" button really reach the
// window, does Continue really flow back out, and -- the regression this
// batch is required to cover per the plan -- does Abort followed by a
// fresh conflict on the same path show the fresh markers rather than the
// stale resolved ones).
//
// ConflictResolveWindow is registered as `conflicts`, a *standalone
// top-level route* (CLAUDE.md: "not a dialog overlay"), not a ShellRoute
// child -- see pumpWorkspace's `topLevelRoutes` doc comment.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_conflict_file.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/conflict_resolution/conflict_resolve_window.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/widgets/split_pane.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);
final List<RouteBase> _conflictsRoute = <RouteBase>[
  GoRoute(
    path: RoutePaths.conflicts,
    builder: (context, state) =>
        ConflictResolveWindow(identity: _identity, isMacOS: false),
  ),
];

RepoState _cherryPickState() => const RepoState(
  flags: RepoStateFlags.cherryPick,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
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

/// Same path, different ours/theirs oids -- a genuinely new conflict per
/// git's own record (e.g. Abort followed by a fresh merge on the same
/// file), mirroring conflict_resolve_window_test.dart's
/// `_conflictEntryReoccurred` fixture.
const WorkingCopyEntry _conflictEntryReoccurred = WorkingCopyEntry(
  path: 'conflict.txt',
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  conflict: ConflictKind.bothModified,
  ancestorBlob: '',
  oursBlob: 'ours-hash-2',
  theirsBlob: 'theirs-hash-2',
  similarity: 0,
  isSubmodule: false,
  isConflicted: true,
);

ConflictSegment _regionSegment({
  required List<String> ours,
  required List<String> theirs,
}) => ConflictSegment(
  kind: ConflictSegmentKind.region,
  lines: const <String>[],
  ours: ours,
  theirs: theirs,
  base: const <String>[],
  hasBase: false,
);

RepoSessionState _conflictSession(
  RepoState repoState,
  WorkingCopyEntry entry,
) => RepoSessionState(
  isOpen: true,
  repoState: repoState,
  workingCopyStatus: WorkingCopyStatus(entries: [entry]),
  lastWorkingTreeContent: WorkingTreeContentReply(
    path: entry.path,
    editable: true,
    content: '<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n',
  ),
);

Future<void> _tapResolve(WidgetTester tester) async {
  await tester.tap(find.text('Resolve…'));
  await tester.pumpAndSettle();
}

Future<void> _selectConflictFile(WidgetTester tester) async {
  await tester.tap(find.text('conflict.txt'));
  await tester.pumpAndSettle();
}

/// Scopes to the inner per-region GbmSplitPane -- see
/// conflict_resolve_window_test.dart's `_perRegionTakeButton` doc comment
/// for why a bare `find.text('Take $label')` is ambiguous (the rail's
/// whole-file mini-buttons render the same text).
Finder _perRegionTakeButton(String label) => find.descendant(
  of: find.byType(GbmSplitPane).last,
  matching: find.text('Take $label'),
);

void main() {
  group('conflict resolve flow: WorkspaceScreen -> ConflictResolveWindow', () {
    testWidgets(
      'Resolve… -> select -> Take Ours -> Continue (with message) -> clean '
      '-> Back to WorkspaceScreen',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _conflictsRoute,
        );
        pumped.controller.parsedFile = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-line'],
              theirs: <String>['theirs-line'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        pumped.controller.emit(
          _conflictSession(_cherryPickState(), _conflictEntry),
        );
        await tester.pumpAndSettle();

        expect(find.text('Resolve…'), findsOneWidget);
        await _tapResolve(tester);

        expect(find.byType(ConflictResolveWindow), findsOneWidget);
        await _selectConflictFile(tester);

        await tester.tap(_perRegionTakeButton('Ours'));
        await tester.pumpAndSettle();
        expect(find.text('Resolved'), findsOneWidget);

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();

        expect(find.byType(AlertDialog), findsOneWidget);
        expect(find.text('Original summary'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('Continue'),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          pumped.controller.commandLog.any(
            (c) => c.name == 'cherryPickContinueWithMessage',
          ),
          isTrue,
        );

        // The sequencer operation finishing publishes a clean state.
        // ConflictResolveWindow's ConflictBatch is a union across the
        // window's lifetime (see ConflictBatch's doc comment: a resolved
        // file stays listed with a checkmark rather than vanishing), so
        // conflict.txt stays visible as Resolved here rather than the body
        // switching to an empty state -- ConflictResolveWindow does not
        // auto-navigate away either way (it is a standalone window), so the
        // way back out is always the AppBar's BackButton.
        pumped.controller.emit(const RepoSessionState(isOpen: true));
        await tester.pumpAndSettle();

        expect(find.text('Resolved'), findsOneWidget);
        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        expect(find.byType(ConflictResolveWindow), findsNothing);
      },
    );

    testWidgets(
      'Abort, then a fresh conflict on the same path shows fresh markers '
      'not the previous resolution (regression)',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          topLevelRoutes: _conflictsRoute,
        );
        pumped.controller.parsedFile = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['first-ours'],
              theirs: <String>['first-theirs'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        pumped.controller.emit(_conflictSession(_mergeState(), _conflictEntry));
        await tester.pumpAndSettle();

        await _tapResolve(tester);
        await _selectConflictFile(tester);

        await tester.tap(_perRegionTakeButton('Ours'));
        await tester.pumpAndSettle();
        expect(find.text('Resolved'), findsOneWidget);

        await tester.tap(find.text('Abort'));
        await tester.pumpAndSettle();
        expect(pumped.controller.mergeAbortCalled, isTrue);

        // Abort clears the conflict; the file drops out of `conflicted`.
        pumped.controller.emit(
          pumped.controller.state.copyWith(
            workingCopyStatus: WorkingCopyStatus.empty,
          ),
        );
        await tester.pumpAndSettle();

        // A fresh merge conflicts the same path again with different
        // markers than the first occurrence.
        pumped.controller.parsedFile = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['second-ours'],
              theirs: <String>['second-theirs'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        pumped.controller.emit(
          pumped.controller.state.copyWith(
            repoState: _mergeState(),
            workingCopyStatus: const WorkingCopyStatus(
              entries: [_conflictEntryReoccurred],
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.text('second-ours'),
          findsOneWidget,
          reason: 'The editor must reflect the new occurrence.',
        );
        expect(find.text('Unresolved'), findsOneWidget);
        expect(
          find.text('Resolved'),
          findsNothing,
          reason:
              'Must not stay stuck showing the first occurrence as already '
              'resolved.',
        );
      },
    );
  });
}
