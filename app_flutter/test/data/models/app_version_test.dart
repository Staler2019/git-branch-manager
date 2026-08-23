import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_version.dart';

void main() {
  group('AppVersion.tryParse', () {
    test('parses a bare semver triple', () {
      expect(AppVersion.tryParse('0.30.0'), const AppVersion(0, 30, 0));
    });

    test('parses the v-prefixed form GitHub tags use', () {
      expect(AppVersion.tryParse('v0.30.0'), const AppVersion(0, 30, 0));
    });

    test('parses a pre-release suffix', () {
      expect(
        AppVersion.tryParse('1.0.0-rc.1'),
        const AppVersion(1, 0, 0, preRelease: 'rc.1'),
      );
    });

    test('tolerates surrounding whitespace', () {
      expect(AppVersion.tryParse('  v1.2.3  '), const AppVersion(1, 2, 3));
    });

    // The dev-build case: `String.fromEnvironment` with no --dart-define
    // yields '', and that has to read as "this build has no release
    // identity" rather than as version 0.0.0 -- see [isReleaseBuild].
    test('returns null for the empty string', () {
      expect(AppVersion.tryParse(''), isNull);
    });

    test('returns null for malformed input', () {
      for (final String raw in <String>[
        'not-a-version',
        '1',
        '1.2',
        '1.2.x',
        'v',
        '1.2.3.4',
        '-1.2.3',
        // `int.tryParse` accepts all four of these (measured: '+2' -> 2,
        // '0x10' -> 16, ' 2' -> 2, '2 ' -> 2), so rejecting them takes an
        // explicit digits-only check on top of it.
        '1.+2.3',
        '1.0x10.3',
        '1. 2.3',
        '1.2 .3',
      ]) {
        expect(AppVersion.tryParse(raw), isNull, reason: 'parsed "$raw"');
      }
    });
  });

  group('ordering', () {
    test('compares major, then minor, then patch', () {
      expect(const AppVersion(1, 0, 0) > const AppVersion(0, 99, 99), isTrue);
      expect(const AppVersion(0, 31, 0) > const AppVersion(0, 30, 99), isTrue);
      expect(const AppVersion(0, 30, 1) > const AppVersion(0, 30, 0), isTrue);
    });

    // The number that motivates this whole feature: the shipped app reports
    // 1.0.0 from pubspec while the newest tag is v0.30.0. A plain string or
    // a major-only compare would call the release "older" and never offer
    // the update.
    test('0.30.0 is older than 1.0.0 by number, not by string', () {
      expect(const AppVersion(0, 30, 0) < const AppVersion(1, 0, 0), isTrue);
      expect(
        const AppVersion(0, 9, 0) < const AppVersion(0, 30, 0),
        isTrue,
        reason: 'string ordering would put "0.9.0" after "0.30.0"',
      );
    });

    test('a pre-release sorts below its own release', () {
      expect(
        const AppVersion(1, 0, 0, preRelease: 'rc.1') <
            const AppVersion(1, 0, 0),
        isTrue,
      );
    });

    test('equal versions are neither newer nor older', () {
      expect(const AppVersion(1, 2, 3) > const AppVersion(1, 2, 3), isFalse);
      expect(const AppVersion(1, 2, 3) < const AppVersion(1, 2, 3), isFalse);
      expect(const AppVersion(1, 2, 3), const AppVersion(1, 2, 3));
    });

    test('sorts a mixed list oldest-first', () {
      final List<AppVersion> versions = <AppVersion>[
        const AppVersion(0, 30, 0),
        const AppVersion(1, 0, 0),
        const AppVersion(0, 9, 0),
        const AppVersion(1, 0, 0, preRelease: 'rc.1'),
      ]..sort();

      expect(versions.map((AppVersion v) => v.toString()).toList(), <String>[
        '0.9.0',
        '0.30.0',
        '1.0.0-rc.1',
        '1.0.0',
      ]);
    });
  });

  group('toString', () {
    test('renders without a v prefix', () {
      expect(const AppVersion(0, 30, 0).toString(), '0.30.0');
    });

    test('renders the pre-release suffix', () {
      expect(
        const AppVersion(1, 0, 0, preRelease: 'rc.1').toString(),
        '1.0.0-rc.1',
      );
    });
  });

  group('build identity', () {
    // These two assertions pin the *test-run* identity deliberately: the
    // suite runs with no --dart-define, which is exactly the shape a
    // `flutter run` developer build has. The invariant that matters is that
    // such a build is never treated as updatable.
    test('a build with no GBM_VERSION has no release identity', () {
      expect(currentBuildVersion, isNull);
      expect(isReleaseBuild, isFalse);
    });
  });
}
