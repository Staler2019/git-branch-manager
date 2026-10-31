// Slice S3: one `2 file` column's sync units and where each sits on the
// index ruler both columns share. A card or gap is one unit; a fill run is
// one unit per row, or a full-file view would be one segment end to end.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_block_order.dart';
import 'package:gbm_flutter/features/diff/diff_full_file_fill.dart';
import 'package:gbm_flutter/features/diff/diff_scopes.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_segments.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_spans.dart';

/// `.` both sides, `+` new only, `-` old only, numbered from [start].
DiffHunk _hunk(String sketch, {required int start}) {
  int oldLine = start;
  int newLine = start;
  return DiffHunk(
    oldStart: start,
    oldCount: sketch.replaceAll('+', '').length,
    newStart: start,
    newCount: sketch.replaceAll('-', '').length,
    heading: '',
    lines: <DiffLine>[
      for (final String c in sketch.split(''))
        DiffLine(
          kind: switch (c) {
            '+' => DiffLineKind.added,
            '-' => DiffLineKind.removed,
            _ => DiffLineKind.context,
          },
          oldLine: c == '+' ? 0 : oldLine++,
          newLine: c == '-' ? 0 : newLine++,
          text: c,
        ),
    ],
  );
}

DiffFile _file(List<DiffHunk> hunks) => DiffFile(
  oldPath: 'a',
  newPath: 'a',
  kind: FileChangeKind.modified,
  oldMode: '',
  newMode: '',
  oldBlob: '',
  newBlob: '',
  binary: false,
  similarity: 0,
  addedLines: 0,
  removedLines: 0,
  displayPath: 'a',
  hunks: hunks,
);

List<DiffBlock> _blocks(DiffSide side, {List<DiffFillRow>? fill}) =>
    orderedDiffBlocks(
      <DiffSide>[side],
      <Map<int, List<DiffScope>>>[
        splitDiffFileIntoScopes(side.file!, staged: side.staged),
      ],
      fill: fill,
    );

List<DiffFillRow> _fill(List<int> lines) => <DiffFillRow>[
  for (final int l in lines)
    (
      sourceIndex: 0,
      indexLine: l,
      line: DiffLine(
        kind: DiffLineKind.context,
        oldLine: l,
        newLine: l,
        text: 'f$l',
      ),
    ),
];

SyncSpan<IndexPosition> _span(int lo, int loOff, int hi, int hiOff) =>
    (lo: (line: lo, offset: loOff), hi: (line: hi, offset: hiOff));

void main() {
  test('unstaged: a card or gap spans its first to last row on the index '
      '(old) side, an insertion sitting after its line', () {
    final DiffSide side = (
      file: _file(<DiffHunk>[_hunk('...+...', start: 5)]),
      staged: false,
    );
    expect(
      syncUnitSpans(_blocks(side), <DiffSide>[side]),
      <SyncSpan<IndexPosition>>[
        _span(5, 0, 7, 0),
        _span(7, 1, 7, 1),
        _span(8, 0, 10, 0),
      ],
    );
  });

  test('staged: the same sketch reads the new side, where the addition is '
      'an index line of its own', () {
    final DiffSide side = (
      file: _file(<DiffHunk>[_hunk('...+...', start: 5)]),
      staged: true,
    );
    expect(
      syncUnitSpans(_blocks(side), <DiffSide>[side]),
      <SyncSpan<IndexPosition>>[
        _span(5, 0, 7, 0),
        _span(8, 0, 8, 0),
        _span(9, 0, 11, 0),
      ],
    );
  });

  test('a fill run is one unit per row', () {
    final DiffSide side = (
      file: _file(<DiffHunk>[_hunk('.+.', start: 3)]),
      staged: false,
    );
    final List<DiffBlock> blocks = _blocks(
      side,
      fill: _fill(<int>[1, 2, 5, 6]),
    );
    expect(
      blocks.where((DiffBlock b) => b.segment is DiffFillSegment).length,
      2,
      reason: 'the fixture has two joined runs',
    );
    expect(syncUnitSpans(blocks, <DiffSide>[side]), <SyncSpan<IndexPosition>>[
      _span(1, 0, 1, 0),
      _span(2, 0, 2, 0),
      _span(3, 0, 3, 0),
      _span(3, 1, 3, 1),
      _span(4, 0, 4, 0),
      _span(5, 0, 5, 0),
      _span(6, 0, 6, 0),
    ]);
  });
}
