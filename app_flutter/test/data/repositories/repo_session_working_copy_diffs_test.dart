import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

WorkingCopyDiffReply _reply(String path, {required bool staged}) =>
    WorkingCopyDiffReply(path: path, staged: staged, diff: ParsedDiff.empty);

void main() {
  group('workingCopyDiffKey', () {
    test('separates the two sides of one path', () {
      expect(
        workingCopyDiffKey('lib/main.dart', staged: true),
        isNot(workingCopyDiffKey('lib/main.dart', staged: false)),
        reason:
            'a key without the side would make the two replies overwrite '
            'each other -- which is exactly what the single lastDiff slot '
            'did, and why one pane was always empty',
      );
    });

    test('separates two paths on the same side', () {
      expect(
        workingCopyDiffKey('a.dart', staged: false),
        isNot(workingCopyDiffKey('b.dart', staged: false)),
      );
    });
  });

  group('RepoSessionState.workingCopyDiffs', () {
    test('holds both sides of a file at once', () {
      const RepoSessionState empty = RepoSessionState();

      final RepoSessionState both = empty.copyWith(
        workingCopyDiffs: <String, WorkingCopyDiffReply>{
          workingCopyDiffKey('lib/main.dart', staged: false): _reply(
            'lib/main.dart',
            staged: false,
          ),
          workingCopyDiffKey('lib/main.dart', staged: true): _reply(
            'lib/main.dart',
            staged: true,
          ),
        },
      );

      expect(both.workingCopyDiffs.length, 2);
      expect(both.workingCopyDiffs.values.map((r) => r.staged).toSet(), <bool>{
        false,
        true,
      });
    });

    test('starts empty rather than null, so a reader never has to ask '
        'whether anything has been fetched yet', () {
      expect(const RepoSessionState().workingCopyDiffs, isEmpty);
    });
  });
}
