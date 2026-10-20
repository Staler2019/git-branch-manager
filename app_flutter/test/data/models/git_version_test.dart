// The detected git's version, and the one rule the clone dialog asks of it:
// at or above 2.50.1, the release that fixed CVE-2025-48384, "clone
// submodules" starts checked (welcome-and-clone-spec.html W-D5). Backports
// are deliberately not recognised -- a patched 2.47.3 only starts unchecked.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_version.dart';

void main() {
  test('decodes gbm_git_version_json', () {
    final GitVersion v = GitVersion.fromJson(<String, dynamic>{
      'major': 2,
      'minor': 39,
      'patch': 5,
    });
    expect(v, const GitVersion(2, 39, 5));
    expect(v.toString(), '2.39.5');
  });

  test('isAtLeast compares major, then minor, then patch', () {
    const GitVersion v = GitVersion(2, 50, 1);
    expect(v.isAtLeast(2, 50, 1), isTrue);
    expect(v.isAtLeast(2, 50, 2), isFalse);
    expect(v.isAtLeast(2, 51, 0), isFalse);
    expect(v.isAtLeast(3, 0, 0), isFalse);
    expect(const GitVersion(2, 51, 0).isAtLeast(2, 50, 9), isTrue);
    expect(const GitVersion(3, 0, 0).isAtLeast(2, 99, 99), isTrue);
  });

  group('clonesSubmodulesByDefault', () {
    for (final (GitVersion v, bool expected) in <(GitVersion, bool)>[
      (const GitVersion(2, 50, 1), true),
      (const GitVersion(2, 51, 0), true),
      (const GitVersion(2, 50, 0), false),
      (const GitVersion(2, 47, 3), false), // backport, not recognised
      (const GitVersion(2, 30, 0), false),
    ]) {
      test('$v -> $expected', () {
        expect(v.clonesSubmodulesByDefault, expected);
      });
    }
  });
}
