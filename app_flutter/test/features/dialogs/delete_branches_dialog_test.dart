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
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/branch_deletion_probe.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/delete_branches/delete_branches_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_field_kinds.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

RefInfo _branch(
  String name, {
  String upstream = '',
  int ahead = 0,
  bool isHead = false,
  String target = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
}) => RefInfo(
  fullName: 'refs/heads/$name',
  shortName: name,
  kind: RefKind.localBranch,
  target: target,
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
  List<RefInfo> refs, {
  BranchDeletionProbeReply Function(List<String> names)? probe,
  FakeRepoSessionController Function(RepoSessionState)? controller,
}) async {
  final RepoSessionState initial = RepoSessionState(refs: _snapshot(refs));
  final FakeRepoSessionController fake =
      controller?.call(initial) ??
      FakeRepoSessionController(_identity, initial);
  if (probe != null) fake.branchDeletionProbe = probe;
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

/// Answers each [probeBranchDeletion] only when the test completes it, in
/// the order the reads were asked for.
class _HeldProbeController extends FakeRepoSessionController {
  _HeldProbeController(RepoSessionState state) : super(_identity, state);

  final List<Completer<BranchDeletionProbeReply>> reads =
      <Completer<BranchDeletionProbeReply>>[];

  @override
  Future<BranchDeletionProbeReply> probeBranchDeletion(List<String> names) {
    commandLog.add(
      FakeCommand('probeBranchDeletion', <String, Object?>{'names': names}),
    );
    final Completer<BranchDeletionProbeReply> read =
        Completer<BranchDeletionProbeReply>();
    reads.add(read);
    return read.future;
  }
}

ProbeCounted _counted(String name, int n, {String? tip}) => ProbeCounted(
  name,
  tipOid: tip ?? 'tip-$name',
  upstream: 'refs/remotes/origin/$name',
  unsyncedCount: n,
);

final Finder _deleteButton = find.byWidgetPredicate(
  (Widget w) => w is GbmButton && w.label.startsWith('Delete '),
);

GbmButton _button(WidgetTester tester) =>
    tester.widget<GbmButton>(_deleteButton);

List<FakeCommand> _deletes(FakeRepoSessionController fake) =>
    fake.commandLog.where((FakeCommand c) => c.name == 'deleteBranch').toList();

void main() {
  group('deleteBranchLines', () {
    test('a line carries the tip the snapshot shows', () {
      final List<DeleteBranchLine> lines = deleteBranchLines(<String>[
        'solo',
      ], _snapshot(<RefInfo>[_branch('solo', target: 'c' * 40)]));
      expect(lines.single.tip, 'c' * 40);
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
    });

    test('a name with no matching ref still gets a line', () {
      final List<DeleteBranchLine> lines = deleteBranchLines(<String>[
        'vanished',
      ], _snapshot(const <RefInfo>[]));
      expect(lines.single.name, 'vanished');
      expect(lines.single.tip, isEmpty);
    });
  });

  group('DeleteBranchesDialogContent', () {
    testWidgets('lists every branch by name with its own read count', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        <String>['a', 'b'],
        <RefInfo>[
          // `ahead` disagrees with the read on purpose: the row draws the
          // read, which counted at the tip it will send.
          _branch('a', upstream: 'refs/remotes/origin/a', ahead: 9),
          _branch('b'),
        ],
        probe: (List<String> names) => BranchDeletionProbeReply(
          probes: <BranchDeletionProbe>[
            _counted('a', 3),
            const ProbeNoReference('b', tipOid: 'tip-b'),
          ],
        ),
      );
      expect(find.text('a'), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('3 個 commit 尚未同步到 origin/a'), findsOneWidget);
      expect(find.text('沒有 upstream（或已 gone），無法確認是否已同步'), findsOneWidget);
      expect(find.text('本地分支'), findsOneWidget);
      expect(find.text('遠端分支'), findsOneWidget);
      expect(find.text('origin/a'), findsOneWidget);
    });

    testWidgets('a selection with no upstreams has no remote section at all', (
      WidgetTester tester,
    ) async {
      await _pump(tester, <String>['a'], <RefInfo>[_branch('a')]);
      expect(find.text('遠端分支'), findsNothing);
      expect(find.text('同時刪除遠端分支'), findsNothing);
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
      await tester.tap(find.text('同時刪除遠端分支'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete 3 branches').last);
      await tester.pumpAndSettle();

      final List<FakeCommand> deletes = fake.commandLog
          .where((FakeCommand c) => c.name == 'deleteBranch')
          .toList();
      expect(deletes, hasLength(1));
      expect(deletes.single.args['names'], <String>['a', 'b', 'c']);
      expect(
        deletes.single.args['thenDeleteRemote'],
        const <RemoteBranchDeletion>[
          RemoteBranchDeletion(remoteName: 'origin', names: <String>['a']),
          RemoteBranchDeletion(remoteName: 'fork', names: <String>['b']),
        ],
        reason: 'grouped by remote; the untracked branch c is not in either',
      );
    });

    // Issue 5 (A6): no global force switch. Each row is warned about up
    // front and sent by its own read -- `-d` where its upstream has every
    // commit, `-D` at the read tip otherwise.
    testWidgets('each row is sent by its own read', (
      WidgetTester tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        <String>['a', 'b', 'c', 'd'],
        <RefInfo>[
          _branch('a', upstream: 'refs/remotes/origin/a'),
          _branch('b', upstream: 'refs/remotes/origin/b'),
          _branch('c'),
          _branch('d'),
        ],
        probe: (List<String> names) => BranchDeletionProbeReply(
          probes: <BranchDeletionProbe>[
            _counted('a', 0),
            _counted('b', 2),
            const ProbeNoReference('c', tipOid: 'tip-c'),
            const ProbeNotFound('d'),
          ],
        ),
      );
      expect(find.text('即使尚未完全合併也刪除'), findsNothing);
      expect(find.text('已經不存在'), findsOneWidget);

      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();

      expect(_deletes(fake), hasLength(1));
      expect(_deletes(fake).single.args['entries'], const <DeleteBranchEntry>[
        DeleteBranchEntry.plain('a'),
        DeleteBranchEntry.forced('b', expectedTipOid: 'tip-b'),
        DeleteBranchEntry.forced('c', expectedTipOid: 'tip-c'),
      ]);
    });

    testWidgets('the warning counts the rows that will be forced', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        <String>['a', 'b', 'c'],
        <RefInfo>[_branch('a'), _branch('b'), _branch('c')],
        probe: (List<String> names) => BranchDeletionProbeReply(
          probes: <BranchDeletionProbe>[
            _counted('a', 0),
            _counted('b', 2),
            const ProbeNoReference('c', tipOid: 'tip-c'),
          ],
        ),
      );
      expect(
        find.descendant(
          of: find.byType(GbmDialogWarnField),
          matching: find.text('其中 2 個分支會直接刪除，不再檢查是否已合併。'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a row is drawn in the warning colour exactly when forced', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        <String>['a', 'b', 'c'],
        <RefInfo>[_branch('a'), _branch('b'), _branch('c')],
        probe: (List<String> names) => BranchDeletionProbeReply(
          probes: <BranchDeletionProbe>[
            _counted('a', 0),
            _counted('b', 2),
            const ProbeNoReference('c', tipOid: 'tip-c'),
          ],
        ),
      );
      final GbmColors colors = tester.element(_deleteButton).gbmColors;
      Color? colour(String text) =>
          tester.widget<Text>(find.text(text)).style?.color;

      expect(colour('已完整同步'), colors.textTertiary);
      expect(colour('2 個 commit 尚未同步到 origin/b'), colors.warning);
      expect(colour('沒有 upstream（或已 gone），無法確認是否已同步'), colors.warning);
    });

    testWidgets('a fully synced selection carries no warning', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        <String>['a'],
        <RefInfo>[_branch('a', upstream: 'refs/remotes/origin/a')],
        probe: (List<String> names) => BranchDeletionProbeReply(
          probes: <BranchDeletionProbe>[_counted('a', 0)],
        ),
      );
      expect(find.text('已完整同步'), findsOneWidget);
      expect(find.byType(GbmDialogWarnField), findsNothing);
    });

    testWidgets('while the read is in flight nothing can be deleted', (
      WidgetTester tester,
    ) async {
      late _HeldProbeController held;
      await _pump(
        tester,
        <String>['a'],
        <RefInfo>[_branch('a')],
        controller: (RepoSessionState s) => held = _HeldProbeController(s),
      );
      expect(find.text('計算中…'), findsOneWidget);
      expect(_button(tester).onPressed, isNull);

      held.reads.single.complete(
        BranchDeletionProbeReply(
          probes: <BranchDeletionProbe>[_counted('a', 1)],
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('計算中…'), findsNothing);
      expect(_button(tester).onPressed, isNotNull);
    });

    testWidgets('a failed read is shown and deletes nothing', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        <String>['a'],
        <RefInfo>[_branch('a')],
        probe: (List<String> names) => const BranchDeletionProbeReply(
          probes: <BranchDeletionProbe>[],
          error: GitError(
            code: 13,
            codeName: 'ProcessFailed',
            message: 'broken',
            detail: '',
            argv: <String>[],
            exitCode: 128,
          ),
        ),
      );
      expect(find.text('無法確認尚未同步的 commit：broken'), findsOneWidget);
      expect(_button(tester).onPressed, isNull);
    });

    // Core never sends probes with an error (the whole read fails); this
    // reply is synthetic, and pins that the dialog fails closed if it ever
    // did rather than trust a count from a read that reported failure.
    testWidgets('a failed read is not trusted even if it carries probes', (
      WidgetTester tester,
    ) async {
      await _pump(
        tester,
        <String>['a'],
        <RefInfo>[_branch('a')],
        probe: (List<String> names) => BranchDeletionProbeReply(
          probes: <BranchDeletionProbe>[_counted('a', 0)],
          error: const GitError(
            code: 13,
            codeName: 'ProcessFailed',
            message: 'broken',
            detail: '',
            argv: <String>[],
            exitCode: 128,
          ),
        ),
      );
      expect(_button(tester).onPressed, isNull);
      expect(find.text('已完整同步'), findsNothing);
    });

    testWidgets('a branch the snapshot shows moving is read again', (
      WidgetTester tester,
    ) async {
      int reads = 0;
      final FakeRepoSessionController fake = await _pump(
        tester,
        <String>['a', 'b'],
        <RefInfo>[_branch('a'), _branch('b')],
        probe: (List<String> names) {
          reads++;
          return BranchDeletionProbeReply(
            probes: <BranchDeletionProbe>[
              _counted('a', reads, tip: 'a-$reads'),
              _counted('b', 1, tip: 'b-$reads'),
            ],
          );
        },
      );
      fake.state = fake.state.copyWith(
        refs: _snapshot(<RefInfo>[
          _branch('a', target: 'b' * 40),
          _branch('b'),
        ]),
      );
      await tester.pumpAndSettle();

      expect(
        fake.commandLog.where(
          (FakeCommand c) => c.name == 'probeBranchDeletion',
        ),
        hasLength(2),
      );
      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();
      expect(_deletes(fake).single.args['entries'], const <DeleteBranchEntry>[
        DeleteBranchEntry.forced('a', expectedTipOid: 'a-2'),
        DeleteBranchEntry.forced('b', expectedTipOid: 'b-2'),
      ]);
    });

    testWidgets('a read overtaken by a newer one is dropped when it lands', (
      WidgetTester tester,
    ) async {
      late _HeldProbeController held;
      await _pump(
        tester,
        <String>['a'],
        <RefInfo>[_branch('a')],
        controller: (RepoSessionState s) => held = _HeldProbeController(s),
      );
      held.state = held.state.copyWith(
        refs: _snapshot(<RefInfo>[_branch('a', target: 'b' * 40)]),
      );
      await tester.pump();
      expect(held.reads, hasLength(2));

      held.reads[1].complete(
        BranchDeletionProbeReply(
          probes: <BranchDeletionProbe>[_counted('a', 2, tip: 'new')],
        ),
      );
      await tester.pump();
      held.reads[0].complete(
        BranchDeletionProbeReply(
          probes: <BranchDeletionProbe>[_counted('a', 1, tip: 'old')],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(_deleteButton);
      await tester.pumpAndSettle();
      expect(_deletes(held).single.args['entries'], const <DeleteBranchEntry>[
        DeleteBranchEntry.forced('a', expectedTipOid: 'new'),
      ]);
    });
  });
}
