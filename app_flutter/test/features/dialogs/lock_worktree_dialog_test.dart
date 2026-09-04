// D3's `Lock…` confirmation. `lockWorktree(path, {String reason = ''})` has
// taken a reason since it was written and the detail pane already draws a
// 「鎖定原因」 row for it, but no call site ever passed one -- the panel's
// button dispatched unconditionally with the default empty string, a
// [CULT-orphan-wiring] instance. This file pins the dialog that replaces
// that dispatch: a read-only worktree line, an optional reason field, and
// the [GIT-worktree-prune-has-no-expire] note the plan calls load-bearing
// rather than decorative.
//
// `Unlock` gets no dialog of its own and is not covered here -- it destroys
// nothing and needs no input; `worktrees_panel_test.dart` covers its direct
// dispatch.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/worktree_info.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/lock_worktree/lock_worktree_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

const WorktreeInfo _worktree = WorktreeInfo(
  path: '/src/wt/gbm-lfs',
  headOid: '9d02f4e',
  branch: 'feature/lfs',
  isMain: false,
  isBare: false,
  isDetached: false,
  isLocked: false,
  lockReason: '',
  isPrunable: false,
  prunableReason: '',
  isPrimary: false,
  pendingChanges: null,
  pendingCountState: WorktreePendingCountState.unmeasured,
  createdAt: null,
);

Future<FakeRepoSessionController> _pump(
  WidgetTester tester, {
  WorktreeInfo worktree = _worktree,
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
          body: LockWorktreeDialogContent(
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

List<FakeCommand> _locks(FakeRepoSessionController fake) =>
    fake.commandLog.where((FakeCommand c) => c.name == 'lockWorktree').toList();

void main() {
  group('the dialog', () {
    testWidgets('restates the worktree name and path', (tester) async {
      await _pump(tester);

      expect(find.textContaining('gbm-lfs'), findsWidgets);
      expect(find.textContaining('/src/wt/gbm-lfs'), findsWidgets);
    });

    testWidgets('the reason field is focused and starts empty', (tester) async {
      await _pump(tester);

      final TextField field = tester.widget<TextField>(find.byType(TextField));
      expect(field.autofocus, isTrue);
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('the reason field is 30px tall with a r6 border (G4)', (
      tester,
    ) async {
      await _pump(tester);

      final Finder finder = find.byType(TextField);
      expect(tester.getSize(finder).height, GbmSpacing.inputHeight);
      final TextField field = tester.widget<TextField>(finder);
      final OutlineInputBorder border =
          field.decoration!.border! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(GbmSpacing.radiusMd));
    });

    // Not decoration -- the plan's own words for this block. Asserted by
    // its actual content rather than by widget type, since nothing else in
    // this dialog would distinguish "the note is missing" from "the note
    // says something else".
    testWidgets('states what locking protects against', (tester) async {
      await _pump(tester);

      expect(find.textContaining('鎖定唯一的作用是擋掉 prune'), findsOneWidget);
    });

    testWidgets('confirming with no typed reason dispatches an empty one', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);

      await tester.tap(find.widgetWithText(GbmButton, 'Lock'));
      await tester.pumpAndSettle();

      final List<FakeCommand> locks = _locks(fake);
      expect(locks.length, 1);
      expect(locks.single.args['path'], '/src/wt/gbm-lfs');
      expect(locks.single.args['reason'], isEmpty);
    });

    testWidgets('confirming with a typed reason dispatches it', (tester) async {
      final FakeRepoSessionController fake = await _pump(tester);

      await tester.enterText(find.byType(TextField), 'on the USB drive');
      await tester.tap(find.widgetWithText(GbmButton, 'Lock'));
      await tester.pumpAndSettle();

      final List<FakeCommand> locks = _locks(fake);
      expect(locks.length, 1);
      expect(locks.single.args['reason'], 'on the USB drive');
    });

    // The dialog trims what it dispatches -- otherwise a reason typed with
    // trailing whitespace (a stray space before Enter) would sit in the
    // detail pane and `git worktree list`'s output forever.
    testWidgets('trims leading and trailing whitespace from the reason', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);

      await tester.enterText(find.byType(TextField), '  on the USB drive  ');
      await tester.tap(find.widgetWithText(GbmButton, 'Lock'));
      await tester.pumpAndSettle();

      expect(_locks(fake).single.args['reason'], 'on the USB drive');
    });

    testWidgets('Cancel dispatches nothing', (tester) async {
      final FakeRepoSessionController fake = await _pump(tester);

      await tester.tap(find.widgetWithText(GbmButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(_locks(fake), isEmpty);
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
              body: LockWorktreeDialogContent(
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
