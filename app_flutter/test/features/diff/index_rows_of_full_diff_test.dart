// A 2 file column whose own direction has no change draws the index: the
// file both of that direction's ends hold. The other side's full diff
// already carries it -- a staged diff (HEAD -> index) on its new side, an
// unstaged diff (index -> work tree) on its old side (plan: Slice E, E1).
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_full_file_fill.dart';

import '../../support/full_file_diffs.dart';

/// Each row as (index line, kind, old line, new line, text, source).
List<(int, DiffLineKind, int, int, String, int)> _shape(
  List<DiffFillRow> rows,
) => <(int, DiffLineKind, int, int, String, int)>[
  for (final DiffFillRow r in rows)
    (
      r.indexLine,
      r.line.kind,
      r.line.oldLine,
      r.line.newLine,
      r.line.text,
      r.sourceIndex,
    ),
];

/// A whole new file of [lines], staged: one hunk of added rows, ending in
/// git's no-newline marker.
DiffFile _newFile(List<String> lines, {bool binary = false}) => DiffFile(
  oldPath: 'n.dart',
  newPath: 'n.dart',
  kind: FileChangeKind.added,
  oldMode: '',
  newMode: '100644',
  oldBlob: '',
  newBlob: '',
  binary: binary,
  similarity: 0,
  addedLines: lines.length,
  removedLines: 0,
  displayPath: 'n.dart',
  // Hunks kept on a binary one too, so only the flag can empty it.
  hunks: <DiffHunk>[
    DiffHunk(
      oldStart: 0,
      oldCount: 0,
      newStart: 1,
      newCount: lines.length,
      heading: '',
      lines: <DiffLine>[
        for (int i = 0; i < lines.length; i++)
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: 0,
            newLine: i + 1,
            text: lines[i],
          ),
        const DiffLine(
          kind: DiffLineKind.noNewlineMarker,
          oldLine: 0,
          newLine: 0,
          text: r'\ No newline at end of file',
        ),
      ],
    ),
  ],
);

void main() {
  const DiffLineKind ctx = DiffLineKind.context;

  test('a staged diff gives the index from its new side: context and added '
      'rows, never removed ones', () {
    final DiffFile staged = replacementsDiff(6, <int>{
      2,
      5,
    }, context: kAllContext);
    expect(_shape(indexRowsOfFullDiff(staged, staged: true)), <Object>[
      (1, ctx, 1, 1, 'L1', 0),
      (2, ctx, 2, 2, 'edited L2', 0),
      (3, ctx, 3, 3, 'L3', 0),
      (4, ctx, 4, 4, 'L4', 0),
      (5, ctx, 5, 5, 'edited L5', 0),
      (6, ctx, 6, 6, 'L6', 0),
    ]);
  });

  test('an unstaged diff gives the index from its old side: context and '
      'removed rows, never added ones', () {
    final DiffFile unstaged = replacementsDiff(6, <int>{
      2,
      5,
    }, context: kAllContext);
    expect(_shape(indexRowsOfFullDiff(unstaged, staged: false)), <Object>[
      (1, ctx, 1, 1, 'L1', 0),
      (2, ctx, 2, 2, 'L2', 0),
      (3, ctx, 3, 3, 'L3', 0),
      (4, ctx, 4, 4, 'L4', 0),
      (5, ctx, 5, 5, 'L5', 0),
      (6, ctx, 6, 6, 'L6', 0),
    ]);
  });

  test('a new file staged whole is every line, and the no-newline marker is '
      'no row', () {
    expect(
      _shape(
        indexRowsOfFullDiff(_newFile(<String>['a', 'b', 'c']), staged: true),
      ),
      <Object>[
        (1, ctx, 1, 1, 'a', 0),
        (2, ctx, 2, 2, 'b', 0),
        (3, ctx, 3, 3, 'c', 0),
      ],
    );
  });

  test('a binary diff gives no rows', () {
    expect(
      indexRowsOfFullDiff(_newFile(<String>['a'], binary: true), staged: true),
      isEmpty,
    );
  });
}
