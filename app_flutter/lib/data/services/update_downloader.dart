import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/release_asset.dart';

/// A streaming response: the status code, the declared length when the
/// server sent one, and the body as it arrives.
class HttpByteResponse {
  const HttpByteResponse(this.statusCode, this.contentLength, this.body);

  final int statusCode;

  /// Null when the server sent no `Content-Length`. Callers must render
  /// that as indeterminate rather than as zero.
  final int? contentLength;

  final Stream<List<int>> body;
}

/// Performs one HTTPS GET and returns the body as a stream.
///
/// Injected for the same reason as `HttpTextGet` and `ProcessStarter`: the
/// verification path is the most safety-critical code in this feature and
/// has to be exercisable without a network or a 24MB fixture.
typedef HttpByteGet =
    Future<HttpByteResponse> Function(Uri url, Map<String, String> headers);

/// Anything that stopped a download from producing a verified file.
class UpdateDownloadException implements Exception {
  const UpdateDownloadException(this.message);

  final String message;

  @override
  String toString() => 'UpdateDownloadException: $message';
}

/// The user cancelled. Distinct from [UpdateDownloadException] because it is
/// not an error to report — the UI returns to the previous state silently.
class UpdateDownloadCancelled implements Exception {
  const UpdateDownloadCancelled();

  @override
  String toString() => 'UpdateDownloadCancelled';
}

/// Parses a `sha256sum` manifest into `{file name: lowercase digest}`.
///
/// Accepts both separators the tool writes: `<digest>  <name>` (text mode)
/// and `<digest> *<name>` (binary mode). Malformed lines are skipped rather
/// than thrown on — a manifest that gains a comment or a trailing note must
/// not take down the verification of the entries that did parse.
Map<String, String> parseChecksumManifest(String text) {
  final Map<String, String> digests = <String, String>{};
  for (final String line in const LineSplitter().convert(text)) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    final int space = trimmed.indexOf(' ');
    if (space <= 0) {
      continue;
    }
    final String digest = trimmed.substring(0, space);
    String name = trimmed.substring(space + 1).trim();
    if (name.startsWith('*')) {
      name = name.substring(1);
    }
    if (digest.length != 64 || name.isEmpty) {
      continue;
    }
    digests[name] = digest.toLowerCase();
  }
  return digests;
}

/// Downloads a release bundle and refuses to hand back anything whose
/// SHA-256 does not match the release's own manifest.
///
/// **The digest is the only integrity check that exists.** The published
/// bundles are neither code-signed nor notarized — release.yml's signing
/// steps `exit 0` when their secrets are absent, and they are (measured on
/// v0.30.0: `stapler validate` reports no ticket, `spctl` reports no usable
/// signature). So the trust anchor here is TLS plus GitHub's origin, and
/// this check catches corruption in transit and a substituted body from a
/// proxy or CDN — not a compromised GitHub account, since the manifest and
/// the bundle come from the same place.
class UpdateDownloader {
  const UpdateDownloader({HttpByteGet? get}) : _get = get ?? _realGet;

  final HttpByteGet _get;

  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'git-branch-manager',
  };

  static Future<HttpByteResponse> _realGet(
    Uri url,
    Map<String, String> headers,
  ) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 30);
    final HttpClientRequest request = await client.getUrl(url);
    headers.forEach(request.headers.set);
    final HttpClientResponse response = await request.close();
    final int? length = response.contentLength < 0
        ? null
        : response.contentLength;
    // The client is closed when the body stream finishes, not here: closing
    // it now would cancel the very response being returned.
    return HttpByteResponse(
      response.statusCode,
      length,
      response
          .map((List<int> chunk) => chunk)
          .transform(
            StreamTransformer<List<int>, List<int>>.fromHandlers(
              handleDone: (EventSink<List<int>> sink) {
                client.close();
                sink.close();
              },
            ),
          ),
    );
  }

  /// Fetches [asset] into [into] and verifies it against [manifest].
  ///
  /// Returns the verified file. Throws [UpdateDownloadException] on any
  /// failure and [UpdateDownloadCancelled] when [isCancelled] turns true.
  /// In every failing case the partial or unverified file is deleted before
  /// returning — an unverified bundle must never be left somewhere the
  /// installer could later find it.
  Future<File> download({
    required ReleaseAsset asset,
    required ReleaseAsset manifest,
    required Directory into,
    void Function(int received, int? total)? onProgress,
    void Function()? onVerifying,
    bool Function()? isCancelled,
  }) async {
    // The manifest first: a bundle with no expected digest is unusable, and
    // finding that out after transferring 24MB wastes the transfer.
    final Map<String, String> digests = parseChecksumManifest(
      await _getText(manifest.downloadUrl),
    );
    final String? expected = digests[asset.name];
    if (expected == null) {
      throw UpdateDownloadException(
        '$kChecksumManifestName lists no entry for ${asset.name}, '
        'so the download cannot be verified.',
      );
    }

    final File file = File(
      '${into.path}${Platform.pathSeparator}${asset.name}',
    );
    final HttpByteResponse response = await _get(
      Uri.parse(asset.downloadUrl),
      _headers,
    );
    if (response.statusCode != 200) {
      throw UpdateDownloadException(
        'Downloading ${asset.name} returned ${response.statusCode}.',
      );
    }

    final IOSink sink = file.openWrite();
    // Hashed while streaming rather than by re-reading the finished file:
    // the bundles are tens of megabytes and a second full read is pure cost.
    final _DigestSink digestSink = _DigestSink();
    final ByteConversionSink hasher = sha256.startChunkedConversion(digestSink);
    int received = 0;

    try {
      await for (final List<int> chunk in response.body) {
        if (isCancelled?.call() ?? false) {
          throw const UpdateDownloadCancelled();
        }
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(received, response.contentLength);
        if (isCancelled?.call() ?? false) {
          throw const UpdateDownloadCancelled();
        }
      }
    } on Object {
      await sink.close();
      await _deleteQuietly(file);
      rethrow;
    }

    await sink.close();
    hasher.close();

    // Fired here rather than inferred from "progress reached total": the
    // last byte arriving and the digest being compared are different
    // moments, and on a 24MB bundle the gap is visible.
    onVerifying?.call();

    final String actual = digestSink.value.toString();
    if (actual != expected) {
      await _deleteQuietly(file);
      throw UpdateDownloadException(
        'The downloaded ${asset.name} does not match the SHA-256 published '
        'in $kChecksumManifestName. It was not installed.',
      );
    }

    return file;
  }

  Future<String> _getText(String url) async {
    final HttpByteResponse response = await _get(Uri.parse(url), _headers);
    if (response.statusCode != 200) {
      throw UpdateDownloadException(
        'Fetching $kChecksumManifestName returned ${response.statusCode}.',
      );
    }
    final List<int> bytes = <int>[];
    await for (final List<int> chunk in response.body) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (file.existsSync()) {
        await file.delete();
      }
    } on Object {
      // Best effort: a file that cannot be removed is still never returned
      // to the caller, so the installer never sees it.
    }
  }
}

/// Collects the single [Digest] `sha256.startChunkedConversion` emits.
class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Overridden in tests with a downloader built from a recording transport.
final Provider<UpdateDownloader> updateDownloaderProvider =
    Provider<UpdateDownloader>((Ref ref) => const UpdateDownloader());
