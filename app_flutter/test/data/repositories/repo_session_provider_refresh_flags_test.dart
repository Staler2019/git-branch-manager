// `repoSessionProvider`'s own wiring for `RepoSessionController.refreshFlags`
// -- the one thing about the Developer tab's two behaviour flags that no
// other test can see, because `pumpWorkspace()` overrides `repoSessionProvider`
// itself with a pre-built `FakeRepoSessionController`
// (`repoSessionProvider(identity).overrideWith((ref) => controller)`), which
// bypasses this provider's builder function entirely. This file deliberately
// does NOT override `repoSessionProvider` -- that is the one thing under
// test -- only its dependencies (`gbmBindingsProvider`,
// `sharedPreferencesProvider`), the same way `FakeRepoSessionController`
// itself is built: a `FakeGbmBindings` whose `sessionOpen()` returns nullptr
// makes the real `_open()` return before touching bindings again
// ([TEST-fake-session-seam]), so the real controller never actually reaches
// the network/filesystem.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

void main() {
  Future<ProviderContainer> buildContainer({
    Map<String, Object> initialPrefs = const <String, Object>{},
  }) async {
    SharedPreferences.setMockInitialValues(initialPrefs);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        gbmBindingsProvider.overrideWithValue(FakeGbmBindings()),
      ],
    );
    return container;
  }

  group('repoSessionProvider wires RefreshFlags into the controller', () {
    test(
      'the initial flags match whatever AppPreferences already held',
      () async {
        final ProviderContainer container = await buildContainer(
          initialPrefs: <String, Object>{
            'appPrefs.keepDiffDuringRefresh': false,
            'appPrefs.tieredRefresh': false,
          },
        );
        addTearDown(container.dispose);

        final RepoSessionController controller = container.read(
          repoSessionProvider(_identity).notifier,
        );

        expect(controller.refreshFlags.keepDiffDuringRefresh, isFalse);
        expect(controller.refreshFlags.tieredRefresh, isFalse);
      },
    );

    test(
      'a later AppPreferences change reaches the already-open controller',
      () async {
        final ProviderContainer container = await buildContainer();
        addTearDown(container.dispose);

        final RepoSessionController controller = container.read(
          repoSessionProvider(_identity).notifier,
        );
        expect(
          controller.refreshFlags.tieredRefresh,
          isTrue,
          reason: 'defaults are the new behaviour',
        );

        await container
            .read(appPreferencesProvider.notifier)
            .update((AppPreferences p) => p.copyWith(tieredRefresh: false));

        expect(
          controller.refreshFlags.tieredRefresh,
          isFalse,
          reason:
              'ref.listen must push the change into the live controller -- a '
              'construction-time-only read would leave this stuck at true '
              'until the repository were closed and reopened',
        );
      },
    );
  });
}
