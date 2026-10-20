// go_router hands `:repoId` over already decoded (measured: `%2Fa%2F100%25`
// arrives as `/a/100%`). Decoding it a second time threw on a work dir
// containing a bare `%` and misread one containing `%25`; and the bare
// `/repo/:repoId` redirect spliced the decoded value back into a path,
// which no route matches.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<String> _dirs = <String>['/src/my repo', '/a/100%', '/a/100%25x'];

void main() {
  for (final String dir in _dirs) {
    testWidgets('a route builder resolves $dir to itself', (tester) async {
      RepoIdentity? seen;
      final GoRouter router = GoRouter(
        initialLocation: RoutePaths.historyFor(repoIdFor(dir)),
        routes: <RouteBase>[
          GoRoute(
            path: RoutePaths.history,
            builder: (context, state) {
              seen = repoIdentityFromRouteParam(
                state.pathParameters['repoId']!,
              );
              return const SizedBox();
            },
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(seen?.workDir, dir);
    });

    testWidgets('the bare workspace route redirects $dir to its History', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      final GoRouter app = container.read(appRouterProvider);
      final GoRoute workspace = app.configuration.routes
          .whereType<GoRoute>()
          .singleWhere((GoRoute r) => r.path == RoutePaths.workspace);

      // The real route's redirect, on a probe router that hands it exactly
      // the state go_router builds for `/repo/<encoded>`.
      String? target;
      final GoRouter probe = GoRouter(
        initialLocation: '/repo/${repoIdFor(dir)}',
        routes: <RouteBase>[
          GoRoute(
            path: RoutePaths.workspace,
            redirect: (context, state) {
              target = workspace.redirect!(context, state) as String?;
              return '/done';
            },
          ),
          GoRoute(path: '/done', builder: (context, state) => const SizedBox()),
        ],
      );
      addTearDown(probe.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: probe));
      await tester.pumpAndSettle();
      expect(target, RoutePaths.historyFor(repoIdFor(dir)));
    });
  }
}
