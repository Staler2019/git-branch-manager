// Spec page 13's batch-delete confirmation: 「逐項列出名稱與未 push 的
// commit 數，並區分「本地」與「遠端」兩份清單，不用一句「刪除 3 個分支？」
// 概括」.
//
// The two assertions that matter most here are the ones a plain
// "does it render" test would miss: `ahead` is meaningless without an
// upstream (rendering it literally claims "0 unpushed" for a branch where
// *everything* is unpushed), and the remote name must come from
// remoteBranchParts, not a first-slash split -- the latter is the live #74
// bug in the sibling single-branch dialog and would send `refs` as a remote
// name.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/delete_branches/delete_branches_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

RefInfo _branch(
  String name, {
  String upstream = '',
  int ahead = 0,
  bool isHead = false,
}) => RefInfo(
  fullName: 'refs/heads/$name',
  shortName: name,
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: upstream,
  ahead: ahead,
  behind: 0,
  // Deliberately *not* derived from `upstream`: a fixture that computes one
  // field from another cannot falsify code that makes the same wrong
  // derivation (CLAUDE.md's Tier 0c note). `false` with a populated
  // upstream is the real in-sync case that trips hasTrackingInfo.
  hasTrackingInfo: false,
  isGone: false,
  isHead: isHead,
  isSymbolic: false,
  worktreePath: '',
);

RefSnapshot _snapshot(List<RefInfo> refs) => RefSnapshot(
  head: const HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: '',
  ),
  refs: refs,
  refCountGuardTripped: false,
  totalRefCount: refs.length,
);

Future<FakeRepoSessionController> _pump(
  WidgetTester tester,
  List<String> names,
  List<RefInfo> refs,
) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    RepoSessionState(refs: _snapshot(refs)),
  );
  // The dialog calls context.pop() after dispatching, so it has to sit on
  // top of something -- a single-route router throws "nothing to pop" and
  // the delete assertions never run.
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/dialog',
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: DeleteBranchesDialogContent(identity: _identity, names: names),
        ),
      ),
    ],
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      repoSessionProvider(_identity).overrideWith((Ref ref) => fake),
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
  router.push('/dialog');
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  group('deleteBranchLines', () {
    test('a branch with no upstream reports null, not 0 unpushed commits', () {
      final List<DeleteBranchLine> lines = deleteBranchLines(<String>[
        'solo',
      ], _snapshot(<RefInfo>[_branch('solo')]));
      expect(lines.single.unpushed, isNull);
      expect(lines.single.hasUpstream, isFalse);
    });

    test('the remote comes from the full upstream ref, not a first-slash '
        'split (#74)', () {
      final List<DeleteBranchLine> lines = deleteBranchLines(
        <String>['feature/x'],
        _snapshot(<RefInfo>[
          _branch(
            'feature/x',
            upstream: 'refs/remotes/upstream/feature/x',
            ahead: 2,
          ),
        ]),
      );
      expect(lines.single.remote, 'upstream');
      expect(lines.single.unpushed, 2);
    });

    test('a name with no matching ref still gets a line', () {
      final List<DeleteBranchLine> lines = deleteBranchLines(<String>[
        'vanished',
      ], _snapshot(const <RefInfo>[]));
      expect(lines.single.name, 'vanished');
      expect(lines.single.unpushed, isNull);
    });
  });

  group('DeleteBranchesDialogContent', () {
    testWidgets('lists every branch by name with its own unpushed count', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        <String>['a', 'b'],
        <RefInfo>[
          _branch('a', upstream: 'refs/remotes/origin/a', ahead: 3),
          _branch('b'),
        ],
      );
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('3 unpushed commits'), findsOneWidget);
      expect(
        find.text('no upstream — nothing has been pushed'),
        findsOneWidget,
      );
      expect(find.text('Local branches'), findsOneWidget);
      expect(find.text('Remote branches'), findsOneWidget);
      expect(find.text('origin/a'), findsOneWidget);
    });

    testWidgets('a selection with no upstreams has no remote section at all', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <String>['a'], <RefInfo>[_branch('a')]);
      expect(find.text('Remote branches'), findsNothing);
      expect(find.text('Also delete on the remote'), findsNothing);
    });

    testWidgets('deleting issues one call for every local branch, not N', (
      WidgetTester tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        <String>['a', 'b'],
        <RefInfo>[
          _branch('a', upstream: 'refs/remotes/origin/a'),
          _branch('b'),
        ],
      );
      await tester.tap(find.text('Delete 2 branches').last);
      await tester.pumpAndSettle();

      final List<FakeCommand> deletes = fake.commandLog
          .where((FakeCommand c) => c.name == 'deleteBranch')
          .toList();
      expect(deletes, hasLength(1));
      expect(deletes.single.args['names'], <String>['a', 'b']);
      expect(deletes.single.args['isRemote'], isFalse);
    });

    testWidgets('"Also delete on the remote" adds one call per remote', (
      WidgetTester tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        <String>['a', 'b', 'c'],
        <RefInfo>[
          _branch('a', upstream: 'refs/remotes/origin/a'),
          _branch('b', upstream: 'refs/remotes/fork/b'),
          _branch('c'),
        ],
      );
      await tester.tap(find.text('Also delete on the remote'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete 3 branches').last);
      await tester.pumpAndSettle();

      final List<FakeCommand> deletes = fake.commandLog
          .where((FakeCommand c) => c.name == 'deleteBranch')
          .toList();
      expect(deletes, hasLength(3));
      expect(deletes[0].args['names'], <String>['a', 'b', 'c']);
      expect(
        deletes.skip(1).map((FakeCommand c) => c.args['remoteName']).toSet(),
        <String>{'origin', 'fork'},
        reason: 'grouped by remote; the untracked branch c is not in either',
      );
      for (final FakeCommand remote in deletes.skip(1)) {
        expect(remote.args['isRemote'], isTrue);
      }
    });

    testWidgets('the force checkbox reaches every call', (
      WidgetTester tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        <String>['a'],
        <RefInfo>[_branch('a', upstream: 'refs/remotes/origin/a')],
      );
      await tester.tap(find.text('Delete even if not fully merged'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete 1 branches').last);
      await tester.pumpAndSettle();

      expect(
        fake.commandLog
            .where((FakeCommand c) => c.name == 'deleteBranch')
            .every((FakeCommand c) => c.args['force'] == true),
        isTrue,
      );
    });
  });
}
