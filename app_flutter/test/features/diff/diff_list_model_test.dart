import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_block_order.dart';
import 'package:gbm_flutter/features/diff/diff_full_file_fill.dart';
import 'package:gbm_flutter/features/diff/diff_list_model.dart';
import 'package:gbm_flutter/features/diff/diff_row_keys.dart';
import 'package:gbm_flutter/features/diff/diff_scopes.dart';

/// A hunk from a sketch with real line numbers: `.` advances both sides,
/// `-` the old side only, `+` the new side only. Row `i`'s text is [text]
/// when given, else `line i`.
DiffHunk _numbered(String sketch, {required int start, String? text}) {
  int oldLine = start;
  int newLine = start;
  final List<DiffLine> lines = <DiffLine>[];
  for (int i = 0; i < sketch.length; i++) {
    final String c = sketch[i];
    lines.add(
      DiffLine(
        kind: switch (c) {
          '+' => DiffLineKind.added,
          '-' => DiffLineKind.removed,
          _ => DiffLineKind.context,
        },
        oldLine: c == '+' ? 0 : oldLine++,
        newLine: c == '-' ? 0 : newLine++,
        text: text ?? 'line $i',
      ),
    );
  }
  return DiffHunk(
    oldStart: start,
    oldCount: oldLine - start,
    newStart: start,
    newCount: newLine - start,
    heading: '',
    lines: lines,
  );
}

DiffFile _file(List<DiffHunk> hunks) => DiffFile(
  oldPath: 'a.dart',
  newPath: 'a.dart',
  kind: FileChangeKind.modified,
  oldMode: '',
  newMode: '',
  oldBlob: '',
  newBlob: '',
  binary: false,
  similarity: 0,
  addedLines: 0,
  removedLines: 0,
  displayPath: 'a.dart',
  hunks: hunks,
);

List<Map<int, List<DiffScope>>> _scopes(List<DiffSide> sides) {
  final List<IndexBarriers> barriers = DiffBarrierMemo().barriersFor(sides);
  return <Map<int, List<DiffScope>>>[
    for (int i = 0; i < sides.length; i++)
      splitDiffFileIntoScopes(
        sides[i].file!,
        staged: sides[i].staged,
        barriers: barriers[i],
      ),
  ];
}

List<DiffFillRow> _fill(Iterable<int> lines, {int sourceIndex = 0}) =>
    <DiffFillRow>[
      for (final int l in lines)
        (
          sourceIndex: sourceIndex,
          indexLine: l,
          line: DiffLine(
            kind: DiffLineKind.context,
            oldLine: l,
            newLine: l,
            text: 'fill $l',
          ),
        ),
    ];

/// Distinct numbers, so a sum that picks the wrong term cannot land on the
/// right total by accident.
const DiffListMetrics _metrics = (
  rowExtent: 10,
  headingExtent: 7,
  cardChromeExtent: 30,
  gapChromeExtent: 3,
  charsPerLine: 0,
);

String _shape(DiffListItem item) => switch (item) {
  DiffLeadingItem(:final int index) => 'leading $index',
  DiffHeadingItem(:final DiffBlock block) =>
    'heading ${block.sourceIndex}:${block.hunkIndex}',
  DiffBlockItem(:final DiffBlock block) => switch (block.segment) {
    DiffScopeSegment() =>
      'card ${block.sourceIndex}:${block.hunkIndex}:'
          '${block.segment.lineIndices.join(',')}',
    DiffGapSegment() =>
      'gap ${block.sourceIndex}:${block.hunkIndex}:'
          '${block.segment.lineIndices.join(',')}',
    DiffFillSegment() => 'fill-as-block',
  },
  DiffFillItem(:final DiffFillRow row) =>
    'fill ${row.sourceIndex}:${row.indexLine}',
  DiffSpacerItem(:final int segment) => 'spacer $segment',
};

/// The painted row keys of [blocks], walked independently of the model:
/// what `ScopedDiffView` keyed its rows by before the model existed.
List<String> _walk(List<DiffBlock> blocks) => <String>[
  for (final DiffBlock block in blocks)
    if (block.segment case DiffFillSegment(:final List<DiffFillRow> rows))
      for (final DiffFillRow row in rows)
        selectionFillRowKey(row.sourceIndex, row.indexLine)
    else
      for (final int lineIndex in block.segment.lineIndices)
        selectionRowKey(block.sourceIndex, block.hunkIndex, lineIndex),
];

void _expectConsistent(DiffListModel model) {
  final int n = model.items.length;
  double sum = 0;
  for (int i = 0; i < n; i++) {
    expect(model.offsetOf(i), sum, reason: 'offset of item $i');
    sum += model.extentOf(i);
  }
  expect(model.offsetOf(n), sum);
  expect(model.totalExtent, sum);
  for (int r = 0; r < model.rowKeys.length; r++) {
    expect(model.rowIndexOf(model.rowKeys[r]), r);
    final int item = model.itemOfRow(r);
    expect(model.firstRowOf(item) <= r, isTrue, reason: 'row $r');
    expect(r < model.firstRowOf(item) + model.rowCountOf(item), isTrue);
  }
}

void main() {
  group('DiffListModel -- items and rows', () {
    test('excerpt mode: leading items, then a heading per hunk, then its '
        'gaps and cards, one item each', () {
      final DiffFile file = _file(<DiffHunk>[
        _numbered('...+...', start: 5),
        _numbered('..-.', start: 30),
      ]);
      final List<DiffSide> sides = <DiffSide>[(file: file, staged: false)];
      final List<DiffBlock> blocks = orderedDiffBlocks(sides, _scopes(sides));

      final DiffListModel model = DiffListModel.fromBlocks(
        blocks,
        sides: sides,
        headings: true,
        metrics: _metrics,
        leadingExtents: const <double>[22, 18],
      );

      expect(model.items.map(_shape).toList(), <String>[
        'leading 0',
        'leading 1',
        'heading 0:0',
        'gap 0:0:0,1,2',
        'card 0:0:3',
        'gap 0:0:4,5,6',
        'heading 0:1',
        'gap 0:1:0,1',
        'card 0:1:2',
        'gap 0:1:3',
      ]);
      expect(model.rowKeys, _walk(blocks));
      expect(model.cardItems, <int>[4, 8]);
      expect(model.firstRowOf(4), 3);
      expect(model.rowCountOf(4), 1);
      expect(model.rowCountOf(2), 0, reason: 'a heading draws no row');
      expect(model.rowCountOf(0), 0, reason: 'a leading item draws no row');
      _expectConsistent(model);
    });

    test('full-file mode: no headings, and each fill row is its own item', () {
      final DiffFile file = _file(<DiffHunk>[_numbered('.+.', start: 3)]);
      final List<DiffSide> sides = <DiffSide>[(file: file, staged: false)];
      final List<DiffBlock> blocks = orderedDiffBlocks(
        sides,
        _scopes(sides),
        fill: <DiffFillRow>[
          ..._fill(<int>[1, 2]),
          ..._fill(<int>[5, 6]),
        ],
      );

      final DiffListModel model = DiffListModel.fromBlocks(
        blocks,
        sides: sides,
        headings: false,
        metrics: _metrics,
      );

      expect(model.items.map(_shape).toList(), <String>[
        'fill 0:1',
        'fill 0:2',
        'gap 0:0:0',
        'card 0:0:1',
        'gap 0:0:2',
        'fill 0:5',
        'fill 0:6',
      ]);
      expect(model.rowKeys, <String>[
        'f:0:1',
        'f:0:2',
        '0:0:0',
        '0:0:1',
        '0:0:2',
        'f:0:5',
        'f:0:6',
      ]);
      expect(model.cardItems, <int>[3]);
      // Which segment of its run's dashed rule each fill row draws; 0 for
      // anything that is not a fill row.
      expect(
        <int>[
          for (int i = 0; i < model.items.length; i++) model.fillRunOffsetOf(i),
        ],
        <int>[0, 1, 0, 0, 0, 0, 1],
      );
      _expectConsistent(model);
    });

    test('a merged list heads every change of source or hunk, as the view '
        'does', () {
      // Unstaged inserts after index 10; staged adds index 8 and 12. The
      // painted order interleaves the two sources, so a heading per change
      // of (source, hunk) is more headings than either side alone.
      final DiffFile unstaged = _file(<DiffHunk>[
        _numbered('...++...', start: 8),
      ]);
      final DiffFile staged = _file(<DiffHunk>[_numbered('+...+', start: 8)]);
      final List<DiffSide> sides = <DiffSide>[
        (file: unstaged, staged: false),
        (file: staged, staged: true),
      ];
      final List<DiffBlock> blocks = orderedDiffBlocks(sides, _scopes(sides));

      final DiffListModel model = DiffListModel.fromBlocks(
        blocks,
        sides: sides,
        headings: true,
        metrics: _metrics,
      );

      int expected = 0;
      (int, int)? last;
      for (final DiffBlock b in blocks) {
        if (last != (b.sourceIndex, b.hunkIndex)) expected++;
        last = (b.sourceIndex, b.hunkIndex);
      }
      expect(model.items.whereType<DiffHeadingItem>().length, expected);
      expect(expected > 2, isTrue, reason: 'the fixture must interleave');
      expect(model.rowKeys, _walk(blocks));
      _expectConsistent(model);
    });

    test('changedRows are exactly the card rows that are not context, in '
        'painted order', () {
      final DiffFile file = _file(<DiffHunk>[_numbered('..-+..+.', start: 1)]);
      final List<DiffSide> sides = <DiffSide>[(file: file, staged: false)];
      final List<DiffBlock> blocks = orderedDiffBlocks(sides, _scopes(sides));

      final DiffListModel model = DiffListModel.fromBlocks(
        blocks,
        sides: sides,
        headings: true,
        metrics: _metrics,
      );

      expect(
        model.changedRows.map((int r) => model.rowKeys[r]).toList(),
        <String>['0:0:2', '0:0:3', '0:0:6'],
      );
    });
  });

  group('DiffListModel -- extents and offsets', () {
    test('a card is its chrome plus its rows, a gap likewise, a heading and '
        'a fill row their own extent', () {
      final DiffFile file = _file(<DiffHunk>[_numbered('..+.', start: 4)]);
      final List<DiffSide> sides = <DiffSide>[(file: file, staged: false)];

      final DiffListModel excerpt = DiffListModel.fromBlocks(
        orderedDiffBlocks(sides, _scopes(sides)),
        sides: sides,
        headings: true,
        metrics: _metrics,
        leadingExtents: const <double>[22],
      );
      expect(excerpt.items.map(_shape).toList(), <String>[
        'leading 0',
        'heading 0:0',
        'gap 0:0:0,1',
        'card 0:0:2',
        'gap 0:0:3',
      ]);
      expect(excerpt.extentOf(0), 22);
      expect(excerpt.extentOf(1), 7);
      expect(excerpt.extentOf(2), 3 + 2 * 10);
      expect(excerpt.extentOf(3), 30 + 10);

      final DiffFile gapped = _file(<DiffHunk>[_numbered('+....+', start: 1)]);
      final List<DiffSide> gappedSides = <DiffSide>[
        (file: gapped, staged: false),
      ];
      final DiffListModel withGap = DiffListModel.fromBlocks(
        orderedDiffBlocks(
          gappedSides,
          _scopes(gappedSides),
          fill: _fill(<int>[9]),
        ),
        sides: gappedSides,
        headings: false,
        metrics: _metrics,
      );
      expect(withGap.items.map(_shape).toList(), <String>[
        'card 0:0:0',
        'gap 0:0:1,2,3,4',
        'card 0:0:5',
        'fill 0:9',
      ]);
      expect(withGap.extentOf(1), 3 + 4 * 10);
      expect(withGap.extentOf(3), 10);
    });

    test('soft wrap estimates a row as its characters over the characters '
        'a line holds, rounded up, never less than one line', () {
      DiffListModel modelFor(String text, int charsPerLine) {
        final DiffFile file = _file(<DiffHunk>[
          _numbered('+', start: 1, text: text),
        ]);
        final List<DiffSide> sides = <DiffSide>[(file: file, staged: false)];
        return DiffListModel.fromBlocks(
          orderedDiffBlocks(sides, _scopes(sides)),
          sides: sides,
          headings: false,
          metrics: (
            rowExtent: 10,
            headingExtent: 7,
            cardChromeExtent: 30,
            gapChromeExtent: 3,
            charsPerLine: charsPerLine,
          ),
        );
      }

      expect(modelFor('x' * 25, 10).extentOf(0), 30 + 3 * 10);
      expect(modelFor('x' * 20, 10).extentOf(0), 30 + 2 * 10);
      expect(modelFor('x' * 21, 10).extentOf(0), 30 + 3 * 10);
      expect(modelFor('', 10).extentOf(0), 30 + 10);
      expect(modelFor('x' * 25, 0).extentOf(0), 30 + 10, reason: 'no wrap');
    });

    test('itemAt finds the item whose extent holds y, at every boundary', () {
      final DiffFile file = _file(<DiffHunk>[
        _numbered('...+...', start: 5),
        _numbered('..-.', start: 30),
      ]);
      final List<DiffSide> sides = <DiffSide>[(file: file, staged: false)];
      final DiffListModel model = DiffListModel.fromBlocks(
        orderedDiffBlocks(sides, _scopes(sides)),
        sides: sides,
        headings: true,
        metrics: _metrics,
        leadingExtents: const <double>[22],
      );
      final int n = model.items.length;
      for (int i = 0; i < n; i++) {
        final double top = model.offsetOf(i);
        final double bottom = model.offsetOf(i + 1);
        for (final double y in <double>[top, (top + bottom) / 2, bottom - .5]) {
          expect(model.itemAt(y), i, reason: 'y $y');
        }
      }
      expect(model.itemAt(-5), 0, reason: 'above the list clamps to the top');
      expect(model.itemAt(model.totalExtent), n - 1);
      expect(model.itemAt(model.totalExtent + 100), n - 1);
    });

    test('an empty list has no items, no extent and no item at any y', () {
      final DiffListModel empty = DiffListModel.fromBlocks(
        const <DiffBlock>[],
        sides: const <DiffSide>[],
        headings: true,
        metrics: _metrics,
      );
      expect(empty.items, isEmpty);
      expect(empty.rowKeys, isEmpty);
      expect(empty.changedRows, isEmpty);
      expect(empty.cardItems, isEmpty);
      expect(empty.totalExtent, 0);
      expect(empty.offsetOf(0), 0);
      expect(empty.itemAt(0), isNull);
      expect(empty.itemAt(50), isNull);
      expect(empty.rowIndexOf('0:0:0'), isNull);
    });
  });

  test('seeded merged diffs with fill: the model keys rows exactly as the '
      'painted blocks do, and every invariant holds', () {
    final Random rng = Random(20261024);
    for (int round = 0; round < 200; round++) {
      final int n = 3 + rng.nextInt(12);
      final StringBuffer staged = StringBuffer();
      final StringBuffer unstaged = StringBuffer();
      for (int line = 1; line <= n; line++) {
        if (rng.nextInt(5) == 0) staged.write('-');
        if (rng.nextInt(5) == 0) unstaged.write('+');
        staged.write(rng.nextInt(4) == 0 ? '+' : '.');
        unstaged.write(rng.nextInt(4) == 0 ? '-' : '.');
      }
      final List<DiffSide> sides = <DiffSide>[
        (
          file: _file(<DiffHunk>[_numbered(unstaged.toString(), start: 1)]),
          staged: false,
        ),
        (
          file: _file(<DiffHunk>[_numbered(staged.toString(), start: 1)]),
          staged: true,
        ),
      ];
      final bool full = rng.nextBool();
      final List<DiffBlock> blocks = orderedDiffBlocks(
        sides,
        _scopes(sides),
        fill: full
            ? <DiffFillRow>[
                ..._fill(<int>[n + 3, n + 4]),
                ..._fill(<int>[n + 6], sourceIndex: 1),
              ]
            : null,
      );
      final DiffListModel model = DiffListModel.fromBlocks(
        blocks,
        sides: sides,
        headings: !full,
        metrics: (
          rowExtent: 10,
          headingExtent: 7,
          cardChromeExtent: 30,
          gapChromeExtent: 3,
          charsPerLine: rng.nextInt(3) * 4,
        ),
        leadingExtents: const <double>[22],
      );
      expect(model.rowKeys, _walk(blocks), reason: 'round $round');
      expect(
        model.cardItems.length,
        blocks.where((DiffBlock b) => b.segment is DiffScopeSegment).length,
      );
      for (int c = 1; c < model.cardItems.length; c++) {
        expect(model.cardItems[c - 1] < model.cardItems[c], isTrue);
      }
      for (int c = 1; c < model.changedRows.length; c++) {
        expect(model.changedRows[c - 1] < model.changedRows[c], isTrue);
      }
      _expectConsistent(model);
    }
  });

  // Slice S3: a synced `2 file` column pads every segment at its end with a
  // spacer item (plan: Slice S, B1/E3). Rows, cards and keys are untouched.
  group('DiffListModel -- sync spacers', () {
    test('full-file: a spacer closes every segment, absent ones included, '
        'and the rows are what they were', () {
      final DiffFile file = _file(<DiffHunk>[_numbered('.+.', start: 3)]);
      final List<DiffSide> sides = <DiffSide>[(file: file, staged: false)];
      final List<DiffBlock> blocks = orderedDiffBlocks(
        sides,
        _scopes(sides),
        fill: <DiffFillRow>[
          ..._fill(<int>[1, 2]),
          ..._fill(<int>[5, 6]),
        ],
      );
      DiffListModel build({DiffListSync? sync}) => DiffListModel.fromBlocks(
        blocks,
        sides: sides,
        headings: false,
        metrics: _metrics,
        leadingExtents: const <double>[22],
        sync: sync,
      );
      final DiffListModel plain = build();
      // Units: fill 1, fill 2, gap 3, card (3,1), gap 4, fill 5, fill 6.
      // Segment 5 has nothing of this column's.
      final DiffListModel model = build(
        sync: (
          segmentOfUnit: const <int>[1, 1, 2, 2, 2, 3, 4],
          segmentCount: 6,
          spacerExtentOf: (int segment) => 100.0 + segment,
        ),
      );

      expect(model.items.map(_shape).toList(), <String>[
        'leading 0',
        'spacer 0',
        'fill 0:1',
        'fill 0:2',
        'spacer 1',
        'gap 0:0:0',
        'card 0:0:1',
        'gap 0:0:2',
        'spacer 2',
        'fill 0:5',
        'spacer 3',
        'fill 0:6',
        'spacer 4',
        'spacer 5',
      ]);
      expect(model.rowKeys, plain.rowKeys);
      expect(model.changedRows, plain.changedRows);
      expect(model.cardItems, <int>[6]);
      expect(model.items[6], isA<DiffBlockItem>());
      expect(
        <int>[
          for (int i = 0; i < model.items.length; i++) model.segmentOfItem(i),
        ],
        <int>[0, 0, 1, 1, 1, 2, 2, 2, 2, 3, 3, 4, 4, 5],
      );
      for (final int spacer in <int>[1, 4, 8, 10, 12, 13]) {
        expect(model.rowCountOf(spacer), 0, reason: 'item $spacer');
      }
      expect(model.firstRowOf(4), 2, reason: 'after fill 1 and 2');
      expect(model.firstRowOf(13), model.rowKeys.length);
      expect(model.extentOf(1), 100);
      expect(model.extentOf(13), 105);
      // A fill run's dashed rule carries across a spacer it is cut by.
      expect(model.fillRunOffsetOf(11), 1);
      _expectConsistent(model);
    });

    test('excerpt: a hunk heading goes with the segment of the block it '
        'heads, after the previous segment\'s spacer', () {
      final DiffFile file = _file(<DiffHunk>[
        _numbered('...+...', start: 5),
        _numbered('..-.', start: 30),
      ]);
      final List<DiffSide> sides = <DiffSide>[(file: file, staged: false)];
      final DiffListModel model = DiffListModel.fromBlocks(
        orderedDiffBlocks(sides, _scopes(sides)),
        sides: sides,
        headings: true,
        metrics: _metrics,
        sync: (
          segmentOfUnit: const <int>[1, 1, 1, 2, 2, 2],
          segmentCount: 3,
          spacerExtentOf: (_) => 0,
        ),
      );
      expect(model.items.map(_shape).toList(), <String>[
        'spacer 0',
        'heading 0:0',
        'gap 0:0:0,1,2',
        'card 0:0:3',
        'gap 0:0:4,5,6',
        'spacer 1',
        'heading 0:1',
        'gap 0:1:0,1',
        'card 0:1:2',
        'gap 0:1:3',
        'spacer 2',
      ]);
      expect(model.segmentOfItem(6), 2);
      _expectConsistent(model);
    });

    test('unsynced, every item is in segment 0 and there are no spacers', () {
      final DiffFile file = _file(<DiffHunk>[_numbered('.+.', start: 3)]);
      final List<DiffSide> sides = <DiffSide>[(file: file, staged: false)];
      final DiffListModel model = DiffListModel.fromBlocks(
        orderedDiffBlocks(sides, _scopes(sides)),
        sides: sides,
        headings: true,
        metrics: _metrics,
      );
      expect(model.items.whereType<DiffSpacerItem>(), isEmpty);
      expect(model.segmentOfItem(1), 0);
    });
  });
}
