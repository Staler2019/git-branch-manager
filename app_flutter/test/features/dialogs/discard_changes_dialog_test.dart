// Widget coverage for the second half of the discard chain: a parsed
// [DiscardChangesRequest] -> the dialog -> the controller command it fires.
// `discard_changes_request_test.dart` covers the URL -> request half.
//
// What makes this worth pinning: the same danger button reaches two commands
// with very different blast radii -- `discardLines` rewrites a handful of
// lines, `restorePaths` rewrites whole files -- so "which one did it call"
// is the assertion, not just "something happened".
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/discard_changes/discard_changes_dialog.dart';
import 'package:gbm_flutter/features/dialogs/discard_changes/discard_changes_request.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/discard-repo',
  gitDir: '/test/discard-repo/.git',
);

/// Pumps the dialog behind a real [GoRouter] -- its confirm and cancel
/// buttons both call `context.pop()`, which needs one in the tree.
Future<FakeRepoSessionController> pumpDialog(
  WidgetTester tester, {
  required DiscardChangesRequest request,
  RepoSessionState initialState = const RepoSessionState(isOpen: true),
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    initialState,
  );

  // Started at '/' and pushed, not opened as the initial location: both
  // buttons call context.pop(), which throws "there is nothing to pop" on a
  // single-entry stack. In the real app this route is always pushed over a
  // workspace, so pushing here matches production rather than working
  // around the widget.
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('under')),
      ),
      GoRoute(
        path: '/dialog',
        builder: (context, state) =>
            DiscardChangesDialogContent(identity: _identity, request: request),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        repoSessionProvider(_identity).overrideWith((ref) => controller),
      ],
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/dialog');
  await tester.pumpAndSettle();
  return controller;
}

WorkingCopyEntry _entry(String path, {bool untracked = false}) =>
    WorkingCopyEntry(
      path: path,
      oldPath: '',
      untracked: untracked,
      staged: false,
      indexStatus: FileChangeKind.modified,
      hasUnstagedChange: true,
      worktreeStatus: FileChangeKind.modified,
      unstagedAdded: 0,
      unstagedRemoved: 0,
      stagedAdded: 0,
      stagedRemoved: 0,
      conflict: ConflictKind.none,
      ancestorBlob: '',
      oursBlob: '',
      theirsBlob: '',
      similarity: 0,
      isSubmodule: false,
      isConflicted: false,
    );

void main() {
  group('line mode (05-G "Discard N lines…")', () {
    testWidgets('confirming calls discardLines, not restorePaths', (
      tester,
    ) async {
      final FakeRepoSessionController controller = await pumpDialog(
        tester,
        request: DiscardChangesRequest.lines(
          path: 'lib/main.dart',
          hunkIndex: 2,
          lineIndices: <int>[4, 5],
        ),
      );

      await tester.tap(find.text('Discard 2 lines'));
      await tester.pumpAndSettle();

      final FakeCommand command = controller.commandLog.single;
      expect(command.name, 'discardLines');
      expect(command.args['path'], 'lib/main.dart');
      expect(command.args['hunkIndex'], 2);
      expect(command.args['lineIndices'], <int>[4, 5]);
      expect(
        controller.commandLog.where(
          (FakeCommand c) => c.name == 'restorePaths',
        ),
        isEmpty,
        reason: 'restorePaths would rewrite the whole file',
      );
    });

    testWidgets('titles and labels count lines, and name the file', (
      tester,
    ) async {
      await pumpDialog(
        tester,
        request: DiscardChangesRequest.lines(
          path: 'lib/main.dart',
          hunkIndex: 0,
          lineIndices: <int>[7],
        ),
      );

      expect(find.text('Discard Line'), findsOneWidget);
      expect(find.text('Discard line'), findsOneWidget);
      expect(
        find.text('lib/main.dart'),
        findsOneWidget,
        reason: 'spec page 06: 列出實際檔名與行數',
      );
    });

    testWidgets('cancelling fires nothing at all', (tester) async {
      final FakeRepoSessionController controller = await pumpDialog(
        tester,
        request: DiscardChangesRequest.lines(
          path: 'lib/main.dart',
          hunkIndex: 1,
          lineIndices: <int>[3],
        ),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(controller.commandLog, isEmpty);
    });
  });

  group('whole-file mode (05-F "Discard changes…")', () {
    testWidgets('confirming calls restorePaths with every listed path', (
      tester,
    ) async {
      final FakeRepoSessionController controller = await pumpDialog(
        tester,
        request: const DiscardChangesRequest.wholeFiles(<String>[
          'a.dart',
          'b/c.dart',
        ]),
        initialState: RepoSessionState(
          isOpen: true,
          workingCopyStatus: WorkingCopyStatus(
            entries: <WorkingCopyEntry>[_entry('a.dart'), _entry('b/c.dart')],
          ),
        ),
      );

      await tester.tap(find.text('Discard 2 files'));
      await tester.pumpAndSettle();

      final FakeCommand command = controller.commandLog.single;
      expect(command.name, 'restorePaths');
      expect(command.args['paths'], <String>['a.dart', 'b/c.dart']);
    });

    testWidgets('untracked files are excluded from what is restored', (
      tester,
    ) async {
      final FakeRepoSessionController controller = await pumpDialog(
        tester,
        request: const DiscardChangesRequest.wholeFiles(<String>[
          'a.dart',
          'new.dart',
        ]),
        initialState: RepoSessionState(
          isOpen: true,
          workingCopyStatus: WorkingCopyStatus(
            entries: <WorkingCopyEntry>[
              _entry('a.dart'),
              _entry('new.dart', untracked: true),
            ],
          ),
        ),
      );

      await tester.tap(find.text('Discard changes'));
      await tester.pumpAndSettle();

      expect(controller.commandLog.single.args['paths'], <String>['a.dart']);
    });
  });

  group('a malformed line request refuses rather than degrading', () {
    // The failure this guards: before DiscardChangesRequest existed, a URL
    // carrying line indices but no usable hunk fell through to whole-file
    // mode -- the user asked to discard two lines and the same button would
    // have discarded the entire file.
    const DiscardChangesRequest malformed = DiscardChangesRequest.malformed(
      <String>['lib/main.dart'],
    );

    testWidgets('offers no destructive button at all', (tester) async {
      await pumpDialog(tester, request: malformed);

      expect(find.text('Discard changes'), findsNothing);
      expect(find.text('Discard line'), findsNothing);
      expect(find.text('Discard 1 lines'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
    });

    testWidgets('closing it reaches neither discardLines nor restorePaths', (
      tester,
    ) async {
      final FakeRepoSessionController controller = await pumpDialog(
        tester,
        request: malformed,
      );

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(controller.commandLog, isEmpty);
    });
  });
}
