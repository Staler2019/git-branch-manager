import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/release_asset.dart';
import 'package:gbm_flutter/data/services/update_downloader.dart';

/// The real v0.30.0 manifest, byte for byte, so the parser is pinned against
/// what `sha256sum` actually writes rather than against a guess.
const String _realManifest =
    '7b2670c50f61e93a68f381a94728bb974f86a58b7ed5711a8597dcd86db78760  git-branch-manager-0.30.0-linux-x86_64.tar.gz\n'
    'be5d8ffe6e63f5277aac3f8e98d7110b1f655a5bb986325ac35b747ab415c3ac  git-branch-manager-0.30.0-macos-arm64.dmg\n'
    '87e78ed3d2cf78fb30591c8f3f1cbab475de9106616af082d5ca5efa3472b23b  git-branch-manager-0.30.0-windows-x64.zip\n';

/// SHA-256 of the ASCII bytes `hello`, from `printf hello | shasum -a 256`.
const String _helloDigest =
    '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

const ReleaseAsset _asset = ReleaseAsset(
  name: 'git-branch-manager-9.9.9-macos-arm64.dmg',
  downloadUrl: 'https://example.test/macos.dmg',
  sizeBytes: 5,
);

const ReleaseAsset _manifestAsset = ReleaseAsset(
  name: 'sha256sums.txt',
  downloadUrl: 'https://example.test/sha256sums.txt',
  sizeBytes: 100,
);

/// Serves canned bodies per URL, in chunks, so progress reporting is
/// observable and the streaming path is the one under test.
class _FakeTransport {
  _FakeTransport(this.bodies, {this.contentLengths = const <String, int?>{}});

  final Map<String, List<List<int>>> bodies;
  final Map<String, int?> contentLengths;
  final List<Uri> urls = <Uri>[];

  Future<HttpByteResponse> call(Uri url, Map<String, String> headers) async {
    urls.add(url);
    final List<List<int>>? chunks = bodies[url.toString()];
    if (chunks == null) {
      return HttpByteResponse(404, null, const Stream<List<int>>.empty());
    }
    return HttpByteResponse(
      200,
      contentLengths.containsKey(url.toString())
          ? contentLengths[url.toString()]
          : chunks.fold<int>(0, (int n, List<int> c) => n + c.length),
      Stream<List<int>>.fromIterable(chunks),
    );
  }
}

_FakeTransport _transportServing(
  List<int> assetBytes, {
  String manifest = '',
  int? contentLength,
  bool omitContentLength = false,
}) {
  return _FakeTransport(
    <String, List<List<int>>>{
      _asset.downloadUrl: <List<int>>[assetBytes],
      _manifestAsset.downloadUrl: <List<int>>[utf8.encode(manifest)],
    },
    contentLengths: omitContentLength
        ? <String, int?>{_asset.downloadUrl: null}
        : (contentLength == null
              ? const <String, int?>{}
              : <String, int?>{_asset.downloadUrl: contentLength}),
  );
}

void main() {
  group('parseChecksumManifest', () {
    test('reads a real sha256sum manifest', () {
      final Map<String, String> digests = parseChecksumManifest(_realManifest);

      expect(digests, hasLength(3));
      expect(
        digests['git-branch-manager-0.30.0-macos-arm64.dmg'],
        'be5d8ffe6e63f5277aac3f8e98d7110b1f655a5bb986325ac35b747ab415c3ac',
      );
    });

    // `sha256sum -b` writes ` *name` instead of `  name`.
    test('reads the binary-mode marker', () {
      expect(
        parseChecksumManifest('$_helloDigest *thing.zip')['thing.zip'],
        _helloDigest,
      );
    });

    test('ignores blank and malformed lines rather than throwing', () {
      final Map<String, String> digests = parseChecksumManifest(
        '\n'
        'garbage-with-no-separator\n'
        '$_helloDigest  ok.zip\n'
        '\n',
      );

      expect(digests, hasLength(1));
      expect(digests['ok.zip'], _helloDigest);
    });

    test('lower-cases the digest so comparison is case-insensitive', () {
      expect(
        parseChecksumManifest('${_helloDigest.toUpperCase()}  a.zip')['a.zip'],
        _helloDigest,
      );
    });
  });

  group('download', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('gbm-update-test');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('writes the verified bytes and returns the file', () async {
      final _FakeTransport transport = _transportServing(
        utf8.encode('hello'),
        manifest: '$_helloDigest  ${_asset.name}',
      );

      final File file = await UpdateDownloader(
        get: transport.call,
      ).download(asset: _asset, manifest: _manifestAsset, into: tempDir);

      expect(file.existsSync(), isTrue);
      expect(file.readAsStringSync(), 'hello');
      expect(file.path, endsWith(_asset.name));
    });

    // The assertion the whole feature rests on. A corrupted or substituted
    // bundle must never reach the installer.
    test('a digest mismatch throws and leaves no file behind', () async {
      final _FakeTransport transport = _transportServing(
        utf8.encode('tampered'),
        manifest: '$_helloDigest  ${_asset.name}',
      );

      await expectLater(
        UpdateDownloader(
          get: transport.call,
        ).download(asset: _asset, manifest: _manifestAsset, into: tempDir),
        throwsA(
          isA<UpdateDownloadException>().having(
            (UpdateDownloadException e) => e.message,
            'message',
            contains('does not match'),
          ),
        ),
      );

      expect(
        tempDir.listSync(),
        isEmpty,
        reason: 'an unverified download must not be left on disk',
      );
    });

    test('a manifest with no entry for this asset throws', () async {
      final _FakeTransport transport = _transportServing(
        utf8.encode('hello'),
        manifest: '$_helloDigest  some-other-file.zip',
      );

      await expectLater(
        UpdateDownloader(
          get: transport.call,
        ).download(asset: _asset, manifest: _manifestAsset, into: tempDir),
        throwsA(isA<UpdateDownloadException>()),
      );
      expect(tempDir.listSync(), isEmpty);
    });

    test('reports progress as bytes arrive', () async {
      final _FakeTransport transport = _FakeTransport(<String, List<List<int>>>{
        _asset.downloadUrl: <List<int>>[
          utf8.encode('he'),
          utf8.encode('ll'),
          utf8.encode('o'),
        ],
        _manifestAsset.downloadUrl: <List<int>>[
          utf8.encode('$_helloDigest  ${_asset.name}'),
        ],
      });

      final List<int> seen = <int>[];
      await UpdateDownloader(get: transport.call).download(
        asset: _asset,
        manifest: _manifestAsset,
        into: tempDir,
        onProgress: (int received, int? total) => seen.add(received),
      );

      expect(seen, <int>[2, 4, 5]);
    });

    test('a non-200 on the bundle throws', () async {
      final _FakeTransport transport = _FakeTransport(<String, List<List<int>>>{
        _manifestAsset.downloadUrl: <List<int>>[
          utf8.encode('$_helloDigest  ${_asset.name}'),
        ],
      });

      await expectLater(
        UpdateDownloader(
          get: transport.call,
        ).download(asset: _asset, manifest: _manifestAsset, into: tempDir),
        throwsA(isA<UpdateDownloadException>()),
      );
    });

    test(
      'cancelling stops the download and removes the partial file',
      () async {
        final _FakeTransport transport = _FakeTransport(
          <String, List<List<int>>>{
            _asset.downloadUrl: <List<int>>[
              utf8.encode('he'),
              utf8.encode('ll'),
              utf8.encode('o'),
            ],
            _manifestAsset.downloadUrl: <List<int>>[
              utf8.encode('$_helloDigest  ${_asset.name}'),
            ],
          },
        );

        bool cancelled = false;
        await expectLater(
          UpdateDownloader(get: transport.call).download(
            asset: _asset,
            manifest: _manifestAsset,
            into: tempDir,
            isCancelled: () => cancelled,
            onProgress: (int received, int? _) {
              if (received >= 2) {
                cancelled = true;
              }
            },
          ),
          throwsA(isA<UpdateDownloadCancelled>()),
        );

        expect(tempDir.listSync(), isEmpty);
      },
    );

    // A server that sends no Content-Length must produce an indeterminate
    // bar, not a 0% one -- see UpdateState.progress.
    test('a missing Content-Length reports a null total', () async {
      final _FakeTransport transport = _transportServing(
        utf8.encode('hello'),
        manifest: '$_helloDigest  ${_asset.name}',
        omitContentLength: true,
      );

      final List<int?> totals = <int?>[];
      await UpdateDownloader(get: transport.call).download(
        asset: _asset,
        manifest: _manifestAsset,
        into: tempDir,
        onProgress: (int _, int? total) => totals.add(total),
      );

      expect(totals, everyElement(isNull));
    });
  });
}
