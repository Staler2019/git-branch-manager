import 'dart:io';

import 'package:flutter/foundation.dart';

/// A release bundle on disk whose SHA-256 matched the release's manifest.
///
/// The digest travels with the file rather than being thrown away once the
/// comparison passed: the bundle then waits in a temp directory for as long
/// as the user leaves the update dialog at "ready to install", and the
/// installer checks it again right before using it.
@immutable
class DownloadedAsset {
  const DownloadedAsset({required this.file, required this.sha256});

  final File file;

  /// Lower-case hex, exactly as `parseChecksumManifest` normalises it.
  final String sha256;

  @override
  bool operator ==(Object other) =>
      other is DownloadedAsset &&
      other.file.path == file.path &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(file.path, sha256);

  @override
  String toString() => 'DownloadedAsset(${file.path}, $sha256)';
}
