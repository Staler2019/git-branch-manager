import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_version.dart';
import '../models/release_asset.dart';
import 'desktop_launcher.dart';

/// A text response: the status line's code and the decoded body.
class HttpTextResponse {
  const HttpTextResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;
}

/// Performs one HTTPS GET and returns the body as text.
///
/// Injected rather than calling [HttpClient] directly, for the same reason
/// `ProcessStarter` is injected into `DesktopLauncher`: so a unit test can
/// assert what was requested — including the headers, which are load-bearing
/// here — without reaching the network.
typedef HttpTextGet =
    Future<HttpTextResponse> Function(Uri url, Map<String, String> headers);

/// Anything that stopped an update check from producing an answer.
///
/// One type covers transport failures, HTTP errors and malformed payloads
/// on purpose: every caller treats them identically. An automatic check
/// swallows it (a laptop that starts up offline must not show an error), a
/// manual check reports [message] verbatim.
class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => 'UpdateCheckException: $message';
}

/// Reads this project's newest published release from the GitHub REST API.
///
/// Unauthenticated: the endpoint is public and the rate limit (60 requests
/// per hour per IP) is far above one check per app start plus the occasional
/// manual one. Adding a token would mean shipping a credential.
class GithubReleaseGateway {
  const GithubReleaseGateway({HttpTextGet? get}) : _get = get ?? _realGet;

  final HttpTextGet _get;

  /// GitHub rejects an unauthenticated API request that carries no
  /// User-Agent with 403, so this is required, not decorative. The explicit
  /// `Accept` pins the response schema to v3 rather than whatever the
  /// default becomes.
  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'git-branch-manager',
    'Accept': 'application/vnd.github+json',
    'X-GitHub-Api-Version': '2022-11-28',
  };

  static Future<HttpTextResponse> _realGet(
    Uri url,
    Map<String, String> headers,
  ) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final HttpClientRequest request = await client.getUrl(url);
      headers.forEach(request.headers.set);
      final HttpClientResponse response = await request.close();
      final String body = await response.transform(utf8.decoder).join();
      return HttpTextResponse(response.statusCode, body);
    } finally {
      client.close();
    }
  }

  /// Fetches and parses the newest release.
  ///
  /// Throws [UpdateCheckException] for every failure mode; nothing else
  /// escapes.
  Future<LatestRelease> fetchLatest() async {
    final HttpTextResponse response;
    try {
      response = await _get(Uri.parse(GbmUrls.latestReleaseApi), _headers);
    } on Object catch (error) {
      throw UpdateCheckException('Could not reach GitHub: $error');
    }

    if (response.statusCode != 200) {
      throw UpdateCheckException(
        'GitHub returned ${response.statusCode} for the latest release.',
      );
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw UpdateCheckException('Could not read GitHub\'s reply: $error');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const UpdateCheckException(
        'GitHub\'s reply was not a release object.',
      );
    }

    final String tagName = decoded['tag_name'] as String? ?? '';
    final AppVersion? version = AppVersion.tryParse(tagName);
    if (version == null) {
      // A tag this parser cannot read is not a version to guess at -- an
      // unreadable tag must stop the check, not become 0.0.0 and offer a
      // downgrade.
      throw UpdateCheckException(
        'The latest release is tagged "$tagName", which is not a version.',
      );
    }

    return LatestRelease(
      version: version,
      tagName: tagName,
      htmlUrl: decoded['html_url'] as String? ?? GbmUrls.releasesPage,
      notes: decoded['body'] as String? ?? '',
      assets: _parseAssets(decoded['assets']),
    );
  }

  static List<ReleaseAsset> _parseAssets(Object? raw) {
    if (raw is! List<Object?>) {
      return const <ReleaseAsset>[];
    }
    final List<ReleaseAsset> assets = <ReleaseAsset>[];
    for (final Object? entry in raw) {
      if (entry is! Map<String, dynamic>) {
        continue;
      }
      final String? name = entry['name'] as String?;
      final String? url = entry['browser_download_url'] as String?;
      if (name == null || url == null) {
        continue;
      }
      assets.add(
        ReleaseAsset(
          name: name,
          downloadUrl: url,
          sizeBytes: (entry['size'] as num?)?.toInt() ?? 0,
        ),
      );
    }
    return assets;
  }
}

/// Overridden in tests with a gateway built from a recording [HttpTextGet].
final Provider<GithubReleaseGateway> githubReleaseGatewayProvider =
    Provider<GithubReleaseGateway>((Ref ref) => const GithubReleaseGateway());
