import 'dart:ffi' show Abi;

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/models/release_asset.dart';
import 'package:gbm_flutter/data/models/update_state.dart';
import 'package:gbm_flutter/data/repositories/update_repository.dart';
import 'package:gbm_flutter/data/services/github_release_gateway.dart';

LatestRelease _release(String tag, {List<ReleaseAsset>? assets}) {
  return LatestRelease(
    version: AppVersion.tryParse(tag)!,
    tagName: tag,
    htmlUrl: 'https://example.test/releases/tag/$tag',
    notes: 'notes for $tag',
    assets:
        assets ??
        const <ReleaseAsset>[
          ReleaseAsset(
            name: 'git-branch-manager-9.9.9-macos-arm64.dmg',
            downloadUrl: 'https://example.test/macos.dmg',
            sizeBytes: 100,
          ),
          ReleaseAsset(
            name: 'sha256sums.txt',
            downloadUrl: 'https://example.test/sha256sums.txt',
            sizeBytes: 10,
          ),
        ],
  );
}

/// Replays a canned answer and counts calls, so "checked exactly once" is
/// assertable — `.any(...)` cannot see a double fetch.
class _FakeGateway implements GithubReleaseGateway {
  _FakeGateway({this.result, this.error});

  final LatestRelease? result;
  final Object? error;
  int calls = 0;

  @override
  Future<LatestRelease> fetchLatest() async {
    calls++;
    if (error != null) {
      throw error!;
    }
    return result!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

UpdateController _controller({
  LatestRelease? result,
  Object? error,
  AppVersion? current = const AppVersion(0, 30, 0),
  Abi? abi,
}) {
  return UpdateController(
    gateway: _FakeGateway(result: result, error: error),
    currentVersion: current,
    abi: abi ?? Abi.macosArm64,
  );
}

void main() {
  group('check', () {
    test('starts idle', () {
      expect(
        _controller(result: _release('v9.9.9')).state.status,
        UpdateStatus.idle,
      );
    });

    test(
      'a newer release becomes available with its notes and asset',
      () async {
        final UpdateController c = _controller(result: _release('v9.9.9'));
        await c.check();

        expect(c.state.status, UpdateStatus.available);
        expect(c.state.release?.tagName, 'v9.9.9');
        expect(c.state.asset?.name, endsWith('-macos-arm64.dmg'));
        expect(c.state.isUpdateAvailable, isTrue);
        expect(c.state.canSelfInstall, isTrue);
      },
    );

    test('the same version is up to date', () async {
      final UpdateController c = _controller(result: _release('v0.30.0'));
      await c.check();

      expect(c.state.status, UpdateStatus.upToDate);
      expect(c.state.isUpdateAvailable, isFalse);
    });

    // A published release older than the running build must never be
    // offered: that is a downgrade, not an update.
    test('an older release is up to date, not an offer to downgrade', () async {
      final UpdateController c = _controller(result: _release('v0.29.0'));
      await c.check();

      expect(c.state.status, UpdateStatus.upToDate);
      expect(c.state.isUpdateAvailable, isFalse);
    });

    test('a developer build never checks and never offers', () async {
      final _FakeGateway gateway = _FakeGateway(result: _release('v9.9.9'));
      final UpdateController c = UpdateController(
        gateway: gateway,
        currentVersion: null,
        abi: Abi.macosArm64,
      );
      await c.check();

      expect(c.state.status, UpdateStatus.developmentBuild);
      expect(
        gateway.calls,
        0,
        reason: 'a developer build must not even reach the network',
      );
    });

    test('a failure carries its message', () async {
      final UpdateController c = _controller(
        error: const UpdateCheckException('GitHub returned 403'),
      );
      await c.check();

      expect(c.state.status, UpdateStatus.failed);
      expect(c.state.errorMessage, contains('403'));
    });

    test('an unexpected error is still reported, not thrown', () async {
      final UpdateController c = _controller(error: StateError('boom'));
      await c.check();

      expect(c.state.status, UpdateStatus.failed);
      expect(c.state.errorMessage, isNotEmpty);
    });

    // The bug `copyWith` with `??` would have produced: re-checking after a
    // failure keeps the stale message and the dialog shows a fresh success
    // beside an old error.
    test('re-checking after a failure clears the previous error', () async {
      final UpdateController failing = _controller(
        error: const UpdateCheckException('offline'),
      );
      await failing.check();
      expect(failing.state.errorMessage, isNotNull);

      final UpdateController c = _controller(result: _release('v0.30.0'));
      await c.check();
      expect(c.state.errorMessage, isNull);
    });

    test('passes through checking on the way', () async {
      final UpdateController c = _controller(result: _release('v9.9.9'));
      final List<UpdateStatus> seen = <UpdateStatus>[];
      c.addListener((UpdateState s) => seen.add(s.status));

      await c.check();

      expect(
        seen,
        containsAllInOrder(<UpdateStatus>[
          UpdateStatus.checking,
          UpdateStatus.available,
        ]),
      );
    });

    test('a concurrent check does not fetch twice', () async {
      final _FakeGateway gateway = _FakeGateway(result: _release('v9.9.9'));
      final UpdateController c = UpdateController(
        gateway: gateway,
        currentVersion: const AppVersion(0, 30, 0),
        abi: Abi.macosArm64,
      );

      await Future.wait<void>(<Future<void>>[c.check(), c.check()]);

      expect(gateway.calls, 1);
    });
  });

  group('blocked platforms', () {
    // An Intel Mac: the update is real and must be reported, but there is
    // no bundle for it, so the way forward is the release page.
    test(
      'an unpublished ABI reports the update and explains the block',
      () async {
        final UpdateController c = _controller(
          result: _release('v9.9.9'),
          abi: Abi.macosX64,
        );
        await c.check();

        expect(c.state.status, UpdateStatus.available);
        expect(c.state.isUpdateAvailable, isTrue);
        expect(c.state.canSelfInstall, isFalse);
        expect(c.state.blockedReason, isNotEmpty);
      },
    );

    test(
      'a release missing this platform asset is blocked, not failed',
      () async {
        final UpdateController c = _controller(
          result: _release(
            'v9.9.9',
            assets: const <ReleaseAsset>[
              ReleaseAsset(
                name: 'sha256sums.txt',
                downloadUrl: 'https://example.test/sha256sums.txt',
                sizeBytes: 10,
              ),
            ],
          ),
        );
        await c.check();

        expect(c.state.status, UpdateStatus.available);
        expect(c.state.canSelfInstall, isFalse);
      },
    );

    // Verification is the only integrity check there is -- the published
    // bundles are neither signed nor notarized -- so a release without the
    // manifest must not be installable.
    test(
      'a release with no checksum manifest cannot be self-installed',
      () async {
        final UpdateController c = _controller(
          result: _release(
            'v9.9.9',
            assets: const <ReleaseAsset>[
              ReleaseAsset(
                name: 'git-branch-manager-9.9.9-macos-arm64.dmg',
                downloadUrl: 'https://example.test/macos.dmg',
                sizeBytes: 100,
              ),
            ],
          ),
        );
        await c.check();

        expect(c.state.canSelfInstall, isFalse);
        expect(c.state.blockedReason, contains(kChecksumManifestName));
      },
    );
  });

  group('dismiss', () {
    test('returns to idle and drops the pending release', () async {
      final UpdateController c = _controller(result: _release('v9.9.9'));
      await c.check();
      c.dismiss();

      expect(c.state.status, UpdateStatus.idle);
      expect(c.state.release, isNull);
      expect(c.state.isUpdateAvailable, isFalse);
    });
  });
}
