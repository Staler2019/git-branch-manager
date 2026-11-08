import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/routing/startup_target.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const List<RecentRepoEntry> _recents = <RecentRepoEntry>[
  RecentRepoEntry(workDir: '/r/newest', lastOpenedEpochMs: 2),
  RecentRepoEntry(workDir: '/r/older', lastOpenedEpochMs: 1),
];

void main() {
  group('decideStartupTarget', () {
    test('no marker reopens the newest repository', () {
      expect(
        decideStartupTarget(marker: null, recents: _recents),
        const OpenRecent('/r/newest'),
      );
    });

    test('a marker lands on welcome and names the repository it was for', () {
      expect(
        decideStartupTarget(marker: '/r/older', recents: _recents),
        const Welcome(skipped: '/r/older'),
      );
    });

    test('a marker is honoured even when the list no longer has it', () {
      expect(
        decideStartupTarget(
          marker: '/r/gone',
          recents: const <RecentRepoEntry>[],
        ),
        const Welcome(skipped: '/r/gone'),
      );
    });

    test('nothing to reopen lands on welcome with nothing skipped', () {
      expect(
        decideStartupTarget(marker: null, recents: const <RecentRepoEntry>[]),
        const Welcome(),
      );
    });
  });

  // What every test that never runs bootstrapApp gets: today's rule, and no marker read.
  test(
    'the default target reopens the newest repository and ignores a marker',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'recents.repos': '[{"workDir":"/r/newest","lastOpenedEpochMs":2}]',
        'launch.autoReopenPending': '/r/newest',
      });
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(startupTargetProvider),
        const OpenRecent('/r/newest'),
      );
    },
  );
}
