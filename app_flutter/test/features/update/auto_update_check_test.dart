import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/models/release_asset.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/build_version_repository.dart';
import 'package:gbm_flutter/data/services/github_release_gateway.dart';
import 'package:gbm_flutter/data/services/update_installer.dart';
import 'package:gbm_flutter/features/update/auto_update_check.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A real gateway seam, not a fake controller: "the setting is honoured"
/// has to mean *no network request was made*, and only counting calls at
/// this level says that literally.
class _CountingGateway extends GithubReleaseGateway {
  _CountingGateway(this.tag);

  final String tag;
  int calls = 0;

  @override
  Future<LatestRelease> fetchLatest() async {
    calls++;
    return LatestRelease(
      version: AppVersion.tryParse(tag)!,
      tagName: tag,
      htmlUrl: 'https://example.test/releases/tag/$tag',
      notes: '',
      assets: const <ReleaseAsset>[
        ReleaseAsset(
          name: 'git-branch-manager-9.9.9-linux-x86_64.tar.gz',
          downloadUrl: 'https://example.test/linux.tar.gz',
          sizeBytes: 100,
        ),
        ReleaseAsset(
          name: kChecksumManifestName,
          downloadUrl: 'https://example.test/sha256sums.txt',
          sizeBytes: 10,
        ),
      ],
    );
  }
}

typedef _Pumped = ({
  _CountingGateway gateway,
  List<String> surfaced,
  ProviderContainer container,
});

Future<_Pumped> _pump(
  WidgetTester tester, {
  String tag = 'v9.9.9',
  AppVersion? current = const AppVersion(0, 30, 0),
  Map<String, Object> prefs = const <String, Object>{},
  DateTime? now,
  Duration delay = Duration.zero,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final SharedPreferences store = await SharedPreferences.getInstance();
  final _CountingGateway gateway = _CountingGateway(tag);
  final List<String> surfaced = <String>[];

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(store),
      githubReleaseGatewayProvider.overrideWithValue(gateway),
      buildVersionProvider.overrideWithValue(current),
      autoUpdateCheckDelayProvider.overrideWithValue(delay),
      autoUpdateClockProvider.overrideWithValue(
        () => now ?? DateTime.utc(2026, 8, 23, 12),
      ),
      // The default probes Platform.resolvedExecutable, so on a machine
      // whose Flutter SDK sits somewhere writable the answer would differ
      // from one where it does not.
      updateInstallerProvider.overrideWithValue(_installable()),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: AutoUpdateCheck(
          onUpdateAvailable: () => surfaced.add('push'),
          child: const Scaffold(body: SizedBox()),
        ),
      ),
    ),
  );
  return (gateway: gateway, surfaced: surfaced, container: container);
}

UpdateInstaller _installable() {
  final Directory install = Directory(
    '${Directory.systemTemp.createTempSync('gbm-auto').path}/opt/gbm',
  )..createSync(recursive: true);
  return UpdateInstaller(
    operatingSystem: 'linux',
    executablePath: '${install.path}/gbm_flutter',
    abi: Abi.linuxX64,
  );
}

void main() {
  // The gate is state, not a setting, and it used to be invisible: nothing
  // in the app could tell "the check found nothing" from "the check is not
  // due for another 23 hours". Preferences renders this string.
  group('lastAutoCheckLabel', () {
    test('says never when nothing has been recorded', () {
      expect(lastAutoCheckLabel(null), 'Last automatic check: never.');
    });

    // Same call `_isDue` makes: a corrupt value must not throw, and must not
    // read as a real time either.
    test('says never for a stamp that will not parse', () {
      expect(lastAutoCheckLabel('not a date'), 'Last automatic check: never.');
    });

    // A local DateTime serialises without a zone suffix, so `toLocal()` is a
    // no-op on it and this assertion holds on any machine.
    test('renders a recorded stamp in local time, zero padded', () {
      expect(
        lastAutoCheckLabel(DateTime(2026, 8, 25, 9, 4).toIso8601String()),
        'Last automatic check: 2026-08-25 09:04.',
      );
    });

    test('converts a UTC stamp to local time', () {
      final DateTime utc = DateTime.utc(2026, 8, 25, 9, 4);
      expect(
        lastAutoCheckLabel(utc.toIso8601String()),
        lastAutoCheckLabel(utc.toLocal().toIso8601String()),
      );
    });
  });

  group('AutoUpdateCheck', () {
    testWidgets('surfaces an available update after the delay', (
      WidgetTester tester,
    ) async {
      final _Pumped p = await _pump(tester, delay: const Duration(seconds: 5));

      // Nothing on the first frame: a check racing the window opening is
      // what the delay exists to avoid.
      expect(p.gateway.calls, 0);
      expect(p.surfaced, isEmpty);

      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(p.gateway.calls, 1);
      expect(p.surfaced, <String>['push']);
    });

    testWidgets('says nothing when already up to date', (
      WidgetTester tester,
    ) async {
      final _Pumped p = await _pump(tester, tag: 'v0.30.0');
      await tester.pumpAndSettle();

      expect(p.gateway.calls, 1);
      expect(p.surfaced, isEmpty);
    });

    testWidgets('says nothing when the check fails', (
      WidgetTester tester,
    ) async {
      // An unparsable tag is the cheapest reachable failure that does not
      // need a network stub of its own.
      final _Pumped p = await _pump(tester, tag: 'nightly');
      await tester.pumpAndSettle();

      expect(p.surfaced, isEmpty);
    });

    testWidgets('says nothing for a release the user skipped', (
      WidgetTester tester,
    ) async {
      final _Pumped p = await _pump(
        tester,
        prefs: <String, Object>{'appPrefs.skippedVersion': '9.9.9'},
      );
      await tester.pumpAndSettle();

      expect(p.gateway.calls, 1);
      expect(p.surfaced, isEmpty);
    });

    // The setting is read when the timer fires, not when the widget mounts
    // -- a user who turns it off during the delay has turned it off. A
    // fixture that sets the preference before mounting cannot tell the two
    // readings apart, so this is the case that pins it.
    testWidgets('honours the setting being turned off during the delay', (
      WidgetTester tester,
    ) async {
      final _Pumped p = await _pump(tester, delay: const Duration(seconds: 5));

      await p.container
          .read(appPreferencesProvider.notifier)
          .update(
            (AppPreferences x) => x.copyWith(autoUpdateCheckEnabled: false),
          );
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(p.gateway.calls, 0);
      expect(p.surfaced, isEmpty);
    });

    // The Preferences honesty rule, made falsifiable: off must mean no
    // request reaches GitHub at all, not a request whose result is hidden.
    testWidgets('makes no request at all when the setting is off', (
      WidgetTester tester,
    ) async {
      final _Pumped p = await _pump(
        tester,
        prefs: <String, Object>{'appPrefs.autoUpdateCheckEnabled': false},
      );
      await tester.pumpAndSettle();

      expect(p.gateway.calls, 0);
      expect(p.surfaced, isEmpty);
    });

    testWidgets('a development build never reaches the network', (
      WidgetTester tester,
    ) async {
      final _Pumped p = await _pump(tester, current: null);
      await tester.pumpAndSettle();

      expect(p.gateway.calls, 0);
      expect(p.surfaced, isEmpty);
    });

    group('once a day', () {
      final DateTime noon = DateTime.utc(2026, 8, 23, 12);

      testWidgets('skips a check made an hour ago', (
        WidgetTester tester,
      ) async {
        final _Pumped p = await _pump(
          tester,
          now: noon,
          prefs: <String, Object>{
            kLastAutoUpdateCheckKey: noon
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
          },
        );
        await tester.pumpAndSettle();

        expect(p.gateway.calls, 0);
      });

      testWidgets('checks again a day later', (WidgetTester tester) async {
        final _Pumped p = await _pump(
          tester,
          now: noon,
          prefs: <String, Object>{
            kLastAutoUpdateCheckKey: noon
                .subtract(const Duration(hours: 25))
                .toIso8601String(),
          },
        );
        await tester.pumpAndSettle();

        expect(p.gateway.calls, 1);
      });

      testWidgets('an unreadable timestamp checks rather than blocks', (
        WidgetTester tester,
      ) async {
        final _Pumped p = await _pump(
          tester,
          prefs: <String, Object>{kLastAutoUpdateCheckKey: 'not a date'},
        );
        await tester.pumpAndSettle();

        expect(p.gateway.calls, 1);
      });

      testWidgets('records the attempt so the next launch stays quiet', (
        WidgetTester tester,
      ) async {
        await _pump(tester, now: noon);
        await tester.pumpAndSettle();

        final SharedPreferences store = await SharedPreferences.getInstance();
        expect(
          store.getString(kLastAutoUpdateCheckKey),
          noon.toIso8601String(),
        );
      });

      // Still recorded *before* the request, so two launches in quick
      // succession cannot both reach GitHub -- but rolled back when the
      // check never asked, or asked and learned nothing. Otherwise one
      // offline launch silences the next 24 hours for free, with no UI
      // anywhere that says so and no way to make it try again.
      testWidgets('an answered check spends the day', (
        WidgetTester tester,
      ) async {
        await _pump(tester, tag: 'v0.30.0', now: noon);
        await tester.pumpAndSettle();

        final SharedPreferences store = await SharedPreferences.getInstance();
        expect(
          store.getString(kLastAutoUpdateCheckKey),
          noon.toIso8601String(),
        );
      });

      testWidgets('a development build does not spend the day', (
        WidgetTester tester,
      ) async {
        await _pump(tester, current: null, now: noon);
        await tester.pumpAndSettle();

        final SharedPreferences store = await SharedPreferences.getInstance();
        expect(store.getString(kLastAutoUpdateCheckKey), isNull);
      });

      testWidgets('a failed check does not spend the day', (
        WidgetTester tester,
      ) async {
        final _Pumped p = await _pump(tester, tag: 'nightly', now: noon);
        await tester.pumpAndSettle();

        expect(p.gateway.calls, 1, reason: 'the request really was made');
        final SharedPreferences store = await SharedPreferences.getInstance();
        expect(store.getString(kLastAutoUpdateCheckKey), isNull);
      });

      // Restored, not cleared: a rollback that wiped an older stamp would
      // hand a machine that is offline every morning an unlimited number of
      // requests the moment it came back.
      testWidgets('restores the earlier stamp rather than clearing it', (
        WidgetTester tester,
      ) async {
        final String earlier = noon
            .subtract(const Duration(hours: 30))
            .toIso8601String();
        await _pump(
          tester,
          tag: 'nightly',
          now: noon,
          prefs: <String, Object>{kLastAutoUpdateCheckKey: earlier},
        );
        await tester.pumpAndSettle();

        final SharedPreferences store = await SharedPreferences.getInstance();
        expect(store.getString(kLastAutoUpdateCheckKey), earlier);
      });
    });

    // The window can close inside the delay. A timer that outlives its
    // widget would reach a disposed container.
    testWidgets('closing before the delay cancels the check', (
      WidgetTester tester,
    ) async {
      final _Pumped p = await _pump(tester, delay: const Duration(seconds: 5));

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      expect(p.gateway.calls, 0);
    });
  });
}
