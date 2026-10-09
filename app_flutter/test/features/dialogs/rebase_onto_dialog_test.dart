// Dispatch behaviour for rebase_onto_dialog.dart's rebaseMerges/autosquash
// checkboxes -- dialog_copy_test.dart covers their copy, this file covers
// whether Start rebase actually forwards what they show.
// (the Rebase onto mock delta, closed in G1d's follow-up)
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

RefInfo _localRef(String shortName, {bool remote = false}) => RefInfo(
  fullName: remote ? 'refs/remotes/$shortName' : 'refs/heads/$shortName',
  shortName: shortName,
  kind: remote ? RefKind.remoteBranch : RefKind.localBranch,
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
    refs: <RefInfo>[
      _localRef('release/0.5'),
      _localRef('origin/feat', remote: true),
    ],
    refCountGuardTripped: false,
    totalRefCount: 2,
  ),
);

Future<FakeRepoSessionController> _pump(
  WidgetTester tester, {
  String? target,
}) async {
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
            RebaseOntoDialogContent(identity: _identity, target: target),
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
      await tester.tap(find.text('release/0.5'));
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
    await tester.tap(find.text('release/0.5'));
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

  // git reads a bare name tag-first, so a same-named tag would be the base
  // instead (verifier P4 #7): a branch goes to git as its full ref, and a
  // commit oid (05-E) exactly as given.
  group('what Start rebase hands git as the upstream', () {
    Future<String?> upstreamFor(
      WidgetTester tester, {
      String? target,
      String? pick,
    }) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        target: target,
      );
      if (pick != null) {
        await tester.tap(find.text(pick));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Start rebase'));
      await tester.pump();
      return _rebased(fake).args['upstream'] as String?;
    }

    testWidgets('a locked branch: its full ref', (tester) async {
      expect(
        await upstreamFor(tester, target: 'release/0.5'),
        'refs/heads/release/0.5',
      );
    });

    testWidgets('a picked remote branch: its remote ref', (tester) async {
      expect(
        await upstreamFor(tester, pick: 'origin/feat'),
        'refs/remotes/origin/feat',
      );
    });

    testWidgets('a locked commit oid: unchanged', (tester) async {
      final String oid = 'b' * 40;
      expect(await upstreamFor(tester, target: oid), oid);
    });
  });
}
