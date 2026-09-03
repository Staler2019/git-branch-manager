// Opening Prune remote branches -- in any repository, as it turns out.
//
// `preview?.remote == _selectedRemote` reads as "the preview we have is for
// the remote we are showing", and it is also true when *both* are null --
// no preview has arrived yet and no remote is selected. The `preview!` on
// the next line then throws, so the first build renders an exception rather
// than the dialog. `_selectedRemote` is assigned in a `Future.microtask`, so
// that both-null window opens on *every* open, not only in a repository with
// no remotes -- which is what the second test below discovered.
//
// [CULT-do-not-derive-what-you-have] is the shape: the code already knows
// whether a preview exists, and asking the question through `?.` threw that
// away. Every fixture with at least one remote is blind to it, which is
// every fixture this dialog had.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/prune_remote_branches/prune_remote_branches_dialog.dart';
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

Future<void> _pump(WidgetTester tester, RepoSessionState state) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    state,
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
            const PruneRemoteBranchesDialogContent(identity: _identity),
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
}

void main() {
  testWidgets(
    'a repository with no remotes gets the empty state, not a crash',
    (tester) async {
      await _pump(tester, const RepoSessionState(isOpen: true));

      expect(tester.takeException(), isNull);
      // The title, deliberately, and not the empty-state wording: the claim
      // here is 「it renders at all」, and pinning it to copy would make this
      // test move every time the copy does.
      expect(find.text('Prune Remote Branches'), findsOneWidget);
    },
  );

  testWidgets('one remote and no preview yet still renders', (tester) async {
    // Written expecting this case to have been safe -- 「a remote is
    // selected, so the two differ and `preview!` is never reached」 -- and it
    // was red too. `_selectedRemote` is assigned inside a `Future.microtask`
    // in initState, so it is null on the *first* build no matter how many
    // remotes exist. The throw therefore fired on every single open of this
    // dialog, not only in a repository with none; the next build (after the
    // microtask) is the one that renders, so what a user saw was a one-frame
    // framework error box rather than a dead dialog.
    //
    // Recording the wrong prediction rather than quietly deleting it: the
    // reason the fix is broader than 「no remotes」 is exactly this.
    await _pump(
      tester,
      const RepoSessionState(
        isOpen: true,
        remotes: <RemoteInfo>[
          RemoteInfo(name: 'origin', fetchUrl: 'u', pushUrl: 'u'),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Prune Remote Branches'), findsOneWidget);
  });
}
