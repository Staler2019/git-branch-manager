// The multiplier is process-wide in core, and git runs before any repository
// is open too: a clone from the welcome screen has no session. So the push
// belongs to the app, not to a session -- it used to live only in
// repoSessionProvider, which left that clone, and any change made while no
// repository was open, at 1x.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/git_timeout_multiplier_sync.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

class _RecordingBindings extends FakeGbmBindings {
  final List<int> pushed = <int>[];

  @override
  SetTimeoutMultiplierDart get setTimeoutMultiplier => (int multiplier) {
    pushed.add(multiplier);
    return multiplier;
  };
}

Future<ProviderContainer> _container(
  _RecordingBindings bindings, {
  required int stored,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'appPrefs.gitTimeoutMultiplier': stored,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      gbmBindingsProvider.overrideWithValue(bindings),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('the stored multiplier is pushed with no session at all', () async {
    final _RecordingBindings bindings = _RecordingBindings();
    final ProviderContainer container = await _container(bindings, stored: 4);

    container.read(gitTimeoutMultiplierSyncProvider);

    expect(bindings.pushed, <int>[4]);
  });

  test('a change is pushed with no session at all', () async {
    final _RecordingBindings bindings = _RecordingBindings();
    final ProviderContainer container = await _container(bindings, stored: 1);
    container.read(gitTimeoutMultiplierSyncProvider);

    await container
        .read(appPreferencesProvider.notifier)
        .update((AppPreferences p) => p.copyWith(gitTimeoutMultiplier: 8));

    expect(bindings.pushed, <int>[1, 8]);
  });

  test('an unrelated preference change pushes nothing', () async {
    final _RecordingBindings bindings = _RecordingBindings();
    final ProviderContainer container = await _container(bindings, stored: 2);
    container.read(gitTimeoutMultiplierSyncProvider);

    await container
        .read(appPreferencesProvider.notifier)
        .update((AppPreferences p) => p.copyWith(confirmForcePush: false));

    expect(bindings.pushed, <int>[2]);
  });
}
