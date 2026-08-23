import 'dart:ffi' show Abi;

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/models/release_asset.dart';
import 'package:gbm_flutter/data/services/github_release_gateway.dart';

/// A minimal but shape-faithful `/releases/latest` payload. Field names and
/// nesting are copied from a real response for this repository's v0.30.0
/// release, trimmed to the keys this gateway reads.
const String _validPayload = '''
{
  "tag_name": "v0.30.0",
  "name": "v0.30.0",
  "html_url": "https://github.com/Staler2019/git-branch-manager/releases/tag/v0.30.0",
  "body": "## What's Changed\\n- fix: something",
  "draft": false,
  "prerelease": false,
  "assets": [
    {
      "name": "git-branch-manager-0.30.0-linux-x86_64.tar.gz",
      "browser_download_url": "https://example.test/linux.tar.gz",
      "size": 13189741
    },
    {
      "name": "git-branch-manager-0.30.0-macos-arm64.dmg",
      "browser_download_url": "https://example.test/macos.dmg",
      "size": 24403102
    },
    {
      "name": "git-branch-manager-0.30.0-windows-x64.zip",
      "browser_download_url": "https://example.test/windows.zip",
      "size": 16194816
    },
    {
      "name": "sha256sums.txt",
      "browser_download_url": "https://example.test/sha256sums.txt",
      "size": 328
    }
  ]
}
''';

/// Records what the gateway asked for and replays a canned response.
class _RecordingGet {
  _RecordingGet(this.response);

  final HttpTextResponse response;
  final List<Uri> urls = <Uri>[];
  final List<Map<String, String>> headers = <Map<String, String>>[];

  Future<HttpTextResponse> call(Uri url, Map<String, String> h) async {
    urls.add(url);
    headers.add(h);
    return response;
  }
}

void main() {
  group('GithubReleaseGateway.fetchLatest', () {
    test('parses the release into a LatestRelease', () async {
      final _RecordingGet get = _RecordingGet(
        const HttpTextResponse(200, _validPayload),
      );
      final LatestRelease release = await GithubReleaseGateway(
        get: get.call,
      ).fetchLatest();

      expect(release.version, const AppVersion(0, 30, 0));
      expect(release.tagName, 'v0.30.0');
      expect(release.notes, contains('fix: something'));
      expect(release.htmlUrl, endsWith('/releases/tag/v0.30.0'));
      expect(release.assets, hasLength(4));
    });

    test('requests the latest-release endpoint for this repository', () async {
      final _RecordingGet get = _RecordingGet(
        const HttpTextResponse(200, _validPayload),
      );
      await GithubReleaseGateway(get: get.call).fetchLatest();

      expect(get.urls.single.host, 'api.github.com');
      expect(get.urls.single.path, endsWith('/releases/latest'));
      expect(get.urls.single.path, contains('git-branch-manager'));
    });

    // Not cosmetic: the GitHub API answers an unauthenticated request with
    // no User-Agent with 403, so omitting it breaks every check.
    test('sends a User-Agent and an explicit Accept', () async {
      final _RecordingGet get = _RecordingGet(
        const HttpTextResponse(200, _validPayload),
      );
      await GithubReleaseGateway(get: get.call).fetchLatest();

      expect(get.headers.single['User-Agent'], isNotEmpty);
      expect(get.headers.single['Accept'], 'application/vnd.github+json');
    });

    test('throws a typed error on a non-200 status', () async {
      final _RecordingGet get = _RecordingGet(
        const HttpTextResponse(403, '{"message":"rate limit exceeded"}'),
      );

      expect(
        () => GithubReleaseGateway(get: get.call).fetchLatest(),
        throwsA(
          isA<UpdateCheckException>().having(
            (UpdateCheckException e) => e.message,
            'message',
            contains('403'),
          ),
        ),
      );
    });

    test('throws a typed error on malformed JSON', () async {
      final _RecordingGet get = _RecordingGet(
        const HttpTextResponse(200, 'not json at all'),
      );

      expect(
        () => GithubReleaseGateway(get: get.call).fetchLatest(),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    // A tag this parser cannot read is not a version it may guess at.
    test('throws when the tag is not a version', () async {
      final _RecordingGet get = _RecordingGet(
        const HttpTextResponse(200, '{"tag_name":"nightly","assets":[]}'),
      );

      expect(
        () => GithubReleaseGateway(get: get.call).fetchLatest(),
        throwsA(
          isA<UpdateCheckException>().having(
            (UpdateCheckException e) => e.message,
            'message',
            contains('nightly'),
          ),
        ),
      );
    });

    test('wraps a transport failure rather than letting it escape', () async {
      Future<HttpTextResponse> boom(
        Uri url,
        Map<String, String> headers,
      ) async {
        throw const SocketExceptionStub();
      }

      expect(
        () => GithubReleaseGateway(get: boom).fetchLatest(),
        throwsA(isA<UpdateCheckException>()),
      );
    });
  });

  group('asset selection', () {
    late List<ReleaseAsset> assets;

    setUp(() {
      assets = <ReleaseAsset>[
        const ReleaseAsset(
          name: 'git-branch-manager-0.30.0-linux-x86_64.tar.gz',
          downloadUrl: 'https://example.test/linux.tar.gz',
          sizeBytes: 13189741,
        ),
        const ReleaseAsset(
          name: 'git-branch-manager-0.30.0-macos-arm64.dmg',
          downloadUrl: 'https://example.test/macos.dmg',
          sizeBytes: 24403102,
        ),
        const ReleaseAsset(
          name: 'git-branch-manager-0.30.0-windows-x64.zip',
          downloadUrl: 'https://example.test/windows.zip',
          sizeBytes: 16194816,
        ),
        const ReleaseAsset(
          name: 'sha256sums.txt',
          downloadUrl: 'https://example.test/sha256sums.txt',
          sizeBytes: 328,
        ),
      ];
    });

    test('picks the .dmg on Apple silicon', () {
      expect(
        selectAssetFor(assets, Abi.macosArm64)?.name,
        endsWith('-macos-arm64.dmg'),
      );
    });

    test('picks the .zip on Windows x64', () {
      expect(
        selectAssetFor(assets, Abi.windowsX64)?.name,
        endsWith('-windows-x64.zip'),
      );
    });

    test('picks the .tar.gz on Linux x64', () {
      expect(
        selectAssetFor(assets, Abi.linuxX64)?.name,
        endsWith('-linux-x86_64.tar.gz'),
      );
    });

    // release.yml publishes three artifacts and no more. An Intel Mac, an
    // ARM Linux box or an ARM Windows machine has nothing to install, and
    // must be told so rather than handed another platform's bundle.
    test('returns null for an ABI this project does not publish', () {
      for (final Abi abi in <Abi>[
        Abi.macosX64,
        Abi.linuxArm64,
        Abi.windowsArm64,
      ]) {
        expect(selectAssetFor(assets, abi), isNull, reason: '$abi');
      }
    });

    test(
      'returns null when the matching asset is missing from the release',
      () {
        final List<ReleaseAsset> withoutMac = assets
            .where((ReleaseAsset a) => !a.name.endsWith('.dmg'))
            .toList();
        expect(selectAssetFor(withoutMac, Abi.macosArm64), isNull);
      },
    );

    test('finds the checksum manifest by its exact name', () {
      expect(
        selectChecksumManifest(assets)?.downloadUrl,
        'https://example.test/sha256sums.txt',
      );
      expect(selectChecksumManifest(<ReleaseAsset>[]), isNull);
    });
  });
}

/// Stands in for a `dart:io` SocketException without importing it, so the
/// test states only what matters: the gateway must not leak a transport
/// exception to its caller.
class SocketExceptionStub implements Exception {
  const SocketExceptionStub();
}
