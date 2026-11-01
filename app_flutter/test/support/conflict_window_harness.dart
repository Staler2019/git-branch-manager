// Pumps the conflict-resolve window on one conflicted file, for tests that
// drive its three columns rather than its rail.
import 'dart:ui' as ui;

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

import 'fake_repo_session.dart';

const String kConflictPath = 'conflict.txt';

/// A region segment with no common ancestor.
ConflictSegment conflictRegion(List<String> ours, List<String> theirs) =>
    ConflictSegment(
      kind: ConflictSegmentKind.region,
      lines: const <String>[],
      ours: ours,
      theirs: theirs,
      base: const <String>[],
      hasBase: false,
    );

/// A text segment of [lines], each ending in a newline as the parser keeps
/// them.
ConflictSegment conflictText(List<String> lines) => ConflictSegment(
  kind: ConflictSegmentKind.text,
  lines: <String>[for (final String l in lines) '$l\n'],
  ours: const <String>[],
  theirs: const <String>[],
  base: const <String>[],
  hasBase: false,
);

/// Pumps the window on [parsed] at [size] and selects its file, so the three
/// columns are on screen.
Future<void> pumpConflictWindow(
  WidgetTester tester,
  ParsedConflictFile parsed, {
  Map<String, Object> prefs = const <String, Object>{},
  ui.Size size = const ui.Size(1400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  final SharedPreferences sharedPrefs = await SharedPreferences.getInstance();
  final RepoIdentity identity = RepoIdentity(
    workDir: '/test/repo',
    gitDir: '/test/repo/.git',
  );
  final GoRouter router = GoRouter(
    initialLocation: RoutePaths.conflictsFor(
      Uri.encodeComponent(identity.workDir),
    ),
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.conflicts,
        builder: (BuildContext context, GoRouterState state) =>
            ConflictResolveWindow(identity: identity, isMacOS: false),
      ),
    ],
  );
  const WorkingCopyEntry entry = WorkingCopyEntry(
    path: kConflictPath,
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
  final ProviderContainer container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(sharedPrefs),
      repoSessionProvider(identity).overrideWith(
        (ref) => FakeRepoSessionController(
          identity,
          RepoSessionState(
            isOpen: true,
            workingCopyStatus: const WorkingCopyStatus(
              entries: <WorkingCopyEntry>[entry],
            ),
            lastWorkingTreeContent: const WorkingTreeContentReply(
              path: kConflictPath,
              editable: true,
              content: '<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> b\n',
            ),
          ),
          parsedFile: parsed,
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
  await tester.tap(find.text(kConflictPath));
  await tester.pumpAndSettle();
}
