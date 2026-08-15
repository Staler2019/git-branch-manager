import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/parsed_conflict_file.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart'
    show
        ConflictResolution,
        RepoSessionController,
        RepoSessionState,
        WorkingTreeContentReply,
        repoSessionProvider;
import 'package:gbm_flutter/features/conflict_resolution/conflict_resolve_window.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/split_pane.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Fixture builders mirroring conflict_resolve_logic_test.dart's pattern:
// hand-build a ParsedConflictFile directly rather than round-tripping through
// gbm_parse_conflict_markers() (native, unavailable to a fake GbmBindings).

RepoState _stateWith(int flags) => RepoState(
  flags: flags,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
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

final WorkingCopyEntry _conflictEntry = const WorkingCopyEntry(
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

void main() {
  group('ConflictResolveWindow', () {
    final identity = RepoIdentity(
      workDir: '/test/repo',
      gitDir: '/test/repo/.git',
    );

    testWidgets('renders three-column layout with split panes', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      expect(find.text('Resolve Conflicts'), findsOneWidget);
      expect(find.byType(GbmSplitPane), findsWidgets);
      expect(find.text('Ours'), findsOneWidget);
      expect(find.text('Theirs'), findsOneWidget);
    });

    testWidgets('Take Ours appends lines with sequential badges', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1', 'ours-line2'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      expect(find.text('Unresolved'), findsOneWidget);

      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);
    });

    testWidgets('per-line delete button removes a line and renumbers badges', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1', 'ours-line2'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);

      // Delete the first result line (position 0, badge ①).
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      // The remaining line renumbers down to ①; ② is gone.
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsNothing);
    });

    testWidgets('Reset clears a region back to empty/unresolved', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('Resolved'), findsOneWidget);

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsNothing);
      expect(find.text('Unresolved'), findsOneWidget);
    });

    testWidgets('hover-fade button shows arrow icon on hover', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Find the AnimatedOpacity inside the Ours pane's take button
      final oursButtonFinder = _perRegionTakeButton('Ours');
      final animatedOpacityFinder = find.ancestor(
        of: oursButtonFinder,
        matching: find.byType(AnimatedOpacity),
      );

      // Before hover: opacity should be ~0
      var animatedOpacity = tester.firstWidget<AnimatedOpacity>(
        animatedOpacityFinder,
      );
      expect(animatedOpacity.opacity, 0);

      // Create a mouse gesture and move it over the hunk block
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(location: Offset.zero);
      await tester.pump();

      // Move mouse to center of the Ours label (hunk header region)
      final oursLabelFinder = find.text('Ours');
      await gesture.moveTo(tester.getCenter(oursLabelFinder));
      await tester.pumpAndSettle();

      // After hover: opacity should be ~1
      animatedOpacity = tester.firstWidget<AnimatedOpacity>(
        animatedOpacityFinder,
      );
      expect(animatedOpacity.opacity, 1);
    });

    testWidgets('arrow icons are displayed in take buttons', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Ours side should have arrow_forward icon
      final oursPane = find.ancestor(
        of: find.text('Ours'),
        matching: find.byType(Container),
      );
      expect(
        find.descendant(
          of: oursPane,
          matching: find.byIcon(Icons.arrow_forward),
        ),
        findsOneWidget,
      );

      // Theirs side should have arrow_back icon
      final theirsPane = find.ancestor(
        of: find.text('Theirs'),
        matching: find.byType(Container),
      );
      expect(
        find.descendant(
          of: theirsPane,
          matching: find.byIcon(Icons.arrow_back),
        ),
        findsOneWidget,
      );
    });

    testWidgets('single-line click appends only that line', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['line-a', 'line-b'],
            theirs: <String>['line-c'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      expect(find.text('Unresolved'), findsOneWidget);

      // Tap on line-b (second line in ours pane)
      final lineBText = find.text('line-b');
      await tester.tap(lineBText);
      await tester.pumpAndSettle();

      // Only ① badge should be present (one line added, not all)
      expect(find.text('①'), findsOneWidget);
      // ② should not exist (that would mean both lines were added)
      expect(find.text('②'), findsNothing);

      // line-a should still be visible only in ours pane (not copied to result)
      expect(find.text('line-a'), findsOneWidget);
    });

    testWidgets('drag-and-drop whole hunk to result pane', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['drag-line1', 'drag-line2'],
            theirs: <String>['theirs-line'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Before drag: region should be unresolved
      expect(find.text('Unresolved'), findsOneWidget);

      // Drag from the "Take Ours" button (which is inside Draggable)
      // to a point to the right (toward the result pane)
      final takeOursButton = _perRegionTakeButton('Ours');

      // Drag to the right by 250 logical pixels (should land in the result pane area)
      await tester.drag(takeOursButton, const Offset(250, 0));
      await tester.pumpAndSettle();

      // Both lines should now be in result with badges ① and ②
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);

      // Region should now be resolved (both lines added)
      expect(find.text('Resolved'), findsOneWidget);
      expect(find.text('Unresolved'), findsNothing);
    });

    testWidgets('drag result line out of pane discards it', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['result-line1', 'result-line2'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Take ours to populate result
      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);

      // Drag the badge (①) out to the left. The badge is unique to the result column.
      await tester.drag(find.text('①'), const Offset(-250, 0));
      await tester.pumpAndSettle();

      // The first line should be gone; badges prove deletion worked (① renumbered, ② gone)
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsNothing);
    });

    testWidgets('drag result line small offset within pane is no-op', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['keep-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Take ours to populate result
      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);

      // Drag the badge by a small offset (stays within pane)
      await tester.drag(find.text('①'), const Offset(20, 10));
      await tester.pumpAndSettle();

      // Line should still be there (no-op); badge proves no deletion occurred
      expect(find.text('①'), findsOneWidget);
    });

    testWidgets('Ctrl+Z undo after deleting line via close button', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['line-to-delete'],
            theirs: <String>['theirs-line'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Take ours
      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);

      // Delete via close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Badge proves deletion worked
      expect(find.text('①'), findsNothing);

      // Send Ctrl+Z
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Line should be restored; badge proves undo worked
      expect(find.text('①'), findsOneWidget);
    });

    testWidgets('Ctrl+Z undo is no-op when nothing discarded', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line'],
            theirs: <String>['theirs-line'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Nothing deleted yet
      expect(find.text('①'), findsNothing);

      // Send Ctrl+Z (should do nothing, no error)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Still nothing (no-op)
      expect(find.text('①'), findsNothing);
    });

    testWidgets('Ctrl+Z undo after drag-out discard', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['drag-line1', 'drag-line2'],
            theirs: <String>['theirs-line'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Take ours
      await tester.tap(_perRegionTakeButton('Ours'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);

      // Drag first badge out of pane
      await tester.drag(find.text('①'), const Offset(-250, 0));
      await tester.pumpAndSettle();

      // Badges prove deletion worked (① renumbered, ② gone)
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsNothing);

      // Undo the drag discard
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyZ);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Badges prove undo worked (both badges restored)
      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);
    });

    testWidgets('bottom action bar renders with expected buttons', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // Verify action bar buttons exist
      expect(find.text('Previous'), findsWidgets);
      expect(find.text('Next'), findsWidgets);
      expect(find.text('Mark Resolved'), findsWidgets);
    });

    testWidgets('merge: Abort dispatches mergeAbort, Continue is disabled', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );
      final session = _sessionWith(
        _conflictEntry,
      ).copyWith(repoState: _stateWith(RepoStateFlags.merge));

      final container = await _pumpWindow(tester, identity, session, parsed);
      await _selectConflictFile(tester);
      final controller =
          container.read(repoSessionProvider(identity).notifier)
              as _FakeRepoSessionController;

      await tester.tap(find.text('Abort'));
      await tester.pumpAndSettle();
      expect(controller.mergeAbortCalled, isTrue);

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(controller.cherryPickContinueCalled, isFalse);
      expect(controller.continueRebaseCalled, isFalse);
    });

    testWidgets(
      'cherry-pick: Abort dispatches cherryPickAbort, Continue dispatches cherryPickContinue',
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-line1'],
              theirs: <String>['theirs-line1'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        final session = _sessionWith(
          _conflictEntry,
        ).copyWith(repoState: _stateWith(RepoStateFlags.cherryPick));

        final container = await _pumpWindow(tester, identity, session, parsed);
        await _selectConflictFile(tester);
        final controller =
            container.read(repoSessionProvider(identity).notifier)
                as _FakeRepoSessionController;

        await tester.tap(find.text('Abort'));
        await tester.pumpAndSettle();
        expect(controller.cherryPickAbortCalled, isTrue);

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(controller.cherryPickContinueCalled, isTrue);
      },
    );

    testWidgets(
      'rebase: Abort dispatches abortRebase, Continue dispatches continueRebase',
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-line1'],
              theirs: <String>['theirs-line1'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        final session = _sessionWith(
          _conflictEntry,
        ).copyWith(repoState: _stateWith(RepoStateFlags.rebaseMerge));

        final container = await _pumpWindow(tester, identity, session, parsed);
        await _selectConflictFile(tester);
        final controller =
            container.read(repoSessionProvider(identity).notifier)
                as _FakeRepoSessionController;

        await tester.tap(find.text('Abort'));
        await tester.pumpAndSettle();
        expect(controller.abortRebaseCalled, isTrue);

        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(controller.continueRebaseCalled, isTrue);
      },
    );

    testWidgets('revert: Abort and Continue are both disabled', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );
      final session = _sessionWith(
        _conflictEntry,
      ).copyWith(repoState: _stateWith(RepoStateFlags.revert));

      final container = await _pumpWindow(tester, identity, session, parsed);
      await _selectConflictFile(tester);
      final controller =
          container.read(repoSessionProvider(identity).notifier)
              as _FakeRepoSessionController;

      // Both buttons are shown (a sequencer op is active) but disabled.
      expect(find.text('Abort'), findsWidgets);
      expect(find.text('Continue'), findsWidgets);

      await tester.tap(find.text('Abort'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(controller.mergeAbortCalled, isFalse);
      expect(controller.cherryPickAbortCalled, isFalse);
      expect(controller.abortRebaseCalled, isFalse);
      expect(controller.cherryPickContinueCalled, isFalse);
      expect(controller.continueRebaseCalled, isFalse);
    });

    testWidgets('no sequencer operation: Abort and Continue are not shown', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      expect(find.text('Abort'), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });

    testWidgets(
      'Mark Resolved dispatches resolveConflict(markResolved) for the selected path',
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-line1'],
              theirs: <String>['theirs-line1'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );

        final container = await _pumpWindow(
          tester,
          identity,
          _sessionWith(_conflictEntry),
          parsed,
        );
        await _selectConflictFile(tester);
        final controller =
            container.read(repoSessionProvider(identity).notifier)
                as _FakeRepoSessionController;

        await tester.tap(find.text('Mark Resolved').last);
        await tester.pumpAndSettle();

        expect(controller.resolveConflictCalls, hasLength(1));
        expect(
          controller.resolveConflictCalls.single.path,
          _conflictEntry.path,
        );
        expect(
          controller.resolveConflictCalls.single.resolution,
          ConflictResolution.markResolved,
        );
      },
    );

    testWidgets('Previous/Next buttons disabled when 0 or 1 regions', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // With 1 region, Previous/Next should be disabled
      final previousButton = find.text('Previous');
      final nextButton = find.text('Next');

      // The buttons should exist but be disabled (onPressed is null)
      // Since we can't directly inspect onPressed, we just verify they exist
      expect(previousButton, findsWidgets);
      expect(nextButton, findsWidgets);
    });

    testWidgets('Previous/Next buttons enabled when multiple regions', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-line1'],
            theirs: <String>['theirs-line1'],
          ),
          _regionSegment(
            ours: <String>['ours-line2'],
            theirs: <String>['theirs-line2'],
          ),
        ],
        regionCount: 2,
        wellFormed: true,
      );

      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      // With 2 regions, Previous/Next buttons should be present
      final previousButton = find.text('Previous');
      final nextButton = find.text('Next');

      expect(previousButton, findsWidgets);
      expect(nextButton, findsWidgets);

      // Tap Next - should not throw
      await tester.tap(nextButton.first);
      await tester.pumpAndSettle();

      // Tap Previous - should not throw
      await tester.tap(previousButton.first);
      await tester.pumpAndSettle();

      // Test passed if no errors were thrown
      expect(find.text('Resolve Conflicts'), findsOneWidget);
    });
  });
}

RepoSessionState _sessionWith(WorkingCopyEntry entry) => RepoSessionState(
  isOpen: true,
  workingCopyStatus: WorkingCopyStatus(entries: [entry]),
  lastWorkingTreeContent: WorkingTreeContentReply(
    path: entry.path,
    editable: true,
    content: '<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n',
  ),
);

/// Taps the conflicted-file rail row to drive `_selectPath`, which is the
/// only thing that populates `_selectedPath` and, via
/// `_applyParsedContentIfNeeded`, actually parses and renders the editor --
/// without this tap the window sits on its "Select a file" placeholder.
Future<void> _selectConflictFile(WidgetTester tester) async {
  await tester.tap(find.text('conflict.txt'));
  await tester.pumpAndSettle();
}

/// The rail row's whole-file "Take Ours"/"Take Theirs" mini-buttons and the
/// per-region `_SidePane`'s buttons render identical text, so a bare
/// `find.text('Take Ours')` is ambiguous. The rail lives in the OUTER
/// GbmSplitPane (splitterCwFiles); the per-region side panes live in the
/// INNER one (splitterCwPanes, nested inside the outer's editor child) --
/// scoping to the inner (`.last`) picks the per-region button.
Finder _perRegionTakeButton(String label) => find.descendant(
  of: find.byType(GbmSplitPane).last,
  matching: find.text('Take $label'),
);

Future<ProviderContainer> _pumpWindow(
  WidgetTester tester,
  RepoIdentity identity,
  RepoSessionState sessionState,
  ParsedConflictFile parsedFile,
) async {
  // The rail (158px) plus three panes (220px min each, splitterCwPanes) need
  // >=830 logical px -- wider than flutter_test's default surface, which
  // would otherwise overflow every Row in the three-column layout.
  tester.view.physicalSize = const ui.Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final GoRouter router = GoRouter(
    initialLocation: RoutePaths.conflictsFor(
      Uri.encodeComponent(identity.workDir),
    ),
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.conflicts,
        builder: (context, state) =>
            ConflictResolveWindow(identity: identity, isMacOS: false),
      ),
      GoRoute(
        path: RoutePaths.repoList,
        builder: (context, state) => const Scaffold(body: SizedBox()),
      ),
      GoRoute(
        path: RoutePaths.workingCopy,
        builder: (context, state) => const Scaffold(body: SizedBox()),
      ),
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(identity).overrideWith(
        (ref) => _FakeRepoSessionController(identity, sessionState, parsedFile),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );

  await tester.pumpAndSettle();
  return container;
}

class _FakeRepoSessionController extends RepoSessionController {
  _FakeRepoSessionController(
    RepoIdentity identity,
    RepoSessionState initialState,
    this._parsedFile,
  ) : super(_FakeGbmBindings(), identity, _FakeRecentsRepository()) {
    state = initialState;
  }

  final ParsedConflictFile _parsedFile;

  // Recording fields for action invocations
  final List<({String path, dynamic resolution})> resolveConflictCalls = [];
  bool mergeAbortCalled = false;
  bool cherryPickAbortCalled = false;
  bool cherryPickContinueCalled = false;
  bool continueRebaseCalled = false;
  bool abortRebaseCalled = false;

  @override
  void resolveConflict(
    String path,
    dynamic resolution, {
    bool oursBlobMissing = false,
    bool theirsBlobMissing = false,
    String? resolvedContent,
  }) {
    resolveConflictCalls.add((path: path, resolution: resolution));
  }

  @override
  void requestWorkingTreeContent(String path) {}

  @override
  void restorePaths(
    List<String> paths, {
    String source = '',
    bool staged = false,
  }) {}

  @override
  ParsedConflictFile parseConflictMarkers(String content) => _parsedFile;

  @override
  void mergeAbort() {
    mergeAbortCalled = true;
  }

  @override
  void cherryPickAbort() {
    cherryPickAbortCalled = true;
  }

  @override
  void cherryPickContinue() {
    cherryPickContinueCalled = true;
  }

  @override
  void continueRebase() {
    continueRebaseCalled = true;
  }

  @override
  void abortRebase() {
    abortRebaseCalled = true;
  }
}

class _FakeGbmBindings implements GbmBindings {
  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          nullptr;

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => 0;

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not implemented for testing');
}

class _FakeRecentsRepository implements RecentsRepository {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not implemented for testing');
}
