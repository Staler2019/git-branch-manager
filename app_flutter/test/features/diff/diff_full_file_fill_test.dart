import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_full_file_fill.dart';

/// A [total]-line file whose lines in [edited] are each replaced by
/// `edited N`, diffed at [context] lines of context -- hunks built the way
/// git builds them: each edit's window clipped to the file, overlapping or
/// touching windows merged. Replacements keep both sides' numbering equal.
DiffFile _replacements(int total, Set<int> edited, {required int context}) {
  final List<(int, int)> windows = <(int, int)>[];
  for (final int e in edited.toList()..sort()) {
    final int from = e - context < 1 ? 1 : e - context;
    final int to = e + context > total ? total : e + context;
    if (windows.isNotEmpty && from <= windows.last.$2 + 1) {
      windows.last = (windows.last.$1, to);
    } else {
      windows.add((from, to));
    }
  }
  return _file(<DiffHunk>[
    for (final (int from, int to) in windows)
      DiffHunk(
        oldStart: from,
        oldCount: to - from + 1,
        newStart: from,
        newCount: to - from + 1,
        heading: '',
        lines: <DiffLine>[
          for (int n = from; n <= to; n++)
            if (edited.contains(n)) ...<DiffLine>[
              DiffLine(
                kind: DiffLineKind.removed,
                oldLine: n,
                newLine: 0,
                text: '$n',
              ),
              DiffLine(
                kind: DiffLineKind.added,
                oldLine: 0,
                newLine: n,
                text: 'edited $n',
              ),
            ] else
              DiffLine(
                kind: DiffLineKind.context,
                oldLine: n,
                newLine: n,
                text: '$n',
              ),
        ],
      ),
  ]);
}

const int _all = 1 << 30;

DiffFile _file(List<DiffHunk> hunks) => DiffFile(
  oldPath: 'f.txt',
  newPath: 'f.txt',
  kind: FileChangeKind.modified,
  oldMode: '',
  newMode: '',
  oldBlob: '',
  newBlob: '',
  binary: false,
  similarity: 0,
  addedLines: 0,
  removedLines: 0,
  displayPath: 'f.txt',
  hunks: hunks,
);

List<int> _lines(List<DiffFillRow>? rows) => <int>[
  for (final DiffFillRow r in rows!) r.indexLine,
];

List<int> _range(int from, int to) => <int>[for (int i = from; i <= to; i++) i];

void main() {
  group('fullFileFillRows -- one source (2 file)', () {
    test('fills every index line no -U3 hunk draws, in order', () {
      final List<DiffFillRow>? rows = fullFileFillRows(<DiffFillSource>[
        (
          excerpt: _replacements(50, <int>{5, 45}, context: 3),
          full: _replacements(50, <int>{5, 45}, context: _all),
          staged: false,
        ),
      ]);
      // -U3 draws 2..8 and 42..48.
      expect(_lines(rows), <int>[1, ..._range(9, 41), 49, 50]);
      expect(rows!.every((DiffFillRow r) => r.sourceIndex == 0), isTrue);
      expect(
        rows.every((DiffFillRow r) => r.line.kind == DiffLineKind.context),
        isTrue,
      );
      expect(rows.first.line.text, '1');
    });

    test('a staged source is measured on its new (index) side', () {
      // Staged: a pure insertion of index line 3 into a 10-line HEAD file.
      DiffFile insertion({required int context}) {
        final int from = 3 - context < 1 ? 1 : 3 - context;
        final int to = 3 + context > 11 ? 11 : 3 + context;
        return _file(<DiffHunk>[
          DiffHunk(
            oldStart: from,
            oldCount: to - from,
            newStart: from,
            newCount: to - from + 1,
            heading: '',
            lines: <DiffLine>[
              for (int n = from; n <= to; n++)
                if (n == 3)
                  const DiffLine(
                    kind: DiffLineKind.added,
                    oldLine: 0,
                    newLine: 3,
                    text: 'new',
                  )
                else
                  DiffLine(
                    kind: DiffLineKind.context,
                    oldLine: n < 3 ? n : n - 1,
                    newLine: n,
                    text: 'l$n',
                  ),
            ],
          ),
        ]);
      }

      final List<DiffFillRow>? rows = fullFileFillRows(<DiffFillSource>[
        (
          excerpt: insertion(context: 3),
          full: insertion(context: _all),
          staged: true,
        ),
      ]);
      // -U3 draws index 1..6; the index has 11 lines.
      expect(_lines(rows), _range(7, 11));
      expect(rows!.first.line.text, 'l7');
    });

    test('nothing to fill when -U3 already shows the whole file', () {
      expect(
        fullFileFillRows(<DiffFillSource>[
          (
            excerpt: _replacements(6, <int>{3}, context: 3),
            full: _replacements(6, <int>{3}, context: _all),
            staged: false,
          ),
        ]),
        isEmpty,
      );
    });
  });

  group('fullFileFillRows -- refuses what it cannot trust', () {
    test('changed lines that disagree (the file moved between the two git '
        'runs) give null', () {
      expect(
        fullFileFillRows(<DiffFillSource>[
          (
            excerpt: _replacements(50, <int>{5, 45}, context: 3),
            full: _replacements(50, <int>{5, 46}, context: _all),
            staged: false,
          ),
        ]),
        isNull,
      );
    });

    test('the same lines changed to different text give null', () {
      final DiffFile full = _replacements(20, <int>{5}, context: _all);
      final DiffHunk h = full.hunks.single;
      final DiffFile retexted = _file(<DiffHunk>[
        DiffHunk(
          oldStart: h.oldStart,
          oldCount: h.oldCount,
          newStart: h.newStart,
          newCount: h.newCount,
          heading: '',
          lines: <DiffLine>[
            for (final DiffLine l in h.lines)
              l.kind == DiffLineKind.added
                  ? DiffLine(
                      kind: l.kind,
                      oldLine: l.oldLine,
                      newLine: l.newLine,
                      text: 'other',
                    )
                  : l,
          ],
        ),
      ]);
      expect(
        fullFileFillRows(<DiffFillSource>[
          (
            excerpt: _replacements(20, <int>{5}, context: 3),
            full: retexted,
            staged: false,
          ),
        ]),
        isNull,
      );
    });

    test('a source whose full diff has not arrived gives null', () {
      expect(
        fullFileFillRows(<DiffFillSource>[
          (
            excerpt: _replacements(50, <int>{5}, context: 3),
            full: null,
            staged: false,
          ),
        ]),
        isNull,
      );
    });

    test('a binary source gives null', () {
      const DiffFile binary = DiffFile(
        oldPath: 'b',
        newPath: 'b',
        kind: FileChangeKind.modified,
        oldMode: '',
        newMode: '',
        oldBlob: '',
        newBlob: '',
        binary: true,
        similarity: 0,
        addedLines: 0,
        removedLines: 0,
        displayPath: 'b',
        hunks: <DiffHunk>[],
      );
      expect(
        fullFileFillRows(<DiffFillSource>[
          (excerpt: binary, full: binary, staged: false),
        ]),
        isNull,
      );
    });
  });

  group('fullFileFillRows -- two sources (unified)', () {
    // Unstaged edits index line 5; staged edited line 45 (index holds
    // `edited 45`). Both are replacements, so both sides number the index
    // the same way.
    final List<DiffFillSource> both = <DiffFillSource>[
      (
        excerpt: _replacements(50, <int>{5}, context: 3),
        full: _replacements(50, <int>{5}, context: _all),
        staged: false,
      ),
      (
        excerpt: _replacements(50, <int>{45}, context: 3),
        full: _replacements(50, <int>{45}, context: _all),
        staged: true,
      ),
    ];

    test('each index line no hunk of either side draws is filled exactly '
        'once', () {
      final List<int> lines = _lines(fullFileFillRows(both));
      expect(lines, <int>[1, ..._range(9, 41), 49, 50]);
      expect(lines.toSet(), hasLength(lines.length));
    });

    test('the unstaged source supplies the row, whichever slot it is in', () {
      expect(
        fullFileFillRows(both)!.map((DiffFillRow r) => r.sourceIndex).toSet(),
        <int>{0},
      );
      expect(
        fullFileFillRows(both.reversed.toList())!
            .map((DiffFillRow r) => r.sourceIndex)
            .toSet(),
        <int>{1},
      );
    });

    test('one side that cannot be trusted keeps the whole pane in excerpt '
        'mode', () {
      expect(
        fullFileFillRows(<DiffFillSource>[
          both.first,
          (excerpt: both.last.excerpt, full: null, staged: true),
        ]),
        isNull,
      );
    });

    test('a side with no -U3 diff (only one direction changed) is skipped', () {
      expect(
        _lines(
          fullFileFillRows(<DiffFillSource>[
            both.first,
            (excerpt: null, full: null, staged: true),
          ]),
        ),
        <int>[1, ..._range(9, 50)],
      );
    });
  });
}
