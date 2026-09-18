import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';

Map<String, dynamic> _rawEntry({
  bool untracked = false,
  int? untrackedSize,
  int? untrackedMtimeTicks,
}) {
  return <String, dynamic>{
    'path': 'fresh.txt',
    'oldPath': '',
    'untracked': untracked,
    'staged': false,
    'indexStatus': 0,
    'hasUnstagedChange': true,
    'worktreeStatus': 0,
    'unstagedAdded': 3,
    'unstagedRemoved': 0,
    'stagedAdded': 0,
    'stagedRemoved': 0,
    'conflict': 0,
    'ancestorBlob': '',
    'oursBlob': '',
    'theirsBlob': '',
    'similarity': 0,
    'isSubmodule': false,
    'isConflicted': false,
    'untrackedSize': ?untrackedSize,
    'untrackedMtimeTicks': ?untrackedMtimeTicks,
  };
}

void main() {
  group('WorkingCopyEntry.fromJson untrackedSize/untrackedMtimeTicks', () {
    test('reads both fields when present and non-zero', () {
      final entry = WorkingCopyEntry.fromJson(
        _rawEntry(
          untracked: true,
          untrackedSize: 9,
          untrackedMtimeTicks: 1234567890123456789,
        ),
      );

      expect(entry.untrackedSize, 9);
      expect(entry.untrackedMtimeTicks, 1234567890123456789);
    });

    // C2a's fields must not be `required` -- a raw-JSON fixture built before
    // this field existed (or a JSON payload from an older running app
    // during a rolling deploy, though this app has no such thing today) is
    // exactly [CULT-stage-by-file]'s "invisible to a grep for the
    // constructor" case, and a missing key must not become `null as int`.
    test('defaults both fields to 0 when the keys are absent', () {
      final entry = WorkingCopyEntry.fromJson(_rawEntry(untracked: true));

      expect(entry.untrackedSize, 0);
      expect(entry.untrackedMtimeTicks, 0);
    });

    test('stays 0/0 for a tracked file, matching the C++ "not measured" '
        'convention', () {
      final entry = WorkingCopyEntry.fromJson(
        _rawEntry(untracked: false, untrackedSize: 0, untrackedMtimeTicks: 0),
      );

      expect(entry.untrackedSize, 0);
      expect(entry.untrackedMtimeTicks, 0);
    });
  });
}
