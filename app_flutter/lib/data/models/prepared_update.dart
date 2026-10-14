import 'dart:io';

import 'package:flutter/foundation.dart';

/// What a verified download has been turned into, ready for the updater
/// script to apply once the app has exited.
///
/// Sealed because the two shapes are applied by entirely different means and
/// the updater must handle each explicitly: a directory is swapped into
/// place by the script itself, while an installer package is handed to the
/// operating system's installer, which does its own replacing and rollback.
/// A `switch` over this type is a compile error the day a third shape is
/// added and some caller has not learned it.
@immutable
sealed class PreparedUpdate {
  const PreparedUpdate();
}

/// An unpacked build shaped exactly like `UpdateInstaller.installTarget()`,
/// so the script's job is a plain directory-for-directory replacement.
final class PreparedDirectory extends PreparedUpdate {
  const PreparedDirectory(this.directory);

  final Directory directory;

  @override
  bool operator ==(Object other) =>
      other is PreparedDirectory && other.directory.path == directory.path;

  @override
  int get hashCode => directory.path.hashCode;

  @override
  String toString() => 'PreparedDirectory(${directory.path})';
}

/// A verified Windows Installer package, handed to `msiexec` unopened.
///
/// Windows Installer does the replacing -- and the rolling back when that
/// fails -- so there is nothing to unpack. [sha256] travels with it because
/// the updater script checks the package once more right before msiexec
/// reads it.
final class PreparedInstallerPackage extends PreparedUpdate {
  const PreparedInstallerPackage({required this.package, required this.sha256});

  final File package;

  /// Lower-case hex.
  final String sha256;

  @override
  bool operator ==(Object other) =>
      other is PreparedInstallerPackage &&
      other.package.path == package.path &&
      other.sha256 == sha256;

  @override
  int get hashCode => Object.hash(package.path, sha256);

  @override
  String toString() => 'PreparedInstallerPackage(${package.path}, $sha256)';
}
