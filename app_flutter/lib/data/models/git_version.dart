import 'package:flutter/foundation.dart';

/// The git every invocation runs, as `gbm_git_version_json` reports it --
/// core's `GitVersion` (src/core/git/GitExecutable.h) across the FFI.
@immutable
class GitVersion {
  const GitVersion(this.major, this.minor, this.patch);

  factory GitVersion.fromJson(Map<String, dynamic> json) => GitVersion(
    json['major'] as int,
    json['minor'] as int,
    json['patch'] as int,
  );

  final int major;
  final int minor;
  final int patch;

  bool isAtLeast(int major, int minor, int patch) {
    if (this.major != major) return this.major > major;
    if (this.minor != minor) return this.minor > minor;
    return this.patch >= patch;
  }

  /// Whether the clone dialog's 「一併 clone submodule」 starts checked
  /// (DLGS draws it `chk-on`): only from 2.50.1, the release that fixed
  /// CVE-2025-48384, a recursive clone of an untrusted repository writing
  /// outside it (ASK-3 (a), welcome-and-clone-spec.html W-D5). Backports
  /// (2.43.7, 2.44.4, … 2.49.1) are deliberately not recognised: a patched
  /// git only starts unchecked, and the user can still check it.
  bool get clonesSubmodulesByDefault => isAtLeast(2, 50, 1);

  @override
  bool operator ==(Object other) =>
      other is GitVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}
