// Regression coverage for a fixed crash: `_selectedRemote` is assigned
// inside a `Future.microtask` in `initState`, so it is null on the first
// build regardless of remote count. The dialog's preview guard now reads
// `preview != null && preview.remote == _selectedRemote` for exactly this
// reason -- see the guard's own comment in the dialog for the fix.
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
    // Covers the case a remotes-empty fixture cannot: `_selectedRemote` is
    // still null on the dialog's first build even when a remote exists,
    // because it is only assigned inside `initState`'s `Future.microtask`.
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
