// D2's `Remove worktree…` confirmation. Previously the panel dispatched
// `removeWorktree()` straight off the button press -- no confirmation, no
// warning about the folder or its uncommitted changes, and no distinction
// between a plain worktree and a locked one.
//
// The locked case is the one this file exists to pin down. Measured on a
// real repository (see `remove_worktree_dialog.dart`'s doc comment): `git
// worktree remove --force` on a *locked* worktree fails identically to a
// plain `remove` -- the lock is checked before uncommitted changes are, and
// only `remove -f -f` (which `gbm_worktree_remove()` cannot send; its
// `force` parameter is a bool, not a count) gets past it. So the dialog
// does not offer a checkbox or a second confirmation that claims to force
// through a lock -- it names the lock and points at `Unlock`, which is
// already a real, undialogued action one click above this one in the
// panel.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/worktree_info.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/remove_worktree/remove_worktree_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

/// A worktree fixture whose count/lock fields are the only thing a caller
/// varies. Everything else is held identical across a transition, which is
/// [TEST-fixture-cannot-disagree] shape 10.
WorktreeInfo _wt({
  String path = '/src/wt/gbm-lfs',
  bool isLocked = false,
  String lockReason = '',
  int? pendingChanges,
  WorktreePendingCountState pendingCountState =
      WorktreePendingCountState.unmeasured,
}) => WorktreeInfo(
  path: path,
  headOid: '9d02f4e',
  branch: 'feature/lfs',
  isMain: false,
  isBare: false,
  isDetached: false,
  isLocked: isLocked,
  lockReason: lockReason,
  isPrunable: false,
  prunableReason: '',
  isPrimary: false,
  pendingChanges: pendingChanges,
  pendingCountState: pendingCountState,
  createdAt: null,
);

Future<FakeRepoSessionController> _pump(
  WidgetTester tester, {
  required WorktreeInfo worktree,
}) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    RepoSessionState(isOpen: true, worktrees: <WorktreeInfo>[worktree]),
  );
  // The dialog pops after dispatching, so it needs something underneath it.
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/dialog',
        builder: (context, state) => Scaffold(
          body: RemoveWorktreeDialogContent(
            identity: _identity,
            path: worktree.path,
          ),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
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

List<FakeCommand> _removes(FakeRepoSessionController fake) => fake.commandLog
    .where((FakeCommand c) => c.name == 'removeWorktree')
    .toList();

void main() {
  group('worktreePendingCountWarning', () {
    test('measured and nonzero names the count', () {
      final WorktreeInfo w = _wt(
        pendingChanges: 9,
        pendingCountState: WorktreePendingCountState.measured,
      );
      expect(
        worktreePendingCountWarning(w),
        '其中有 9 個未提交的變更，它們不進 stash、也不在 reflog。',
      );
    });

    test('measured and zero is the empty string, not "0 個"', () {
      final WorktreeInfo w = _wt(
        pendingChanges: 0,
        pendingCountState: WorktreePendingCountState.measured,
      );
      expect(worktreePendingCountWarning(w), isEmpty);
    });

    test('unmeasured does not pretend to be zero', () {
      final WorktreeInfo w = _wt(
        pendingCountState: WorktreePendingCountState.unmeasured,
      );
      expect(worktreePendingCountWarning(w), '未提交的變更數未知。');
    });

    test('failed does not pretend to be zero either', () {
      final WorktreeInfo w = _wt(
        pendingCountState: WorktreePendingCountState.failed,
      );
      expect(worktreePendingCountWarning(w), '未提交的變更數未知。');
    });
  });

  group('worktreeLockWarning', () {
    test('unlocked is the empty string', () {
      expect(worktreeLockWarning(_wt(isLocked: false)), isEmpty);
    });

    test('locked with a reason names it', () {
      final String warning = worktreeLockWarning(
        _wt(isLocked: true, lockReason: 'on the USB drive'),
      );
      expect(warning, contains('on the USB drive'));
      expect(warning, contains('Unlock'));
    });

    test('locked with no reason says so rather than a blank', () {
      final String warning = worktreeLockWarning(
        _wt(isLocked: true, lockReason: ''),
      );
      expect(warning, contains('未填寫原因'));
    });
  });

  group('the dialog', () {
    testWidgets('the primary button restates the worktree name', (
      tester,
    ) async {
      await _pump(tester, worktree: _wt(path: '/src/wt/gbm-0.5'));

      expect(find.widgetWithText(GbmButton, 'Remove gbm-0.5'), findsOneWidget);
    });

    testWidgets('a clean, measured worktree drops the pending-count line', (
      tester,
    ) async {
      await _pump(
        tester,
        worktree: _wt(
          pendingChanges: 0,
          pendingCountState: WorktreePendingCountState.measured,
        ),
      );

      expect(find.textContaining('這個資料夾會從磁碟移除'), findsOneWidget);
      expect(find.textContaining('未提交的變更'), findsNothing);
    });

    testWidgets('an unlocked worktree offers the force checkbox, unticked', (
      tester,
    ) async {
      await _pump(tester, worktree: _wt());

      final CheckboxListTile box = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(box.value, isFalse);
    });

    testWidgets('checking force and confirming dispatches force: true', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        worktree: _wt(path: '/src/wt/gbm-lfs'),
      );

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GbmButton, 'Remove gbm-lfs'));
      await tester.pumpAndSettle();

      final List<FakeCommand> removes = _removes(fake);
      expect(removes.length, 1);
      expect(removes.single.args['path'], '/src/wt/gbm-lfs');
      expect(removes.single.args['force'], isTrue);
    });

    testWidgets('confirming without checking force dispatches force: false', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        worktree: _wt(path: '/src/wt/gbm-lfs'),
      );

      await tester.tap(find.widgetWithText(GbmButton, 'Remove gbm-lfs'));
      await tester.pumpAndSettle();

      final List<FakeCommand> removes = _removes(fake);
      expect(removes.length, 1);
      expect(removes.single.args['force'], isFalse);
    });

    group('a locked worktree', () {
      testWidgets('hides the force checkbox and disables the danger button', (
        tester,
      ) async {
        await _pump(
          tester,
          worktree: _wt(isLocked: true, lockReason: 'on the USB drive'),
        );

        expect(find.byType(CheckboxListTile), findsNothing);
        expect(find.textContaining('已鎖定'), findsOneWidget);
        final GbmButton danger = tester.widget<GbmButton>(
          find.widgetWithText(GbmButton, 'Remove gbm-lfs'),
        );
        expect(danger.onPressed, isNull);
      });

      testWidgets('never dispatches removeWorktree, even after a tap', (
        tester,
      ) async {
        final FakeRepoSessionController fake = await _pump(
          tester,
          worktree: _wt(isLocked: true),
        );

        // A disabled GbmButton's onPressed is null, so this tap hits
        // nothing -- asserted anyway, so a future change to GbmButton that
        // makes a disabled button tappable would be caught here rather
        // than silently forcing through a lock the dialog claims it can't.
        await tester.tap(
          find.widgetWithText(GbmButton, 'Remove gbm-lfs'),
          warnIfMissed: false,
        );
        await tester.pumpAndSettle();

        expect(_removes(fake), isEmpty);
      });
    });

    testWidgets('a worktree no longer in the session shows a fallback', (
      tester,
    ) async {
      final FakeRepoSessionController fake = FakeRepoSessionController(
        _identity,
        const RepoSessionState(isOpen: true, worktrees: <WorktreeInfo>[]),
      );
      final GoRouter router = GoRouter(
        initialLocation: '/',
        routes: <RouteBase>[
          GoRoute(
            path: '/',
            builder: (context, state) =>
                const Scaffold(body: SizedBox.shrink()),
          ),
          GoRoute(
            path: '/dialog',
            builder: (context, state) => Scaffold(
              body: RemoveWorktreeDialogContent(
                identity: _identity,
                path: '/src/wt/gone',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
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

      expect(find.text('這個 worktree 已經不在清單裡了。'), findsOneWidget);
      expect(find.byType(GbmButton), findsOneWidget); // Cancel only.
    });
  });
}
