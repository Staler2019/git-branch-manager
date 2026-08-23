import 'package:flutter/foundation.dart';

import 'release_asset.dart';

/// Where the update flow currently is.
///
/// The whole flow is one linear path with two terminal branches:
///
/// ```
/// idle ──check──▶ checking ──▶ upToDate
///                    │
///                    ├──▶ available ──download──▶ downloading
///                    │                                 │
///                    │                                 ▼
///                    │                             verifying ──▶ readyToInstall
///                    │                                                  │
///                    ├──▶ developmentBuild                       install│
///                    └──▶ failed ◀── (any step)                         ▼
///                                                                  installing
///                                                                  (process exits)
/// ```
///
/// Cancelling is possible up to and including [readyToInstall]. Once
/// [installing] is entered the detached updater script is already running
/// and this process is on its way out, so there is nothing left to cancel —
/// which is why the transition into it is behind an explicit confirmation
/// rather than reachable from a progress bar.
enum UpdateStatus {
  /// Nothing has been checked yet this session.
  idle,

  /// A request to GitHub is in flight.
  checking,

  /// The newest release is this build, or older than it.
  upToDate,

  /// A newer release exists. [UpdateState.release] is set.
  available,

  /// The platform bundle is being fetched. [UpdateState.progress] is live.
  downloading,

  /// The bundle is downloaded and its SHA-256 is being compared against the
  /// release's `sha256sums.txt`.
  verifying,

  /// Verified on disk at [UpdateState.downloadedPath], waiting for the user
  /// to confirm the replace-and-restart.
  readyToInstall,

  /// The detached updater has been started; this process is exiting.
  installing,

  /// This build carries no version, so there is nothing to compare against
  /// and nothing that may be safely replaced — see `isReleaseBuild`.
  developmentBuild,

  /// [UpdateState.errorMessage] says what stopped the flow.
  failed,
}

/// The update flow's single immutable snapshot, republished through
/// `copyWith` on every transition (docs/ARCHITECTURE.md invariant 2).
///
/// App-level, not repository-scoped: an update concerns the installed
/// application, and the check has to run on `WelcomeScreen` too — where no
/// repository session exists at all.
@immutable
class UpdateState {
  const UpdateState._({
    required this.status,
    this.release,
    this.asset,
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.downloadedPath,
    this.errorMessage,
    this.blockedReason,
  });

  /// Nothing checked yet, or a pending result dismissed.
  const UpdateState.idle() : this._(status: UpdateStatus.idle);

  /// A request is in flight. Deliberately carries nothing else: entering
  /// this state is what clears a previous run's error, release and
  /// progress.
  const UpdateState.checking() : this._(status: UpdateStatus.checking);

  /// This build has no version to compare, so nothing was requested.
  const UpdateState.developmentBuild()
    : this._(status: UpdateStatus.developmentBuild);

  const UpdateState.upToDate(LatestRelease release)
    : this._(status: UpdateStatus.upToDate, release: release);

  /// A newer release exists. [asset] and [blockedReason] are mutually
  /// exclusive: either this platform has a bundle to install, or there is a
  /// stated reason it does not.
  const UpdateState.available({
    required LatestRelease release,
    ReleaseAsset? asset,
    String? blockedReason,
  }) : this._(
         status: UpdateStatus.available,
         release: release,
         asset: asset,
         blockedReason: blockedReason,
       );

  const UpdateState.failed(String message)
    : this._(status: UpdateStatus.failed, errorMessage: message);

  /// Each factory builds a complete state rather than layering onto the
  /// previous one, which is why there is no general `copyWith`: with `??`
  /// semantics it cannot *clear* a nullable field, so a re-check after a
  /// failure would keep the stale [errorMessage] and the dialog would show
  /// a fresh success beside an old error. The two transitions that really
  /// are incremental ([withProgress], [verifying]) are named instead.
  const UpdateState.downloading({
    required LatestRelease release,
    required ReleaseAsset asset,
    int downloadedBytes = 0,
    int totalBytes = 0,
  }) : this._(
         status: UpdateStatus.downloading,
         release: release,
         asset: asset,
         downloadedBytes: downloadedBytes,
         totalBytes: totalBytes,
       );

  const UpdateState.verifying({
    required LatestRelease release,
    required ReleaseAsset asset,
    required String downloadedPath,
  }) : this._(
         status: UpdateStatus.verifying,
         release: release,
         asset: asset,
         downloadedPath: downloadedPath,
       );

  const UpdateState.readyToInstall({
    required LatestRelease release,
    required ReleaseAsset asset,
    required String downloadedPath,
  }) : this._(
         status: UpdateStatus.readyToInstall,
         release: release,
         asset: asset,
         downloadedPath: downloadedPath,
       );

  const UpdateState.installing({
    required LatestRelease release,
    required ReleaseAsset asset,
    required String downloadedPath,
  }) : this._(
         status: UpdateStatus.installing,
         release: release,
         asset: asset,
         downloadedPath: downloadedPath,
       );

  final UpdateStatus status;

  /// The newest release, from [UpdateStatus.available] onward.
  final LatestRelease? release;

  /// The bundle this platform would install. Null while [blockedReason]
  /// explains that there is none.
  final ReleaseAsset? asset;

  final int downloadedBytes;
  final int totalBytes;

  /// Where the verified bundle is on disk, set from
  /// [UpdateStatus.verifying] onward.
  final String? downloadedPath;

  /// Set only when [status] is [UpdateStatus.failed].
  final String? errorMessage;

  /// Why this machine cannot install the update by itself -- an unpublished
  /// CPU architecture, a release with no bundle or no checksum manifest, an
  /// install directory this process cannot write.
  ///
  /// Deliberately **not** a status of its own: the update still exists and
  /// the user should still be told about it, just with the release page as
  /// the way forward instead of the Install button. Folding it into
  /// [UpdateStatus] would have made "there is an update" and "I can install
  /// it" the same question.
  final String? blockedReason;

  /// Advances download progress without disturbing anything else.
  UpdateState withProgress(int downloadedBytes, int totalBytes) {
    return UpdateState._(
      status: status,
      release: release,
      asset: asset,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      downloadedPath: downloadedPath,
      errorMessage: errorMessage,
      blockedReason: blockedReason,
    );
  }

  /// Whether a newer release was found, whatever can be done about it.
  bool get isUpdateAvailable =>
      release != null &&
      status != UpdateStatus.upToDate &&
      status != UpdateStatus.developmentBuild;

  /// Whether the update can be applied by this app on this machine.
  bool get canSelfInstall => asset != null && blockedReason == null;

  /// Whether a cancel is still meaningful. False from
  /// [UpdateStatus.installing] on, because the updater script is already
  /// detached by then.
  bool get isCancellable =>
      status == UpdateStatus.downloading ||
      status == UpdateStatus.verifying ||
      status == UpdateStatus.readyToInstall;

  /// 0.0-1.0, or null while the total is unknown -- a server that sends no
  /// `Content-Length` must render as indeterminate rather than as 0%.
  double? get progress {
    if (totalBytes <= 0) {
      return null;
    }
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }
}
