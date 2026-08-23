import 'dart:ffi' show Abi;

import 'package:flutter/foundation.dart';

import 'app_version.dart';

/// One file attached to a GitHub release.
@immutable
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;

  @override
  bool operator ==(Object other) =>
      other is ReleaseAsset &&
      other.name == name &&
      other.downloadUrl == downloadUrl &&
      other.sizeBytes == sizeBytes;

  @override
  int get hashCode => Object.hash(name, downloadUrl, sizeBytes);

  @override
  String toString() => 'ReleaseAsset($name, $sizeBytes bytes)';
}

/// The newest published release, as `/releases/latest` describes it.
///
/// That endpoint excludes drafts and pre-releases on GitHub's side, which
/// is this app's entire pre-release policy — there is no client-side filter
/// to keep in step with it.
@immutable
class LatestRelease {
  const LatestRelease({
    required this.version,
    required this.tagName,
    required this.htmlUrl,
    required this.notes,
    required this.assets,
  });

  /// The parsed [tagName]. Never null: a release whose tag is not a version
  /// is rejected at parse time rather than carried as an unknown.
  final AppVersion version;

  /// The raw tag, kept because it is what the release page URL is built
  /// from and what the user sees on GitHub (`v0.30.0`, with the prefix).
  final String tagName;

  final String htmlUrl;

  /// The release body — Conventional-Commits changelog, rendered as plain
  /// text in the update dialog.
  final String notes;

  final List<ReleaseAsset> assets;
}

/// The file-name suffix release.yml gives the artifact for each ABI, or
/// null for an ABI this project publishes nothing for.
///
/// The tokens are **not** derivable from the ABI name: they come from
/// release.yml's build matrix, which spells the architecture differently on
/// each platform (`arm64` on macOS, `x64` on Windows, `x86_64` on Linux).
/// Deriving them would be a guess that happens to work for one platform.
///
/// Three entries, because release.yml has three matrix legs. An Intel Mac,
/// an ARM Linux box or an ARM Windows machine gets null and must be told
/// there is nothing to install — never handed another platform's bundle.
String? assetSuffixForAbi(Abi abi) {
  if (abi == Abi.macosArm64) {
    return '-macos-arm64.dmg';
  }
  if (abi == Abi.windowsX64) {
    return '-windows-x64.zip';
  }
  if (abi == Abi.linuxX64) {
    return '-linux-x86_64.tar.gz';
  }
  return null;
}

/// The asset [abi] should install, or null when this release publishes none
/// for it.
///
/// Matches against the names the release actually lists rather than
/// rebuilding the expected file name from a version, so a change to
/// release.yml's `name=` prefix does not silently stop finding the asset.
ReleaseAsset? selectAssetFor(List<ReleaseAsset> assets, Abi abi) {
  final String? suffix = assetSuffixForAbi(abi);
  if (suffix == null) {
    return null;
  }
  for (final ReleaseAsset asset in assets) {
    if (asset.name.endsWith(suffix)) {
      return asset;
    }
  }
  return null;
}

/// The name release.yml gives the checksum manifest it uploads alongside
/// the three bundles.
const String kChecksumManifestName = 'sha256sums.txt';

/// The release's `sha256sums.txt`, or null when it is absent.
///
/// Absence is a hard stop for the download path, not a reason to skip
/// verification: it is the only integrity check available, because the
/// published bundles are neither code-signed nor notarized (release.yml's
/// signing steps no-op when their secrets are absent, and they are).
ReleaseAsset? selectChecksumManifest(List<ReleaseAsset> assets) {
  for (final ReleaseAsset asset in assets) {
    if (asset.name == kChecksumManifestName) {
      return asset;
    }
  }
  return null;
}
