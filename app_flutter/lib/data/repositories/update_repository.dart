import 'dart:ffi' show Abi;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_version.dart';
import '../models/release_asset.dart';
import '../models/update_state.dart';
import '../services/github_release_gateway.dart';
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
    Abi? abi,
  }) : _abi = abi ?? Abi.current(),
       super(const UpdateState.idle());

  final GithubReleaseGateway _gateway;

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

  /// Drops a pending result and returns to idle.
  void dismiss() {
    state = const UpdateState.idle();
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
      );
    });
