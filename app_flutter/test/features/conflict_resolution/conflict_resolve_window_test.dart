import 'dart:ffi';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/parsed_conflict_file.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart'
    show
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

Future<void> _pumpWindow(
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
        builder: (context, state) => ConflictResolveWindow(identity: identity),
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

  @override
  void resolveConflict(
    String path,
    dynamic resolution, {
    bool oursBlobMissing = false,
    bool theirsBlobMissing = false,
    String? resolvedContent,
  }) {}

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
