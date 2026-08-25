// Verifies the 05-I (Conflict hunk) context menu -- a right-click on a
// line inside either side pane of ConflictResolveWindow -- reaches the
// real per-region ConflictLineOrderState the same way the existing
// click/drag interactions do. conflict_hunk_menu_items_test.dart already
// covers the item list itself in isolation; this covers the dispatch
// path that tier structurally cannot, the same gap closed for
// 05-C/05-H/05-D/05-J. Mirrors conflict_resolve_window_test.dart's
// `_pumpWindow` harness (that file's own private helpers aren't
// importable from here).
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_conflict_file.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart'
    show RepoSessionState, WorkingTreeContentReply, repoSessionProvider;
import 'package:gbm_flutter/features/conflict_resolution/conflict_resolve_window.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

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

RepoSessionState _sessionWith(WorkingCopyEntry entry) => RepoSessionState(
  isOpen: true,
  workingCopyStatus: WorkingCopyStatus(entries: [entry]),
  lastWorkingTreeContent: WorkingTreeContentReply(
    path: entry.path,
    editable: true,
    content: '<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> branch\n',
  ),
);

Future<void> _selectConflictFile(WidgetTester tester) async {
  await tester.tap(find.text('conflict.txt'));
  await tester.pumpAndSettle();
}

/// Once a region is resolved, its assembled text also appears in the
/// bottom "Result (editable)" TextField, and the source line stays
/// visible in its own side pane too -- so a bare `find.text(line)` can
/// become ambiguous after a region resolves. Scopes to the "Ours"/
/// "Theirs" side pane's own Container (same ancestor pattern
/// conflict_resolve_window_test.dart's own tests use), which is the one
/// place the source line always renders exactly once regardless of
/// resolution state.
Finder _sourceLine(String paneLabel, String line) => find.descendant(
  of: find.ancestor(of: find.text(paneLabel), matching: find.byType(Container)),
  matching: find.text(line),
);

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  addTearDown(gesture.removePointer);
  await gesture.down(tester.getCenter(finder));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _pumpWindow(
  WidgetTester tester,
  RepoIdentity identity,
  RepoSessionState sessionState,
  ParsedConflictFile parsedFile,
) async {
  // Same sizing as conflict_resolve_window_test.dart's _pumpWindow -- the
  // three-column layout overflows flutter_test's default surface
  // otherwise.
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
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(identity).overrideWith(
        (ref) => FakeRepoSessionController(
          identity,
          sessionState,
          parsedFile: parsedFile,
        ),
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

void main() {
  final RepoIdentity identity = RepoIdentity(
    workDir: '/test/repo',
    gitDir: '/test/repo/.git',
  );

  group('conflict hunk context menu (05-I)', () {
    testWidgets('right-clicking a line in a side pane opens its 05-I menu', (
      tester,
    ) async {
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

      await _rightClick(tester, find.text('ours-line'));

      expect(find.text('Take this side'), findsOneWidget);
      expect(find.text('Take this line only'), findsOneWidget);
      expect(find.text('Take both — this side first'), findsOneWidget);
      expect(find.text('Open in external merge tool'), findsOneWidget);
      expect(find.text('Discard from result'), findsOneWidget);
    });

    testWidgets('Take this side appends every line of that side, not just '
        'the clicked one', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-a', 'ours-b'],
            theirs: <String>['theirs-a'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );
      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      await _rightClick(tester, find.text('ours-a'));
      await tester.tap(find.text('Take this side'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsOneWidget);
    });

    testWidgets('Take this line only appends just the clicked line', (
      tester,
    ) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-a', 'ours-b'],
            theirs: <String>['theirs-a'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );
      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      await _rightClick(tester, find.text('ours-b'));
      await tester.tap(find.text('Take this line only'));
      await tester.pumpAndSettle();

      expect(find.text('①'), findsOneWidget);
      expect(find.text('②'), findsNothing);
    });

    testWidgets(
      'Take both — this side first appends this side\'s lines, then the '
      'other side\'s',
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-a'],
              theirs: <String>['theirs-a'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        await _pumpWindow(
          tester,
          identity,
          _sessionWith(_conflictEntry),
          parsed,
        );
        await _selectConflictFile(tester);

        await _rightClick(tester, find.text('ours-a'));
        await tester.tap(find.text('Take both — this side first'));
        await tester.pumpAndSettle();

        // Both lines now appear twice each: once in their own source side
        // pane, once in the result -- ① is this side's (ours), ② is the
        // other side's (theirs), confirming both landed and in order.
        expect(find.text('①'), findsOneWidget);
        expect(find.text('②'), findsOneWidget);
        expect(find.text('Resolved'), findsOneWidget);
      },
    );

    testWidgets(
      'Discard from result is disabled while the region has nothing in '
      'its result yet',
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-a'],
              theirs: <String>['theirs-a'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        await _pumpWindow(
          tester,
          identity,
          _sessionWith(_conflictEntry),
          parsed,
        );
        await _selectConflictFile(tester);

        expect(find.text('Unresolved'), findsOneWidget);

        await _rightClick(tester, find.text('ours-a'));
        await tester.tap(find.text('Discard from result'));
        await tester.pumpAndSettle();

        // No crash and no change -- disabled items simply no-op on tap.
        expect(find.text('Unresolved'), findsOneWidget);
      },
    );

    testWidgets(
      'Discard from result resets the region back to unresolved once it '
      'has something to discard',
      (tester) async {
        final parsed = ParsedConflictFile(
          segments: <ConflictSegment>[
            _regionSegment(
              ours: <String>['ours-a'],
              theirs: <String>['theirs-a'],
            ),
          ],
          regionCount: 1,
          wellFormed: true,
        );
        await _pumpWindow(
          tester,
          identity,
          _sessionWith(_conflictEntry),
          parsed,
        );
        await _selectConflictFile(tester);

        await _rightClick(tester, find.text('ours-a'));
        await tester.tap(find.text('Take this side'));
        await tester.pumpAndSettle();
        expect(find.text('Resolved'), findsOneWidget);

        await _rightClick(tester, _sourceLine('Ours', 'ours-a'));
        await tester.tap(find.text('Discard from result'));
        await tester.pumpAndSettle();

        expect(find.text('Unresolved'), findsOneWidget);
        expect(find.text('Resolved'), findsNothing);
      },
    );

    testWidgets('Open in external merge tool is disabled -- no external tool '
        'integration exists', (tester) async {
      final parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          _regionSegment(
            ours: <String>['ours-a'],
            theirs: <String>['theirs-a'],
          ),
        ],
        regionCount: 1,
        wellFormed: true,
      );
      await _pumpWindow(tester, identity, _sessionWith(_conflictEntry), parsed);
      await _selectConflictFile(tester);

      await _rightClick(tester, find.text('ours-a'));
      await tester.tap(find.text('Open in external merge tool'));
      await tester.pumpAndSettle();

      expect(find.text('Unresolved'), findsOneWidget);
    });
  });
}
