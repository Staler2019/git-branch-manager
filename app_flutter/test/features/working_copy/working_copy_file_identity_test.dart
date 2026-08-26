import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/working_copy/working_copy_file_identity.dart';

/// The pairwise relation [logicalFileKey] has to agree with.
///
/// It lived in `lib/` until the C18 orphan sweep found it had no caller there:
/// the board keys its one selection set by [logicalFileKey] and never compares
/// two entries directly. It is kept here rather than deleted because it is the
/// *oracle* the key is checked against below -- an independently-written
/// statement of "the same file", so a bug in the key cannot hide by also being
/// in the thing that checks it. `oldPath` is empty for everything but a rename
/// or a copy, so for ordinary files this degenerates to plain path equality.
bool sameLogicalFile(WorkingCopyEntry a, WorkingCopyEntry b) =>
    a.path == b.path || a.oldPath == b.path || a.path == b.oldPath;

WorkingCopyEntry _entry({
  required String path,
  String oldPath = '',
  bool staged = false,
  bool hasUnstagedChange = false,
  bool untracked = false,
}) => WorkingCopyEntry(
  path: path,
  oldPath: oldPath,
  untracked: untracked,
  staged: staged,
  indexStatus: oldPath.isEmpty
      ? FileChangeKind.modified
      : FileChangeKind.renamed,
  hasUnstagedChange: hasUnstagedChange,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.none,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: '',
  similarity: 0,
  isSubmodule: false,
  isConflicted: false,
);

void main() {
  group('sameLogicalFile', () {
    test('plain paths compare by path', () {
      expect(
        sameLogicalFile(_entry(path: 'a.dart'), _entry(path: 'a.dart')),
        isTrue,
      );
      expect(
        sameLogicalFile(_entry(path: 'a.dart'), _entry(path: 'b.dart')),
        isFalse,
      );
    });

    test(
      'a staged rename matches the old name reappearing in the work tree',
      () {
        final WorkingCopyEntry staged = _entry(
          path: 'lib/new.dart',
          oldPath: 'lib/old.dart',
          staged: true,
        );
        final WorkingCopyEntry worktree = _entry(
          path: 'lib/old.dart',
          untracked: true,
          hasUnstagedChange: true,
        );

        expect(
          sameLogicalFile(staged, worktree),
          isTrue,
          reason: 'comparing path alone would call these two different files',
        );
        expect(
          sameLogicalFile(worktree, staged),
          isTrue,
          reason: 'the relation has to be symmetric or one column lights alone',
        );
      },
    );

    test('an unrelated file is not dragged in by a rename', () {
      final WorkingCopyEntry staged = _entry(
        path: 'lib/new.dart',
        oldPath: 'lib/old.dart',
        staged: true,
      );
      expect(sameLogicalFile(staged, _entry(path: 'lib/other.dart')), isFalse);
    });
  });

  group('logicalFileKey', () {
    test('is the path when there is no rename', () {
      expect(logicalFileKey(_entry(path: 'a.dart')), 'a.dart');
    });

    test('collapses a rename onto its old name, so both rows key the same', () {
      final WorkingCopyEntry staged = _entry(
        path: 'lib/new.dart',
        oldPath: 'lib/old.dart',
        staged: true,
      );
      final WorkingCopyEntry worktree = _entry(
        path: 'lib/old.dart',
        untracked: true,
      );

      expect(logicalFileKey(staged), logicalFileKey(worktree));
    });

    test(
      'agrees with sameLogicalFile on every pair a real status can hold',
      () {
        // A WorkingCopyStatus holds at most one entry per `path`, so the pairs
        // below are the whole space: unrelated files, a rename's two rows, and
        // an entry against itself.
        final List<WorkingCopyEntry> entries = <WorkingCopyEntry>[
          _entry(path: 'a.dart'),
          _entry(path: 'b.dart'),
          _entry(path: 'lib/new.dart', oldPath: 'lib/old.dart', staged: true),
          _entry(path: 'lib/old.dart', untracked: true),
        ];

        for (final WorkingCopyEntry a in entries) {
          for (final WorkingCopyEntry b in entries) {
            expect(
              logicalFileKey(a) == logicalFileKey(b),
              sameLogicalFile(a, b),
              reason:
                  'the key is what the selection set stores; if it disagrees '
                  'with the relation, "same file" means two different things '
                  'depending on which one the caller reached for '
                  '(${a.path} vs ${b.path})',
            );
          }
        }
      },
    );
  });
}
