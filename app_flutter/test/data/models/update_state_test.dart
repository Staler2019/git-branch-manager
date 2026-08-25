import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/models/release_asset.dart';
import 'package:gbm_flutter/data/models/update_state.dart';

const ReleaseAsset _asset = ReleaseAsset(
  name: 'git-branch-manager-9.9.9-windows-x64.zip',
  downloadUrl: 'https://example.test/windows.zip',
  sizeBytes: 16000000,
);

final LatestRelease _release = LatestRelease(
  version: const AppVersion(9, 9, 9),
  tagName: 'v9.9.9',
  htmlUrl: 'https://example.test/releases/tag/v9.9.9',
  notes: '',
  assets: const <ReleaseAsset>[_asset],
);

/// One representative state per [UpdateStatus], so a new status added to the
/// enum without a decision here fails the completeness test below rather than
/// silently inheriting whatever the getter's fall-through happens to be.
final Map<UpdateStatus, UpdateState> _oneOfEach = <UpdateStatus, UpdateState>{
  UpdateStatus.idle: const UpdateState.idle(),
  UpdateStatus.checking: const UpdateState.checking(),
  UpdateStatus.upToDate: UpdateState.upToDate(_release),
  UpdateStatus.available: UpdateState.available(
    release: _release,
    asset: _asset,
  ),
  UpdateStatus.downloading: UpdateState.downloading(
    release: _release,
    asset: _asset,
  ),
  UpdateStatus.verifying: UpdateState.verifying(
    release: _release,
    asset: _asset,
    downloadedPath: '/tmp/x.zip',
  ),
  UpdateStatus.readyToInstall: UpdateState.readyToInstall(
    release: _release,
    asset: _asset,
    downloadedPath: '/tmp/x.zip',
  ),
  UpdateStatus.installing: UpdateState.installing(
    release: _release,
    asset: _asset,
    downloadedPath: '/tmp/x.zip',
  ),
  UpdateStatus.developmentBuild: const UpdateState.developmentBuild(),
  UpdateStatus.failed: const UpdateState.failed('offline'),
};

void main() {
  group('UpdateState.wantsFreshCheck', () {
    test('covers every status, so a new one cannot slip through untested', () {
      expect(_oneOfEach.keys.toSet(), UpdateStatus.values.toSet());
    });

    // The three terminal answers. Nothing in the flow returns them to idle,
    // so without this the dialog replays its own last answer for the rest of
    // the session -- the reported "not checking update again when re-enter".
    test('a settled answer is stale and wants replacing', () {
      expect(_oneOfEach[UpdateStatus.idle]!.wantsFreshCheck, isTrue);
      expect(_oneOfEach[UpdateStatus.upToDate]!.wantsFreshCheck, isTrue);
      expect(_oneOfEach[UpdateStatus.failed]!.wantsFreshCheck, isTrue);
      expect(
        _oneOfEach[UpdateStatus.developmentBuild]!.wantsFreshCheck,
        isTrue,
      );
    });

    // A standing offer is not a stale answer -- it is the thing the user has
    // not acted on yet, and it is what the startup check pushes the dialog
    // *at*, so re-checking it would hit the commonest path.
    test('a standing offer is left alone', () {
      expect(_oneOfEach[UpdateStatus.available]!.wantsFreshCheck, isFalse);
    });

    test('nothing with a request or a transfer in flight is restarted', () {
      for (final UpdateStatus status in <UpdateStatus>[
        UpdateStatus.checking,
        UpdateStatus.downloading,
        UpdateStatus.verifying,
        UpdateStatus.readyToInstall,
        UpdateStatus.installing,
      ]) {
        expect(
          _oneOfEach[status]!.wantsFreshCheck,
          isFalse,
          reason: '$status still holds work a re-check would discard',
        );
      }
    });

    // The two getters partition the enum differently on purpose: `checking`
    // and `installing` can neither be cancelled nor restarted, and
    // `readyToInstall` can be cancelled but must not be restarted.
    test('is not a restatement of isCancellable', () {
      expect(_oneOfEach[UpdateStatus.readyToInstall]!.isCancellable, isTrue);
      expect(_oneOfEach[UpdateStatus.readyToInstall]!.wantsFreshCheck, isFalse);
      expect(_oneOfEach[UpdateStatus.failed]!.isCancellable, isFalse);
      expect(_oneOfEach[UpdateStatus.failed]!.wantsFreshCheck, isTrue);
    });
  });
}
