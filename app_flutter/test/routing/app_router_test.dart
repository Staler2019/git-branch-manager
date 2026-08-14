// Verifies appRouterProvider's cold-start `initialLocation`: goes straight
// into the most-recently-opened repo when RecentsRepository has an entry,
// falls back to the repo list otherwise. Deliberately does NOT pump a
// widget tree (the workspace route's screen needs real FFI bindings via
// gbmBindingsProvider) -- inspecting the constructed GoRouter's own
// routeInformationProvider is enough to verify initialLocation without
// needing the destination screen to actually build.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'initialLocation is the repo list when there are no recent repos',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);

      expect(
        router.routeInformationProvider.value.uri.toString(),
        RoutePaths.repoList,
      );
    },
  );

  test(
    'initialLocation goes straight into the most recently opened repo',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'recents.repos':
            '[{"workDir":"/tmp/repo-b","lastOpenedEpochMs":200},'
            '{"workDir":"/tmp/repo-a","lastOpenedEpochMs":100}]',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      final router = container.read(appRouterProvider);

      expect(
        router.routeInformationProvider.value.uri.toString(),
        RoutePaths.workspaceFor(repoIdFor('/tmp/repo-b')),
      );
    },
  );

  test('explicitly navigating back to RoutePaths.repoList still shows the repo '
      'list even when a recent repo exists (initialLocation is not a '
      'redirect)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'recents.repos': '[{"workDir":"/tmp/repo-a","lastOpenedEpochMs":100}]',
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    final router = container.read(appRouterProvider);
    router.go(RoutePaths.repoList);

    expect(
      router.routeInformationProvider.value.uri.toString(),
      RoutePaths.repoList,
    );
  });
}
