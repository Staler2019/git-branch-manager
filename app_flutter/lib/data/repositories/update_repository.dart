import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_version.dart';
import '../models/release_asset.dart';
import '../models/update_state.dart';
import '../services/github_release_gateway.dart';
import '../services/update_downloader.dart';
import '../services/update_installer.dart';
import 'app_preferences_repository.dart';
import 'build_version_repository.dart';

/// What one automatic check actually managed to do.
///
/// Exists because [UpdateController.checkAutomatically] deliberately
/// collapses "already up to date" and "unreachable" into the same silent
/// [UpdateStatus.idle] outcome on screen -- correct for the UI, useless for
/// the caller that has to decide whether the once-a-day gate was really
/// spent. The distinction lives here rather than leaking into
/// [UpdateState].
enum AutoCheckOutcome {
  /// GitHub answered. Whatever the answer was, the day's check happened.
  concluded,

  /// No request was made at all -- a build with no version identity, or a
  /// flow that was already busy. Nothing was learned.
  notPerformed,

  /// A request was made and produced no answer: offline, rate limited, or a
  /// payload that would not parse. Also nothing learned.
  failed,
}

/// Drives the update flow and publishes one [UpdateState] snapshot per
/// transition.
///
/// App-level rather than repository-scoped: an update concerns the
/// installed application, and the automatic check has to run on
/// `WelcomeScreen` too, where no repository session exists.
class UpdateController extends StateNotifier<UpdateState> {
  UpdateController({
    required this._gateway,
    required this._currentVersion,
    UpdateDownloader? downloader,
    UpdateInstaller? installer,
    Directory Function()? createDownloadDir,
    Abi? abi,
    String Function()? skippedVersion,
  }) : _skippedVersion = skippedVersion ?? _nothingSkipped,
       _downloader = downloader ?? const UpdateDownloader(),
       _installer = installer ?? const UpdateInstaller(),
       _createDownloadDir = createDownloadDir ?? _createSystemTempDownloadDir,
       _abi = abi ?? Abi.current(),
       super(const UpdateState.idle());

  /// `Directory.systemTemp`, not `path_provider`: no plugin channel means a
  /// widget test can exercise the whole path, it is synchronous, and the
  /// macOS build does not run under App Sandbox. Same reasoning as the
  /// open-file-at-revision temp copy.
  static Directory _createSystemTempDownloadDir() =>
      Directory.systemTemp.createTempSync(kUpdateDownloadDirPrefix);

  final GithubReleaseGateway _gateway;
  final UpdateDownloader _downloader;
  final UpdateInstaller _installer;
  final Directory Function() _createDownloadDir;

  /// Read through a function rather than taken as a value, so the answer is
  /// whatever the preference says *now*. Taking it by value would mean
  /// rebuilding this controller whenever any preference changed, which
  /// would throw away a download in flight.
  final String Function() _skippedVersion;

  static String _nothingSkipped() => '';

  /// Created lazily on the first download and reused, so cancelling and
  /// retrying does not leave a trail of empty temp directories.
  Directory? _downloadDir;

  bool _cancelRequested = false;

  /// Null for a build with no injected version — see [isReleaseBuild].
  final AppVersion? _currentVersion;

  /// Overridable so a test can exercise every platform's asset selection
  /// from one machine.
  final Abi _abi;

  bool _checkInFlight = false;

  /// Asks GitHub for the newest release and classifies the answer.
  ///
  /// Never throws: every failure lands in [UpdateStatus.failed] with a
  /// message. Callers decide whether to show it — an automatic check stays
  /// silent (a laptop that starts up offline must not raise an error), a
  /// manual one reports both outcomes.
  Future<void> check() async {
    // A developer build has no version to compare and must never be
    // replaced: doing so would overwrite the checkout it was built from.
    // Returning before the request also keeps `flutter run` off the network.
    if (_currentVersion == null) {
      state = const UpdateState.developmentBuild();
      return;
    }

    // The startup check and a menu click can land together; fetching twice
    // would double the rate-limit cost for one answer.
    if (_checkInFlight) {
      return;
    }
    _checkInFlight = true;
    state = const UpdateState.checking();

    try {
      final LatestRelease release = await _gateway.fetchLatest();

      // `<=`, not `!=`: a release older than this build is a downgrade, and
      // offering it would be worse than saying nothing.
      if (release.version <= _currentVersion) {
        state = UpdateState.upToDate(release);
        return;
      }

      state = _classifyAvailable(release);
    } on UpdateCheckException catch (error) {
      state = UpdateState.failed(error.message);
    } on Object catch (error) {
      state = UpdateState.failed('The update check failed: $error');
    } finally {
      _checkInFlight = false;
    }
  }

  /// Decides whether the newer [release] can be installed here, and says why
  /// not when it cannot.
  ///
  /// Every "no" still reports the update — the release page stays reachable.
  /// Silently dropping it would leave the user on an old build with no way
  /// to find out.
  UpdateState _classifyAvailable(LatestRelease release) {
    final ReleaseAsset? asset = selectAssetFor(release.assets, _abi);
    if (asset == null) {
      return UpdateState.available(
        release: release,
        blockedReason:
            'This release has no download for $_abi. '
            'Install it from the release page instead.',
      );
    }

    // The bundles are neither code-signed nor notarized (release.yml's
    // signing steps no-op without their secrets), so the SHA-256 manifest
    // is the only integrity check that exists. A release without one is not
    // installable — verification is not an optional step to skip.
    if (selectChecksumManifest(release.assets) == null) {
      return UpdateState.available(
        release: release,
        blockedReason:
            'This release publishes no $kChecksumManifestName, so the '
            'download cannot be verified. Install it from the release page '
            'instead.',
      );
    }

    // Asked here rather than when the Install button is pressed, so an
    // install that was never going to work says so before the download
    // instead of after it. The installer owns the answer -- if this and the
    // install path each decided writability for themselves they could
    // disagree, and the button would be offering something that then fails.
    final String? blocker = _installer.selfInstallBlocker();
    if (blocker != null) {
      return UpdateState.available(release: release, blockedReason: blocker);
    }

    return UpdateState.available(release: release, asset: asset);
  }

  /// The startup check: silent unless there is something to offer.
  ///
  /// Ends in exactly two states. [UpdateStatus.available] means there is a
  /// release worth showing, and the caller decides how to surface it.
  /// Everything else -- up to date, unreachable, a development build, a
  /// release the user skipped -- ends back on [UpdateStatus.idle].
  ///
  /// Idle rather than the outcome's own state, because the update dialog
  /// checks on mount only when idle: a user who opens it after a
  /// silently-failed automatic check would otherwise be met with an error
  /// banner from a check they never ran.
  ///
  /// A no-op unless the flow is already idle, so a background timer cannot
  /// reset a flow the user is in the middle of.
  ///
  /// Returns what the attempt was actually worth, which the on-screen state
  /// can no longer say once it has been collapsed back to idle. The caller
  /// owns the once-a-day gate and needs the distinction; nothing else does.
  Future<AutoCheckOutcome> checkAutomatically() async {
    if (state.status != UpdateStatus.idle) {
      return AutoCheckOutcome.notPerformed;
    }
    await check();
    final UpdateState result = state;
    final bool worthShowing =
        result.status == UpdateStatus.available &&
        result.release?.version.toString() != _skippedVersion();
    if (!worthShowing) {
      state = const UpdateState.idle();
    }

    // A release the user skipped still counts as concluded: GitHub was
    // asked and answered, and the suppression is the user's own.
    return switch (result.status) {
      UpdateStatus.upToDate ||
      UpdateStatus.available => AutoCheckOutcome.concluded,
      UpdateStatus.failed => AutoCheckOutcome.failed,
      // `check()` cannot leave the flow anywhere else. Written out rather
      // than defaulted so a status added to UpdateStatus is a compile error
      // here, instead of silently deciding whether it spends the day.
      UpdateStatus.developmentBuild ||
      UpdateStatus.idle ||
      UpdateStatus.checking ||
      UpdateStatus.downloading ||
      UpdateStatus.verifying ||
      UpdateStatus.readyToInstall ||
      UpdateStatus.installing => AutoCheckOutcome.notPerformed,
    };
  }

  /// Fetches the platform bundle and verifies it, leaving the flow at
  /// [UpdateStatus.readyToInstall].
  ///
  /// A no-op unless the state is a self-installable [UpdateStatus.available],
  /// so a double click cannot start two transfers.
  Future<void> download() async {
    final UpdateState current = state;
    if (current.status != UpdateStatus.available || !current.canSelfInstall) {
      return;
    }
    final LatestRelease release = current.release!;
    final ReleaseAsset asset = current.asset!;
    final ReleaseAsset? manifest = selectChecksumManifest(release.assets);
    if (manifest == null) {
      // Unreachable via _classifyAvailable, which blocks self-install
      // without a manifest -- asserted rather than assumed, because
      // skipping verification is the one thing this flow must never do.
      state = UpdateState.failed(
        'This release publishes no $kChecksumManifestName.',
      );
      return;
    }

    _cancelRequested = false;
    // The API reports the asset size, so the bar is determinate from the
    // first frame rather than waiting for a Content-Length.
    state = UpdateState.downloading(
      release: release,
      asset: asset,
      totalBytes: asset.sizeBytes,
    );

    try {
      final Directory into = _downloadDir ??= _createDownloadDir();
      final File file = await _downloader.download(
        asset: asset,
        manifest: manifest,
        into: into,
        onProgress: (int received, int? total) {
          if (state.status == UpdateStatus.downloading) {
            state = state.withProgress(received, total ?? asset.sizeBytes);
          }
        },
        onVerifying: () {
          state = UpdateState.verifying(
            release: release,
            asset: asset,
            downloadedPath:
                '${into.path}${Platform.pathSeparator}${asset.name}',
          );
        },
        isCancelled: () => _cancelRequested,
      );

      state = UpdateState.readyToInstall(
        release: release,
        asset: asset,
        downloadedPath: file.path,
      );
    } on UpdateDownloadCancelled {
      // Not an error: back to the offer, which is where the user was.
      state = UpdateState.available(release: release, asset: asset);
    } on UpdateDownloadException catch (error) {
      state = UpdateState.failed(error.message);
    } on Object catch (error) {
      state = UpdateState.failed('The download failed: $error');
    }
  }

  /// Unpacks the verified download and hands over to the updater script.
  ///
  /// One-way, and the only state with no way back: [cancel] stops at
  /// [UpdateStatus.readyToInstall] because after this the swap is running in
  /// a detached process this one no longer controls.
  ///
  /// [beforeExit] is where the app closes its FFI sessions -- an interrupted
  /// refresh would otherwise leave an orphan git process holding an index
  /// lock in a repository the user still has open. It is supplied by the
  /// caller rather than reached for here because this layer has no business
  /// knowing which repository sessions are open.
  Future<void> install({required Future<void> Function() beforeExit}) async {
    final UpdateState current = state;
    final LatestRelease? release = current.release;
    final ReleaseAsset? asset = current.asset;
    final String? bundlePath = current.downloadedPath;
    final Directory? dir = _downloadDir;

    // The script, the transcript and the path the dialog shows the user all
    // derive from this one local, so no two of them can name different
    // places.
    final Directory scriptDir = Directory.systemTemp;
    final UpdateLog log = UpdateLog(scriptDir);

    if (current.status != UpdateStatus.readyToInstall ||
        release == null ||
        asset == null ||
        bundlePath == null ||
        dir == null) {
      // Appended rather than begun: this attempt never started, and blanking
      // the transcript would take the previous one's evidence with it. It
      // was a bare `return` -- a press of Install and restart that left the
      // dialog exactly as it was, with no record anywhere that it had been
      // refused.
      log.write('install refused: status=${current.status.name}');
      return;
    }

    state = UpdateState.installing(
      release: release,
      asset: asset,
      downloadedPath: bundlePath,
    );

    // One install attempt, one transcript. Opened here rather than inside
    // `launchUpdater` so an archive that will not unpack is recorded too --
    // that failure is reportable on screen, but the user looking in the log
    // should not find it silent there.
    log.begin('installing ${release.version} (${asset.name})');

    try {
      // Unpacked before the app quits, never inside the script: an archive
      // that will not open is then an error there is still a window to
      // report, rather than a broken install found when nothing is left
      // running to report it.
      log.write('unpacking $bundlePath');
      final Directory staged = await _installer.stage(
        bundle: File(bundlePath),
        into: dir,
      );
      // The script lives in system temp, never in the directory it is about
      // to move aside -- it would be renamed out from under itself mid-run.
      // NOTE: the download directory survives a successful install, since
      // this process is gone before the script finishes with it. Sweeping
      // stale `gbm-update-*` directories belongs with the `.gbm-old` sweep.
      final String? reason = await _installer.launchUpdater(
        staged: staged,
        scriptDir: scriptDir,
        beforeExit: beforeExit,
      );
      if (reason != null) {
        state = UpdateState.failed(reason);
      }
    } on UpdateInstallException catch (e) {
      log.write('failed: ${e.message}');
      state = UpdateState.failed(e.message);
    } on Object catch (e) {
      log.write('failed: $e');
      state = UpdateState.failed('The update could not be installed: $e');
    }
  }

  /// Backs out of an update the user has not committed to yet.
  ///
  /// Two different jobs, because "cancel" means two different things
  /// depending on where the flow is. Mid-transfer it raises a flag the
  /// download loop polls, and that loop is what publishes the new state.
  /// At [UpdateStatus.readyToInstall] the transfer has already returned, so
  /// nothing is left to poll -- setting the flag alone would leave the
  /// button inert. Cancelling there has to undo the download itself.
  ///
  /// Either way the flow lands back on the offer rather than on idle: the
  /// user declined *this install*, not the update, and Download has to be
  /// able to start over. [dismiss] is the one that closes the offer.
  ///
  /// A no-op once [UpdateStatus.installing] -- the detached script is
  /// already running and is still reading the bundle.
  void cancel() {
    _cancelRequested = true;
    final UpdateState current = state;
    if (current.status != UpdateStatus.readyToInstall) {
      return;
    }
    // Clears `_downloadDir` too, so the next download creates a fresh one
    // instead of writing into a directory that has just been deleted.
    _removeDownloadDir();
    state = UpdateState.available(
      release: current.release!,
      asset: current.asset,
    );
  }

  /// Drops a pending result and returns to idle.
  ///
  /// Also removes a downloaded bundle -- but never while installing, when
  /// the detached script is still reading it.
  void dismiss() {
    if (state.status != UpdateStatus.installing) {
      _removeDownloadDir();
    }
    state = const UpdateState.idle();
  }

  void _removeDownloadDir() {
    final Directory? dir = _downloadDir;
    _downloadDir = null;
    if (dir == null) {
      return;
    }
    try {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } on Object {
      // Best effort: a temp directory left behind is the OS's problem, and
      // failing a dismiss over it would be worse.
    }
  }
}

/// The app-wide update flow.
///
/// Not autoDispose: the dialog is opened and closed repeatedly, and a
/// downloaded-and-verified bundle must survive that — re-downloading 24MB
/// because a dialog was dismissed would be a bug, not a fresh start.
final StateNotifierProvider<UpdateController, UpdateState> updateProvider =
    StateNotifierProvider<UpdateController, UpdateState>((Ref ref) {
      return UpdateController(
        gateway: ref.watch(githubReleaseGatewayProvider),
        currentVersion: ref.watch(buildVersionProvider),
        downloader: ref.watch(updateDownloaderProvider),
        installer: ref.watch(updateInstallerProvider),
        // `read` inside the closure, not `watch` at build time: this
        // controller must not be rebuilt every time an unrelated preference
        // changes, and the skip only matters at the moment a check ends.
        skippedVersion: () => ref.read(appPreferencesProvider).skippedVersion,
      );
    });
