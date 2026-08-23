import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_version.dart';
import '../models/release_asset.dart';
import '../models/update_state.dart';
import '../services/github_release_gateway.dart';
import '../services/update_downloader.dart';
import 'build_version_repository.dart';

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
    Directory Function()? createDownloadDir,
    Abi? abi,
  }) : _downloader = downloader ?? const UpdateDownloader(),
       _createDownloadDir = createDownloadDir ?? _createSystemTempDownloadDir,
       _abi = abi ?? Abi.current(),
       super(const UpdateState.idle());

  /// `Directory.systemTemp`, not `path_provider`: no plugin channel means a
  /// widget test can exercise the whole path, it is synchronous, and the
  /// macOS build does not run under App Sandbox. Same reasoning as the
  /// open-file-at-revision temp copy.
  static Directory _createSystemTempDownloadDir() =>
      Directory.systemTemp.createTempSync('gbm-update-');

  final GithubReleaseGateway _gateway;
  final UpdateDownloader _downloader;
  final Directory Function() _createDownloadDir;

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

    return UpdateState.available(release: release, asset: asset);
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

  /// Asks an in-flight download to stop.
  ///
  /// Only meaningful while [UpdateState.isCancellable]; once the updater
  /// script is detached there is nothing left to stop.
  void cancel() {
    _cancelRequested = true;
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
      );
    });
