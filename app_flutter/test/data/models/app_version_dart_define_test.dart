import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_version.dart';

/// Verifies the one link in the version chain that no other test can see:
/// `--dart-define=GBM_VERSION` -> `String.fromEnvironment` ->
/// [currentBuildVersion].
///
/// It is the half of `.github/workflows/release.yml`'s version stamping that
/// is checkable locally. The other half — that release.yml actually passes
/// the flag — cannot be proved until the next tag fires, so run this with
/// the *same* flag release.yml uses and the chain is verified end to end
/// except for the workflow file's own text:
///
/// ```sh
/// flutter test --dart-define=GBM_VERSION=9.9.9 \
///   test/data/models/app_version_dart_define_test.dart
/// ```
///
/// Skipped in the ordinary suite rather than asserting the null case — that
/// one is already pinned by `app_version_test.dart`'s "build identity"
/// group, and a test that passes under both conditions would prove nothing.
const String _injected = String.fromEnvironment('GBM_VERSION');

void main() {
  test(
    'a --dart-define reaches currentBuildVersion',
    () {
      expect(currentBuildVersion, isNotNull);
      expect(currentBuildVersion.toString(), _injected);
      expect(isReleaseBuild, isTrue);
    },
    skip: _injected.isEmpty
        ? 'run with --dart-define=GBM_VERSION=<version> (see the file header)'
        : null,
  );
}
