// Device-tier E2E: the update flow against the **real** GitHub Releases API
// and the **real** published assets, on the real GbmApp.
//
// Deliberately stops at `readyToInstall` and never presses "Install and
// restart": that step replaces this checkout's own build and relaunches it,
// which no automated test can undo. The plan records the self-install pass
// as manual-only, done against a throwaway pre-release tag.
//
// Requires network. A machine with no route to api.github.com fails loudly
// here rather than skipping -- a network test that quietly passes offline
// reports nothing, and the whole point of this file is that the live
// release still matches what the code expects.
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/app.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/models/release_asset.dart';
import 'package:gbm_flutter/data/models/update_state.dart';
import 'package:gbm_flutter/data/repositories/build_version_repository.dart';
import 'package:gbm_flutter/data/repositories/update_repository.dart';
import 'package:gbm_flutter/data/services/desktop_launcher.dart';
import 'package:gbm_flutter/data/services/github_release_gateway.dart';
import 'package:gbm_flutter/data/services/update_installer.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// A version no real release can be older than, so the live `latest` always
/// classifies as an update.
///
/// A debug build leaves `GBM_VERSION` unset, which makes `buildVersionProvider`
/// null and short-circuits `check()` to `developmentBuild` without touching
/// the network -- so overriding this is what lets the real check run at all.
const AppVersion _ancient = AppVersion(0, 0, 1);

/// Refuses every launch instead of opening a browser on the machine running
/// the suite. Reached only if the check comes back blocked, in which case
/// the test fails on the reason rather than on a stray Safari window.
class _NoLaunchLauncher extends DesktopLauncher {
  _NoLaunchLauncher() : super(operatingSystem: Platform.operatingSystem);

  @override
  Future<bool> openUrl(String url) async => false;
}

/// Names every `gbm-update-*` directory currently in the system temp dir.
///
/// Used to delete only what this test created: another instance of the app
/// may legitimately be downloading into one of these right now, and the
/// production sweep separates them by age precisely because the name cannot.
Set<String> _updateTempDirs() {
  try {
    return Directory.systemTemp
        .listSync(followLinks: false)
        .whereType<Directory>()
        .map((Directory d) => d.path)
        .where(
          (String p) => p
              .split(Platform.pathSeparator)
              .last
              .startsWith(kUpdateDownloadDirPrefix),
        )
        .toSet();
  } on FileSystemException {
    return <String>{};
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // Leg 1: no widgets at all. Isolates "does the live release still publish
  // what this platform needs" from anything the UI does, so a red here
  // names release.yml rather than the dialog.
  group('the live GitHub release', () {
    testWidgets('publishes a bundle this platform can install, and a '
        '$kChecksumManifestName beside it', (WidgetTester tester) async {
      final LatestRelease release = await const GithubReleaseGateway()
          .fetchLatest();

      expect(
        release.assets,
        isNotEmpty,
        reason: 'release ${release.tagName} has no assets at all',
      );

      // `assetSuffixForAbi` is the naming contract between release.yml's
      // Package step and this app. Drift on either side is invisible to
      // every other tier -- widget tests feed fixed JSON, which by
      // construction agrees with the code that reads it.
      final ReleaseAsset? bundle = selectAssetFor(
        release.assets,
        Abi.current(),
      );
      expect(
        bundle,
        isNotNull,
        reason:
            'no asset matching ${assetSuffixForAbi(Abi.current())} in '
            '${release.tagName}: ${release.assets.map((ReleaseAsset a) => a.name).toList()}',
      );

      // Without this the flow refuses to self-install at all, so its absence
      // would ship the feature dead rather than broken.
      expect(
        selectChecksumManifest(release.assets),
        isNotNull,
        reason:
            'release ${release.tagName} publishes no $kChecksumManifestName',
      );
    });
  });

  // Leg 2: the chain a user actually walks with no repository open --
  // WelcomeScreen has no menu bar, so the About dialog's button is the only
  // entry point in this state.
  group('checking for updates from WelcomeScreen', () {
    late Set<String> tempDirsBefore;

    setUp(() => tempDirsBefore = _updateTempDirs());

    tearDown(() {
      // Cancel already discards the bundle on the happy path; this covers a
      // failure that leaves ~24MB behind. Only directories this test did
      // not find on the way in are touched.
      for (final String path in _updateTempDirs().difference(tempDirsBefore)) {
        try {
          Directory(path).deleteSync(recursive: true);
        } on FileSystemException {
          // Nothing left to do about it, and failing the teardown would
          // mask whichever assertion actually went red.
        }
      }
    });

    testWidgets('downloads the real asset and verifies it against the '
        'published checksum', (WidgetTester tester) async {
      await pumpRealAppWithNoRepo(
        tester,
        extraOverrides: <Override>[
          buildVersionProvider.overrideWithValue(_ancient),
          desktopLauncherProvider.overrideWithValue(_NoLaunchLauncher()),
        ],
      );

      // Read off the app root rather than the dialog: the dialog is not
      // mounted yet, and the scope above `GbmApp` is the same one either
      // way.
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(GbmApp)),
      );

      expect(
        find.byTooltip('About'),
        findsOneWidget,
        reason: 'expected WelcomeScreen, so no repository was opened',
      );

      await tester.tap(find.byTooltip('About'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Check for updates…'));

      final UpdateState offered = await _pumpUntil(
        tester,
        container,
        (UpdateState s) => s.status == UpdateStatus.available,
        what: 'the check to report an update',
      );

      // A real release the code cannot install is a conformance failure, not
      // an acceptable outcome -- the reason is printed so a genuinely
      // unwritable install root reads as itself rather than as a mystery.
      expect(
        offered.canSelfInstall,
        isTrue,
        reason: 'self-install is blocked: ${offered.blockedReason}',
      );
      expect(find.text('Download and install'), findsOneWidget);

      await tester.tap(find.text('Download and install'));

      // Never `pumpAndSettle` here: the transfer reschedules frames for its
      // whole duration, so settling could only run out its timeout. This is
      // also a real ~24MB download over the network, hence the wide budget.
      final UpdateState ready = await _pumpUntil(
        tester,
        container,
        (UpdateState s) => s.status == UpdateStatus.readyToInstall,
        what: 'the download to finish and verify',
        timeout: const Duration(minutes: 10),
      );

      // Reaching readyToInstall *is* the checksum assertion: the downloader
      // deletes the file and fails the flow on a mismatch, which _pumpUntil
      // surfaces as a failure rather than a timeout.
      final File downloaded = File(ready.downloadedPath!);
      expect(downloaded.existsSync(), isTrue);
      expect(downloaded.lengthSync(), ready.asset!.sizeBytes);

      // Present, and deliberately not pressed.
      expect(find.text('Install and restart'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(container.read(updateProvider).status, UpdateStatus.available);
      expect(
        downloaded.existsSync(),
        isFalse,
        reason: 'backing out must not leave the bundle on disk',
      );
    });
  });
}

/// Pumps real frames until [done], failing with [what] on timeout and
/// failing immediately -- not after the whole budget -- if the flow errors.
Future<UpdateState> _pumpUntil(
  WidgetTester tester,
  ProviderContainer container,
  bool Function(UpdateState) done, {
  required String what,
  Duration timeout = const Duration(minutes: 2),
}) async {
  final Stopwatch elapsed = Stopwatch()..start();
  while (elapsed.elapsed < timeout) {
    final UpdateState state = container.read(updateProvider);
    if (done(state)) return state;
    if (state.status == UpdateStatus.failed) {
      fail('waiting for $what, the flow failed: ${state.errorMessage}');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail(
    'timed out after ${timeout.inSeconds}s waiting for $what; last status '
    'was ${container.read(updateProvider).status}',
  );
}
