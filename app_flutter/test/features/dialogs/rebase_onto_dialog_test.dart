// Dispatch behaviour for rebase_onto_dialog.dart's rebaseMerges/autosquash
// checkboxes -- dialog_copy_test.dart covers their copy, this file covers
// whether Start rebase actually forwards what they show.
// [DRIFT-rebase-onto-missing-capi-flags]
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/rebase_onto/rebase_onto_dialog.dart';
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

RefInfo _localRef(String shortName) => RefInfo(
  fullName: 'refs/heads/$shortName',
  shortName: shortName,
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

final RepoSessionState _state = RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'aaaa',
    ),
    refs: <RefInfo>[_localRef('release/0.5')],
    refCountGuardTripped: false,
    totalRefCount: 1,
  ),
);

Future<FakeRepoSessionController> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    _state,
  );

  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/dialog',
        builder: (context, state) =>
            const RebaseOntoDialogContent(identity: _identity),
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

FakeCommand _rebased(FakeRepoSessionController fake) =>
    fake.commandLog.singleWhere((FakeCommand c) => c.name == 'startRebase');

void main() {
  testWidgets(
    'Start rebase dispatches the default checkbox values -- rebaseMerges '
    'on, autosquash off',
    (tester) async {
      final FakeRepoSessionController fake = await _pump(tester);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('release/0.5').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Start rebase'));
      await tester.pump();

      final FakeCommand call = _rebased(fake);
      expect(call.args['rebaseMerges'], isTrue);
      expect(call.args['autosquash'], isFalse);
    },
  );

  testWidgets('toggling autosquash off/on changes what is dispatched', (
    tester,
  ) async {
    final FakeRepoSessionController fake = await _pump(tester);
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('release/0.5').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('自動 squash 標記過的 fixup commit'));
    await tester.tap(find.text('保留 merge commit（--rebase-merges）'));
    await tester.pump();

    await tester.tap(find.text('Start rebase'));
    await tester.pump();

    final FakeCommand call = _rebased(fake);
    expect(call.args['rebaseMerges'], isFalse);
    expect(call.args['autosquash'], isTrue);
  });
}
