import 'package:flutter/foundation.dart';

/// The version string the running build was compiled with, or `''` when it
/// was not compiled with one.
///
/// This is a **compile-time** constant, injected on every `flutter build`
/// by the `--dart-define=GBM_VERSION` flag in
/// `.github/workflows/release.yml`. It is deliberately not read from
/// `pubspec.yaml`: that
/// file's `version:` field is a stale `1.0.0+1` that no release has ever
/// updated, because release.yml derives the real version from Conventional
/// Commits and — before this feature — used it only to name the artifact
/// files. Reading pubspec would therefore report `1.0.0` on a build of
/// `v0.30.0` and make every comparison here meaningless.
///
/// A plain `flutter run`/`flutter test` passes no `--dart-define`, so this
/// is `''` there. That is the intended signal, not a defect: see
/// [isReleaseBuild].
const String kBuildVersionRaw = String.fromEnvironment('GBM_VERSION');

/// The running build's version, or null when it has no release identity —
/// a developer build, or a release built before the version-stamping flags
/// were added to release.yml.
///
/// Null must never be coerced to a number. `0.0.0` would make every release
/// look newer and turn a `flutter run` session into an update candidate;
/// treating it as the highest possible version would silently disable
/// updates for real users of an older build. Callers branch on
/// [isReleaseBuild] instead.
AppVersion? get currentBuildVersion => AppVersion.tryParse(kBuildVersionRaw);

/// Whether this build knows which release it is, and can therefore be
/// compared against — and replaced by — a published one.
///
/// The update flow is gated on this end to end: a developer build never
/// auto-checks and never self-installs, because replacing a `flutter run`
/// tree with a release bundle would destroy the checkout it was built from.
bool get isReleaseBuild => currentBuildVersion != null;

/// A semantic version, as this project's git tags carry it (`v0.30.0`).
///
/// Immutable value type (docs/ARCHITECTURE.md invariant 2), ordered by
/// [compareTo] so a list of them sorts oldest-first.
///
/// **Pre-release handling is a deliberate simplification.** Semver orders
/// pre-release identifiers field by field with numeric parts compared
/// numerically; this compares the whole suffix as one string. The only
/// consumer is the update check, which reads GitHub's `/releases/latest` —
/// an endpoint that excludes pre-releases and drafts outright — so a
/// suffix reaches this type only from a hand-typed value or a future
/// caller. The one rule that does matter is honoured exactly: a
/// pre-release sorts *below* the release sharing its `major.minor.patch`.
@immutable
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, {this.preRelease = ''});

  /// Parses `1.2.3`, `v1.2.3`, or either with a `-suffix`, tolerating
  /// surrounding whitespace.
  ///
  /// Returns null — never a fallback version — for anything else, including
  /// the empty string. Every caller has to decide what "no version" means
  /// for it, and none of the sensible answers is a number.
  static AppVersion? tryParse(String raw) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return null;
    }

    final String withoutPrefix = trimmed.startsWith('v')
        ? trimmed.substring(1)
        : trimmed;

    final int dashIndex = withoutPrefix.indexOf('-');
    final String core = dashIndex == -1
        ? withoutPrefix
        : withoutPrefix.substring(0, dashIndex);
    final String preRelease = dashIndex == -1
        ? ''
        : withoutPrefix.substring(dashIndex + 1);

    final List<String> parts = core.split('.');
    if (parts.length != 3) {
      return null;
    }

    final List<int> numbers = <int>[];
    for (final String part in parts) {
      // `int.tryParse` accepts a leading '-', which would let "-1.2.3" and
      // "1.-2.3" through as negative components.
      if (part.isEmpty || !part.split('').every(_isAsciiDigit)) {
        return null;
      }
      final int? value = int.tryParse(part);
      if (value == null) {
        return null;
      }
      numbers.add(value);
    }

    if (dashIndex != -1 && preRelease.isEmpty) {
      return null;
    }

    return AppVersion(
      numbers[0],
      numbers[1],
      numbers[2],
      preRelease: preRelease,
    );
  }

  static bool _isAsciiDigit(String char) {
    final int code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }

  final int major;
  final int minor;
  final int patch;

  /// The `-suffix` part, or `''` for a plain release.
  final String preRelease;

  /// Whether this version is a pre-release of [major].[minor].[patch].
  bool get isPreRelease => preRelease.isNotEmpty;

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) {
      return major.compareTo(other.major);
    }
    if (minor != other.minor) {
      return minor.compareTo(other.minor);
    }
    if (patch != other.patch) {
      return patch.compareTo(other.patch);
    }
    // Same core version: a pre-release is older than the release itself.
    if (isPreRelease != other.isPreRelease) {
      return isPreRelease ? -1 : 1;
    }
    return preRelease.compareTo(other.preRelease);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;

  bool operator <(AppVersion other) => compareTo(other) < 0;

  bool operator >=(AppVersion other) => compareTo(other) >= 0;

  bool operator <=(AppVersion other) => compareTo(other) <= 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch &&
      other.preRelease == preRelease;

  @override
  int get hashCode => Object.hash(major, minor, patch, preRelease);

  /// Renders without the `v` prefix — the form spoken in UI copy. Callers
  /// that need the tag form add the prefix themselves.
  @override
  String toString() => isPreRelease
      ? '$major.$minor.$patch-$preRelease'
      : '$major.$minor.$patch';
}
