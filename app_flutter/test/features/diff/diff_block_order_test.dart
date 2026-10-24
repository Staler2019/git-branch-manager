import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_block_order.dart';
import 'package:gbm_flutter/features/diff/diff_scopes.dart';

/// A hunk from a sketch with real line numbers: `.` advances both sides,
/// `-` the old side only, `+` the new side only.
DiffHunk _numbered(String sketch, {required int start}) {
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
        text: 'line $i',
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

/// The scopes of each side, split the way the merged view splits them.
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

List<String> _rows(List<DiffBlock> blocks) => <String>[
  for (final DiffBlock b in blocks)
    for (final int line in b.segment.lineIndices)
      '${b.sourceIndex}:${b.hunkIndex}:$line',
];

String _shape(DiffBlock b) =>
    '${b.segment is DiffScopeSegment ? 'card' : 'gap'} '
    '${b.sourceIndex}:${b.segment.lineIndices.join(',')}';

void main() {
  group('orderedDiffBlocks -- merged order is per row', () {
    // Staged (HEAD -> index) adds index 8, keeps 9-11, adds 12 and deletes a
    // HEAD-only line after it -> (12, 1). Unstaged (index -> worktree) is a
    // two-line insertion after index 10 with no context -> (10, 1) twice.
    // The staged gap 9-11 straddles that insertion point: placed as one run
    // at its first row, index 11 would be painted above an insertion that
    // sits before it.
    final List<DiffSide> sides = <DiffSide>[
      (file: _file(<DiffHunk>[_numbered('++', start: 11)]), staged: false),
      (file: _file(<DiffHunk>[_numbered('+...+-', start: 8)]), staged: true),
    ];

    test('every painted row is in (line, offset, rank) order, cards whole', () {
      expect(_rows(orderedDiffBlocks(sides, _scopes(sides))), <String>[
        '1:0:0', // + index 8         (8, 0, 1)
        '1:0:1', //   index 9         (9, 0, 1)
        '1:0:2', //   index 10        (10, 0, 1)
        '0:0:0', // + after 10        (10, 1, 0)
        '0:0:1', // + after 10        (10, 1, 0)
        '1:0:3', //   index 11        (11, 0, 1)
        '1:0:4', // + index 12        (12, 0, 1)
        '1:0:5', // - after 12        (12, 1, 1)
      ]);
    });

    test('context rows split for the sort are joined back where adjacent', () {
      expect(
        orderedDiffBlocks(sides, _scopes(sides)).map(_shape).toList(),
        <String>[
          'card 1:0',
          'gap 1:1,2',
          'card 0:0,1',
          'gap 1:3',
          'card 1:4,5',
        ],
      );
    });
  });

  group(
    'orderedDiffBlocks -- the tie-break is the rank, not the source order',
    () {
      test('at an equal position the unstaged rows come first even when the '
          'staged side is source 0', () {
        // Staged deletes a HEAD-only line after index 10, unstaged inserts two
        // lines after it: all three rows are (10, 1). Sources deliberately in
        // the opposite order to the pane's, so source order and rank disagree.
        final List<DiffSide> sides = <DiffSide>[
          (file: _file(<DiffHunk>[_numbered('.-.', start: 10)]), staged: true),
          (
            file: _file(<DiffHunk>[_numbered('.++.', start: 10)]),
            staged: false,
          ),
        ];
        final List<String> rows = _rows(
          orderedDiffBlocks(sides, _scopes(sides)),
        );
        expect(rows.indexOf('1:0:1'), lessThan(rows.indexOf('0:0:1')));
        expect(rows.indexOf('1:0:2'), lessThan(rows.indexOf('0:0:1')));
      });
    },
  );

  group('orderedDiffBlocks -- a lone side is untouched (U6)', () {
    test('the blocks are exactly hunkSegments, hunk by hunk', () {
      final List<DiffSide> sides = <DiffSide>[
        (
          file: _file(<DiffHunk>[
            _numbered('..-...+..', start: 1),
            _numbered('.+.', start: 40),
          ]),
          staged: false,
        ),
      ];
      final List<Map<int, List<DiffScope>>> scopes = _scopes(sides);
      final DiffFile file = sides.single.file!;

      expect(orderedDiffBlocks(sides, scopes).map(_shape).toList(), <String>[
        for (int h = 0; h < file.hunks.length; h++)
          for (final DiffSegment segment in hunkSegments(
            file.hunks[h],
            scopes.single[h]!,
          ))
            _shape((
              sourceIndex: 0,
              hunkIndex: h,
              segment: segment,
              position: (line: 0, offset: 0),
            )),
      ]);
    });
  });
}
