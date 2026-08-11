import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_conflict_file.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/conflict_resolution/conflict_resolve_logic.dart';

// assembleConflictResolution mirrors selected cases from
// tests/unit/ConflictMarkerParserTest.cpp's Assemble* tests (skipping the
// Custom-choice cases, which this port deliberately does not support -- see
// conflict_resolve_logic.dart's doc comment); ConflictBatch mirrors selected
// cases from tests/unit/ConflictBatchTest.cpp.

ConflictSegment textSegment(String text) =>
    ConflictSegment(kind: ConflictSegmentKind.text, lines: <String>[text], ours: const [], theirs: const [], base: const [], hasBase: false);

ConflictSegment regionSegment({required List<String> ours, required List<String> theirs}) => ConflictSegment(
  kind: ConflictSegmentKind.region,
  lines: const <String>[],
  ours: ours,
  theirs: theirs,
  base: const <String>[],
  hasBase: false,
);

WorkingCopyEntry conflictedEntry(String path) => WorkingCopyEntry(
  path: path,
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: false,
  worktreeStatus: FileChangeKind.modified,
  conflict: ConflictKind.bothModified,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: '',
  similarity: 0,
  isSubmodule: false,
  isConflicted: true,
);

void main() {
  group('assembleConflictResolution', () {
    test('assembles the chosen side without any marker text', () {
      final ParsedConflictFile parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          textSegment('before line 1\n'),
          regionSegment(ours: <String>['ours line 1\n', 'ours line 2\n'], theirs: <String>['theirs line 1\n']),
          textSegment('after line 1\n'),
        ],
        regionCount: 1,
        wellFormed: true,
      );

      final String? ours = assembleConflictResolution(parsed, <ConflictRegionChoice>[ConflictRegionChoice.ours]);
      expect(ours, 'before line 1\nours line 1\nours line 2\nafter line 1\n');
      expect(ours!.contains('<<<<<<<'), isFalse);

      final String? theirs = assembleConflictResolution(parsed, <ConflictRegionChoice>[ConflictRegionChoice.theirs]);
      expect(theirs, 'before line 1\ntheirs line 1\nafter line 1\n');
    });

    test('never emits a marker line across mixed choices', () {
      final ParsedConflictFile parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          regionSegment(ours: <String>['a-ours\n'], theirs: <String>['a-theirs\n']),
          textSegment('between\n'),
          regionSegment(ours: <String>['b-ours\n'], theirs: <String>['b-theirs\n']),
        ],
        regionCount: 2,
        wellFormed: true,
      );

      final String? result = assembleConflictResolution(parsed, <ConflictRegionChoice>[
        ConflictRegionChoice.ours,
        ConflictRegionChoice.theirs,
      ]);
      expect(result, 'a-ours\nbetween\nb-theirs\n');
      for (final marker in <String>['<<<<<<<', '=======', '>>>>>>>', '|||||||']) {
        expect(result!.contains(marker), isFalse, reason: 'leaked marker: $marker');
      }
    });

    test('returns null when any region is unresolved', () {
      final ParsedConflictFile parsed = ParsedConflictFile(
        segments: <ConflictSegment>[regionSegment(ours: <String>['ours\n'], theirs: <String>['theirs\n'])],
        regionCount: 1,
        wellFormed: true,
      );

      expect(assembleConflictResolution(parsed, <ConflictRegionChoice>[ConflictRegionChoice.unresolved]), isNull);
    });

    test('returns null when resolution count does not match region count', () {
      final ParsedConflictFile parsed = ParsedConflictFile(
        segments: <ConflictSegment>[regionSegment(ours: <String>['ours\n'], theirs: <String>['theirs\n'])],
        regionCount: 1,
        wellFormed: true,
      );

      expect(assembleConflictResolution(parsed, const <ConflictRegionChoice>[]), isNull);
      expect(
        assembleConflictResolution(parsed, <ConflictRegionChoice>[ConflictRegionChoice.ours, ConflictRegionChoice.ours]),
        isNull,
      );
    });
  });

  group('ConflictBatch', () {
    test('first merge records every conflicted path as unresolved', () {
      final ConflictBatch batch = ConflictBatch();
      batch.merge(<WorkingCopyEntry>[conflictedEntry('a.cpp'), conflictedEntry('b.h')]);

      expect(batch.entries.length, 2);
      expect(batch.entries[0].path, 'a.cpp');
      expect(batch.entries[0].state, ConflictFileState.unresolved);
      expect(batch.entries[1].path, 'b.h');
      expect(batch.resolvedCount, 0);
      expect(batch.allResolved, isFalse);
    });

    test('a new conflict appearing midway is appended', () {
      final ConflictBatch batch = ConflictBatch();
      batch.merge(<WorkingCopyEntry>[conflictedEntry('a.cpp')]);
      batch.merge(<WorkingCopyEntry>[conflictedEntry('a.cpp'), conflictedEntry('c.txt')]);

      expect(batch.entries.length, 2);
      expect(batch.entries[0].path, 'a.cpp');
      expect(batch.entries[0].state, ConflictFileState.unresolved);
      expect(batch.entries[1].path, 'c.txt');
      expect(batch.entries[1].state, ConflictFileState.unresolved);
    });

    test('a path missing from a later scan becomes resolved', () {
      final ConflictBatch batch = ConflictBatch();
      batch.merge(<WorkingCopyEntry>[conflictedEntry('a.cpp'), conflictedEntry('b.h')]);
      batch.merge(<WorkingCopyEntry>[conflictedEntry('a.cpp')]);

      expect(batch.entries.length, 2);
      expect(batch.entries[0].state, ConflictFileState.unresolved);
      expect(batch.entries[1].path, 'b.h');
      expect(batch.entries[1].state, ConflictFileState.resolved);
      expect(batch.resolvedCount, 1);
      expect(batch.allResolved, isFalse);
    });

    test('allResolved is true only when every tracked path is resolved', () {
      final ConflictBatch batch = ConflictBatch();
      batch.merge(<WorkingCopyEntry>[conflictedEntry('a.cpp'), conflictedEntry('b.h')]);

      batch.merge(<WorkingCopyEntry>[conflictedEntry('a.cpp')]);
      expect(batch.allResolved, isFalse);

      batch.merge(const <WorkingCopyEntry>[]);
      expect(batch.allResolved, isTrue);
      expect(batch.resolvedCount, 2);
    });

    test('entry order is stable across resolution and new arrivals', () {
      final ConflictBatch batch = ConflictBatch();
      batch.merge(<WorkingCopyEntry>[conflictedEntry('a.cpp'), conflictedEntry('b.h')]);
      // Resolve a.cpp (drops out), c.txt shows up mid-rebase.
      batch.merge(<WorkingCopyEntry>[conflictedEntry('b.h'), conflictedEntry('c.txt')]);

      expect(batch.entries.length, 3);
      expect(batch.entries[0].path, 'a.cpp');
      expect(batch.entries[0].state, ConflictFileState.resolved);
      expect(batch.entries[1].path, 'b.h');
      expect(batch.entries[1].state, ConflictFileState.unresolved);
      expect(batch.entries[2].path, 'c.txt');
      expect(batch.entries[2].state, ConflictFileState.unresolved);
    });

    test('a path that becomes conflicted again flips back to unresolved', () {
      final ConflictBatch batch = ConflictBatch();
      batch.merge(<WorkingCopyEntry>[conflictedEntry('a.cpp')]);
      batch.merge(const <WorkingCopyEntry>[]);
      expect(batch.entries[0].state, ConflictFileState.resolved);

      batch.merge(<WorkingCopyEntry>[conflictedEntry('a.cpp')]);
      expect(batch.entries[0].state, ConflictFileState.unresolved);
    });
  });
}
