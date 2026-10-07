// The git timeout multiplier is process-wide in core and read at each git
// process, so it must reach core *before* the session's first read: opening a
// repository starts a status, a refs and a history read straight away, and
// those are exactly the reads that timed out on the slow machine this exists
// for. A push that lands after `sessionOpen` leaves that first round at 1x.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

/// Records the order of the two calls this test is about.
class _OrderRecordingBindings extends FakeGbmBindings {
  final List<String> calls = <String>[];
  final List<int> multipliers = <int>[];

  @override
  SetTimeoutMultiplierDart get setTimeoutMultiplier => (int multiplier) {
    calls.add('setTimeoutMultiplier');
    multipliers.add(multiplier);
    return multiplier;
  };

  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) {
        calls.add('sessionOpen');
        return nullptr;
      };
}

Future<ProviderContainer> _container(
  _OrderRecordingBindings bindings, {
  required int storedMultiplier,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'appPrefs.gitTimeoutMultiplier': storedMultiplier,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      gbmBindingsProvider.overrideWithValue(bindings),
      recentsRepositoryProvider.overrideWithValue(FakeRecentsRepository()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  final RepoIdentity identity = RepoIdentity.forWorkDir('/test/repo');

  test('the stored multiplier reaches core before the session opens', () async {
    final _OrderRecordingBindings bindings = _OrderRecordingBindings();
    final ProviderContainer container = await _container(
      bindings,
      storedMultiplier: 4,
    );

    container.read(repoSessionProvider(identity));

    expect(bindings.calls, <String>['setTimeoutMultiplier', 'sessionOpen']);
    expect(bindings.multipliers, <int>[4]);
  });

  test('changing the preference pushes the new multiplier', () async {
    final _OrderRecordingBindings bindings = _OrderRecordingBindings();
    final ProviderContainer container = await _container(
      bindings,
      storedMultiplier: 1,
    );
    container.read(repoSessionProvider(identity));

    await container
        .read(appPreferencesProvider.notifier)
        .update((AppPreferences p) => p.copyWith(gitTimeoutMultiplier: 8));

    expect(bindings.multipliers, <int>[1, 8]);
  });
}
