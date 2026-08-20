import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/rename_branch/rename_branch_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/tmp/repo',
  gitDir: '/tmp/repo/.git',
);

RefInfo _branch(
  String shortName, {
  String upstream = '',
  int ahead = 0,
  bool isHead = false,
}) {
  return RefInfo(
    fullName: 'refs/heads/$shortName',
    shortName: shortName,
    kind: RefKind.localBranch,
    target: 'a' * 40,
    upstream: upstream,
    ahead: ahead,
    behind: 0,
    hasTrackingInfo: upstream.isNotEmpty,
    isGone: false,
    isHead: isHead,
    isSymbolic: false,
    worktreePath: '',
  );
}

const WorkingCopyEntry _conflictEntry = WorkingCopyEntry(
  path: 'lib/main.dart',
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

RepoSessionState _sessionWith(
  List<RefInfo> branches, {
  String head = 'feature/lane-allocator',
  bool conflicted = false,
}) {
  return RepoSessionState(
    isOpen: true,
    refs: RefSnapshot(
      head: HeadInfo(
        kind: HeadKind.branch,
        branchName: head,
        fullRef: 'refs/heads/$head',
        target: 'a' * 40,
      ),
      refs: branches,
      refCountGuardTripped: false,
      totalRefCount: branches.length,
    ),
    workingCopyStatus: WorkingCopyStatus(
      entries: conflicted
          ? const <WorkingCopyEntry>[_conflictEntry]
          : const <WorkingCopyEntry>[],
    ),
  );
}

Future<FakeRepoSessionController> _pumpDialog(
  WidgetTester tester, {
  required RepoSessionState initialState,
  String? branchName,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    initialState,
  );

  // A real router, not a bare `home:` -- the confirm button calls
  // context.pop(), which only exists once GoRouter is in the tree.
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/dialog',
        builder: (context, state) => RenameBranchDialogContent(
          identity: _identity,
          branchName: branchName,
        ),
      ),
    ],
  );

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

/// Finds the Rename button's onPressed, which is null while disabled -- the
/// signal spec page 13's RENAMEVALID table describes for every invalid case.
bool _renameEnabled(WidgetTester tester) {
  final Finder button = find.widgetWithText(InkWell, 'Rename');
  // Deliberately not defaulting to false when the button cannot be found: a
  // missing button would otherwise satisfy every `isFalse` assertion below
  // and turn a real regression into a passing test.
  expect(button, findsWidgets, reason: 'the Rename button should be rendered');
  return tester.widget<InkWell>(button.first).onTap != null;
}

void main() {
  final List<RefInfo> branches = <RefInfo>[
    _branch(
      'feature/lane-allocator',
      upstream: 'refs/remotes/origin/feature/lane-allocator',
      ahead: 2,
      isHead: true,
    ),
    _branch('main'),
  ];

  group('RenameBranchDialogContent', () {
    testWidgets('seeds the field with the current branch name and shows it '
        'read-only above (spec P13 A: 目前名稱 / 新名稱)', (tester) async {
      await _pumpDialog(tester, initialState: _sessionWith(branches));

      expect(find.text('Current name'), findsOneWidget);
      expect(find.text('New name'), findsOneWidget);
      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'feature/lane-allocator');
    });

    testWidgets('an unchanged name keeps Rename disabled with no error text '
        '(RENAMEVALID: 未改動 -> disabled, 不出現錯誤紅字)', (tester) async {
      await _pumpDialog(tester, initialState: _sessionWith(branches));

      expect(_renameEnabled(tester), isFalse);
      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.errorText, isNull);
    });

    testWidgets('a duplicate name names the branch it collides with and '
        'disables Rename (RENAMEVALID: 名稱重複)', (tester) async {
      await _pumpDialog(tester, initialState: _sessionWith(branches));

      await tester.enterText(find.byType(TextField), 'main');
      await tester.pumpAndSettle();

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.errorText, contains('main'));
      expect(_renameEnabled(tester), isFalse);
    });

    testWidgets('an illegal character disables Rename '
        '(RENAMEVALID: 含 git 不允許的字元)', (tester) async {
      await _pumpDialog(tester, initialState: _sessionWith(branches));

      await tester.enterText(find.byType(TextField), 'has space');
      await tester.pumpAndSettle();

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.decoration!.errorText, isNotNull);
      expect(_renameEnabled(tester), isFalse);
    });

    testWidgets('a valid new name shows the availability line and enables '
        'Rename', (tester) async {
      await _pumpDialog(tester, initialState: _sessionWith(branches));

      await tester.enterText(
        find.byType(TextField),
        'feature/lane-allocator-v2',
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Available'), findsOneWidget);
      expect(_renameEnabled(tester), isTrue);
    });

    testWidgets('the default remote choice renames on the remote too, and '
        'sends the remote name recovered from the full upstream ref', (
      tester,
    ) async {
      final FakeRepoSessionController controller = await _pumpDialog(
        tester,
        initialState: _sessionWith(branches),
      );

      await tester.enterText(
        find.byType(TextField),
        'feature/lane-allocator-v2',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      final FakeCommand command = controller.commandLog.single;
      expect(command.name, 'renameBranch');
      expect(command.args['from'], 'feature/lane-allocator');
      expect(command.args['to'], 'feature/lane-allocator-v2');
      expect(command.args['renameRemote'], isTrue);
      // RefInfo.upstream is `refs/remotes/origin/feature/lane-allocator`;
      // splitting it on the first slash would send "refs".
      expect(command.args['remoteName'], 'origin');
    });

    testWidgets('choosing local-only sends renameRemote false and no remote '
        'name (spec P13: 只改本地，upstream 會清空)', (tester) async {
      final FakeRepoSessionController controller = await _pumpDialog(
        tester,
        initialState: _sessionWith(branches),
      );

      await tester.enterText(
        find.byType(TextField),
        'feature/lane-allocator-v2',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Rename locally'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      final FakeCommand command = controller.commandLog.single;
      expect(command.args['renameRemote'], isFalse);
      expect(command.args['remoteName'], '');
    });

    testWidgets('a branch with no upstream offers no remote choice at all', (
      tester,
    ) async {
      final FakeRepoSessionController controller = await _pumpDialog(
        tester,
        initialState: _sessionWith(<RefInfo>[
          _branch('local-only', isHead: true),
        ], head: 'local-only'),
      );

      expect(find.text('Remote handling'), findsNothing);

      await tester.enterText(find.byType(TextField), 'renamed');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(controller.commandLog.single.args['renameRemote'], isFalse);
    });

    testWidgets('the warning reports the real unpushed commit count', (
      tester,
    ) async {
      await _pumpDialog(tester, initialState: _sessionWith(branches));

      expect(find.textContaining('2 commit(s) not yet pushed'), findsOneWidget);
    });

    testWidgets('renames the branch named by the route, not the current one', (
      tester,
    ) async {
      final FakeRepoSessionController controller = await _pumpDialog(
        tester,
        initialState: _sessionWith(branches),
        branchName: 'main',
      );

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, 'main');

      await tester.enterText(find.byType(TextField), 'trunk');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();

      expect(controller.commandLog.single.args['from'], 'main');
    });

    testWidgets('mid-conflict the dialog refuses to offer a rename at all '
        '(RENAMEVALID: 分支正在被 rebase / merge 佔用)', (tester) async {
      final FakeRepoSessionController controller = await _pumpDialog(
        tester,
        initialState: _sessionWith(branches, conflicted: true),
      );

      // No name field and no destructive button -- only a way out, the same
      // shape the discard-changes dialog uses for a request it cannot honour.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Rename'), findsNothing);
      expect(find.text('Close'), findsOneWidget);
      expect(controller.commandLog, isEmpty);
    });
  });
}
