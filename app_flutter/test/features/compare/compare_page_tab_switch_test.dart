// ComparePage carries State: a ScrollController seeded from the tab's stored
// offset, and a `_lastRequested` key that dedupes repeat requests. GoRouter
// renders it at the same position in the tree for every `/compare/:tabId`,
// so with no key on the widget Flutter reuses one State across two tabs --
// `initState` never runs again, the `Future.microtask` that asks for the
// diff never fires for the second tab, and `_lastRequested` still holds the
// first tab's key so a late request would be swallowed too. The reported
// symptom is 「開到第二個視窗就會一直轉圈圈，file list、與 diff view 區塊也
//沒有出來」.
//
// A standalone `/compare/:tabId` route rather than the real ShellRoute
// child: the condition under test is widget identity at one route position,
// which the shell plays no part in, and keeping the tree small means the
// only thing that can dispatch is the page itself.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

// forWorkDir, because `buildComparePageRoute` reconstructs the identity
// from the route param the same way -- a hand-built RepoIdentity would key
// a different provider and the override would silently not apply.
final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');
final String _repoId = repoIdFor('/test/repo');

int _requests(FakeRepoSessionController fake) => fake.commandLog
    .where((FakeCommand c) => c.name == 'requestCompareRefs')
    .length;

void main() {
  testWidgets('each Compare tab asks for its own diff when it is shown', (
    tester,
  ) async {
    final FakeRepoSessionController fake = FakeRepoSessionController(
      _identity,
      const RepoSessionState(isOpen: true),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        repoSessionProvider(_identity).overrideWith((ref) => fake),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    final CompareTabsNotifier tabs = container.read(
      compareTabsProvider(_identity).notifier,
    );
    final String first = tabs.open(left: 'main', right: 'develop');
    final String second = tabs.open(left: 'main', right: 'release/1.4');

    final GoRouter router = GoRouter(
      initialLocation: RoutePaths.compareFor(_repoId, first),
      routes: <RouteBase>[
        // The production builder itself, not a copy -- the key it applies is
        // the whole fix, so a re-implementation here would test only itself.
        GoRoute(
          path: '/repo/:repoId/compare/:tabId',
          // Scaffold only because ComparePage's TextFields need a Material
          // ancestor, which the real ShellRoute supplies. The page itself is
          // still built by the production builder, so the key under test is
          // production's and not the test's.
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: buildComparePageRoute(context, state)),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          routerConfig: router,
        ),
      ),
    );
    await tester.pump();

    expect(
      _requests(fake),
      1,
      reason: 'the tab that is on screen at mount asks for its diff',
    );

    router.go(RoutePaths.compareFor(_repoId, second));
    await tester.pump();
    await tester.pump();

    // Counted, not `any` -- `any` cannot tell "the second tab asked" from
    // "the first tab asked twice" ([TEST-count-dont-any]).
    expect(
      _requests(fake),
      2,
      reason:
          'switching to a second Compare tab must request that tab\'s diff; '
          'reusing one State leaves it spinning forever',
    );
    expect(
      fake.commandLog
          .where((FakeCommand c) => c.name == 'requestCompareRefs')
          .last
          .args['rightRef'],
      'release/1.4',
      reason:
          'and it must be the second tab\'s refs, not a repeat of the first',
    );
  });
}
