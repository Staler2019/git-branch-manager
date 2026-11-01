import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_scopes.dart';

/// Builds a hunk from a compact sketch: `+` added, `-` removed, `.` context,
/// `\` the no-newline marker. Line numbers are irrelevant to scope splitting,
/// so they are all zero.
DiffHunk _hunk(String sketch) => DiffHunk(
  oldStart: 1,
  oldCount: sketch.length,
  newStart: 1,
  newCount: sketch.length,
  heading: '',
  lines: <DiffLine>[
    for (int i = 0; i < sketch.length; i++)
      DiffLine(
        kind: switch (sketch[i]) {
          '+' => DiffLineKind.added,
          '-' => DiffLineKind.removed,
          r'\' => DiffLineKind.noNewlineMarker,
          _ => DiffLineKind.context,
        },
        oldLine: 0,
        newLine: 0,
        text: 'line $i',
      ),
  ],
);

DiffFile _file({
  String path = 'a.dart',
  bool binary = false,
  List<DiffHunk> hunks = const <DiffHunk>[],
}) => DiffFile(
  oldPath: path,
  newPath: path,
  kind: FileChangeKind.modified,
  oldMode: '',
  newMode: '',
  oldBlob: '',
  newBlob: '',
  binary: binary,
  similarity: 0,
  addedLines: 0,
  removedLines: 0,
  displayPath: path,
  hunks: hunks,
);

List<List<int>> _spans(List<DiffScope> scopes) =>
    scopes.map((DiffScope s) => s.lineIndices).toList(growable: false);

List<List<int>> _changed(List<DiffScope> scopes) =>
    scopes.map((DiffScope s) => s.changedLineIndices).toList(growable: false);

/// A hunk from a sketch with real line numbers: `.` advances both sides,
/// `-` the old side only, `+` the new side only.
DiffHunk _numbered(
  String sketch, {
  required int oldStart,
  required int newStart,
}) {
  int oldLine = oldStart;
  int newLine = newStart;
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
    oldStart: oldStart,
    oldCount: oldLine - oldStart,
    newStart: newStart,
    newCount: newLine - newStart,
    heading: '',
    lines: lines,
  );
}

/// The barriers a staged side that adds exactly [indexLines] hands the
/// unstaged side -- the shape every pre-position barrier test was written in.
IndexBarriers _stagedAdds(List<int> indexLines) =>
    IndexBarriers.ofChanges(<DiffSide>[
      (
        file: _file(
          hunks: <DiffHunk>[
            DiffHunk(
              oldStart: 1,
              oldCount: 0,
              newStart: 1,
              newCount: indexLines.length,
              heading: '',
              lines: <DiffLine>[
                for (final int line in indexLines)
                  DiffLine(
                    kind: DiffLineKind.added,
                    oldLine: 0,
                    newLine: line,
                    text: 'x',
                  ),
              ],
            ),
          ],
        ),
        staged: true,
      ),
    ]);

void main() {
  group('splitHunkIntoScopes -- the gap rule', () {
    test('0 unchanged lines between two changes keeps them in one scope', () {
      expect(_spans(splitHunkIntoScopes(_hunk('.+-.'))), <List<int>>[
        <int>[1, 2],
      ]);
    });

    test('1 unchanged line between two changes still merges', () {
      expect(_spans(splitHunkIntoScopes(_hunk('.+.+.'))), <List<int>>[
        <int>[1, 2, 3],
      ]);
    });

    test('2 unchanged lines between two changes still merges -- the boundary '
        'the rule is written at', () {
      expect(_spans(splitHunkIntoScopes(_hunk('.+..+.'))), <List<int>>[
        <int>[1, 2, 3, 4],
      ]);
    });

    test('3 unchanged lines between two changes splits -- the other side of '
        'the same boundary', () {
      expect(_spans(splitHunkIntoScopes(_hunk('.+...+.'))), <List<int>>[
        <int>[1],
        <int>[5],
      ]);
    });

    test('4 unchanged lines between two changes splits', () {
      expect(_spans(splitHunkIntoScopes(_hunk('.+....+.'))), <List<int>>[
        <int>[1],
        <int>[6],
      ]);
    });
  });

  group('splitHunkIntoScopes -- hunk boundaries', () {
    test('a change on the first line of the hunk starts a scope there', () {
      expect(_spans(splitHunkIntoScopes(_hunk('+..'))), <List<int>>[
        <int>[0],
      ]);
    });

    test('a change on the last line of the hunk ends a scope there', () {
      expect(_spans(splitHunkIntoScopes(_hunk('..+'))), <List<int>>[
        <int>[2],
      ]);
    });

    test('leading and trailing context stays outside the scope', () {
      // The scope spans first-changed..last-changed. Context before and
      // after is not "part of the change" and belongs outside the card.
      expect(_spans(splitHunkIntoScopes(_hunk('...+-...'))), <List<int>>[
        <int>[3, 4],
      ]);
    });

    test('a hunk with no changed line at all yields no scopes', () {
      expect(splitHunkIntoScopes(_hunk('....')), isEmpty);
    });

    test('a hunk that is entirely one run of changes is one scope', () {
      expect(_spans(splitHunkIntoScopes(_hunk('---+++'))), <List<int>>[
        <int>[0, 1, 2, 3, 4, 5],
      ]);
    });

    test('consecutive removals followed by consecutive additions stay one '
        'scope', () {
      expect(_spans(splitHunkIntoScopes(_hunk('.--++.'))), <List<int>>[
        <int>[1, 2, 3, 4],
      ]);
    });

    test('three separated changes make three scopes', () {
      expect(_spans(splitHunkIntoScopes(_hunk('+...+...+'))), <List<int>>[
        <int>[0],
        <int>[4],
        <int>[8],
      ]);
    });
  });

  group('DiffScope contents', () {
    test('changedLineIndices excludes the context the gap rule swallowed', () {
      final List<DiffScope> scopes = splitHunkIntoScopes(_hunk('.+..-.'));

      expect(_spans(scopes), <List<int>>[
        <int>[1, 2, 3, 4],
      ]);
      expect(
        _changed(scopes),
        <List<int>>[
          <int>[1, 4],
        ],
        reason:
            'gbm_stage_lines takes the lines to move; passing the swallowed '
            'context would be asking git to stage lines that did not change',
      );
    });

    test('counts added and removed separately, for the card header', () {
      final DiffScope scope = splitHunkIntoScopes(_hunk('.--+.')).single;

      expect(scope.addedCount, 1);
      expect(scope.removedCount, 2);
      expect(
        scope.changedLineIndices.length,
        3,
        reason: 'the button says how many lines move, both kinds together',
      );
    });

    test('the no-newline marker is neither a change nor a wall', () {
      // UnifiedDiffParser lets context and the no-newline marker through a
      // rebuilt patch regardless of selection, so it can never be staged on
      // its own -- but it also must not split a scope in two.
      final List<DiffScope> scopes = splitHunkIntoScopes(_hunk('+\\+'));

      expect(_spans(scopes), <List<int>>[
        <int>[0, 1, 2],
      ]);
      expect(_changed(scopes), <List<int>>[
        <int>[0, 2],
      ]);
    });
  });

  group('splitHunkIntoScopes -- barriers', () {
    // A barrier is the *other* diff's change, as an [IndexKey]. A scope may
    // not span across one: 使用者裁定 ①「兩張卡片都包住同一個未變更行 →
    // 卡片在這裡切開」and ②「對側純插入／純刪除落在卡片範圍中間 → 卡片在那個
    // 位置切開」. Strictly between two consecutive own changes, under
    // [compareIndexKeys] -- so at an equal (line, offset) the rank decides
    // which side of the barrier this side's row is on.
    IndexBarriers stagedSide(String sketch, {required int start}) =>
        IndexBarriers.ofChanges(<DiffSide>[
          (
            file: _file(
              hunks: <DiffHunk>[
                _numbered(sketch, oldStart: start, newStart: start),
              ],
            ),
            staged: true,
          ),
        ]);
    IndexBarriers unstagedSide(String sketch, {required int start}) =>
        IndexBarriers.ofChanges(<DiffSide>[
          (
            file: _file(
              hunks: <DiffHunk>[
                _numbered(sketch, oldStart: start, newStart: start),
              ],
            ),
            staged: false,
          ),
        ]);

    test('the other side\'s change on an unchanged line between two changes '
        'splits them, and that line stays out of both', () {
      // Unstaged `+ + . + +` over index line 1; staged adds index line 1.
      final DiffHunk hunk = _numbered('++.++', oldStart: 1, newStart: 1);
      expect(splitHunkIntoScopes(hunk), hasLength(1));
      final List<DiffScope> scopes = splitHunkIntoScopes(
        hunk,
        barriers: stagedSide('+', start: 1),
      );
      expect(_spans(scopes), <List<int>>[
        <int>[0, 1],
        <int>[3, 4],
      ]);
    });

    test('a barrier before every change changes nothing', () {
      final DiffHunk hunk = _numbered('.++++', oldStart: 1, newStart: 1);
      expect(
        splitHunkIntoScopes(hunk, barriers: stagedSide('+', start: 1)),
        hasLength(1),
      );
    });

    test('ruling ②: a staged deletion inside an unstaged card splits it', () {
      // Unstaged removes index 10 and 13, context 11-12 in between: one card
      // under the gap rule. Staged deletes a HEAD-only line after index 11,
      // which has no index number -> (11, 1). Before the fix that row was no
      // barrier at all (changedIndexLines skips it).
      final DiffHunk unstaged = _numbered('-..-', oldStart: 10, newStart: 10);
      expect(splitHunkIntoScopes(unstaged), hasLength(1));
      final List<DiffScope> scopes = splitHunkIntoScopes(
        unstaged,
        barriers: stagedSide('.-.', start: 11),
      );
      expect(_spans(scopes), <List<int>>[
        <int>[0],
        <int>[3],
      ]);
    });

    test('ruling ①: a staged card is split by an unstaged insertion it would '
        'otherwise share an unchanged line with', () {
      // Staged adds index 10 and 12 (context 11 between -> one card holding
      // 11). Unstaged inserts after 10 and removes 12, so its card would hold
      // 11 too. The unstaged insertion (10, 1) sits strictly inside the
      // staged span, so the staged card splits and 11 leaves it.
      final DiffHunk staged = _numbered('+.+', oldStart: 10, newStart: 10);
      expect(splitHunkIntoScopes(staged, staged: true), hasLength(1));
      final List<DiffScope> scopes = splitHunkIntoScopes(
        staged,
        staged: true,
        barriers: unstagedSide('.+.-', start: 10),
      );
      expect(_spans(scopes), <List<int>>[
        <int>[0],
        <int>[2],
      ]);
    });

    test('both sides change the same index line: in the middle of an unstaged '
        'run, the run splits after it', () {
      // Unstaged removes 9, 10, 11; staged adds 10 -> (10, 0, rank 1) sorts
      // after unstaged's own (10, 0, rank 0) and before (11, 0, 0).
      final DiffHunk unstaged = _numbered('---', oldStart: 9, newStart: 9);
      expect(
        _spans(
          splitHunkIntoScopes(unstaged, barriers: stagedSide('+', start: 10)),
        ),
        <List<int>>[
          <int>[0, 1],
          <int>[2],
        ],
      );
    });

    test('both sides change the same index line: at the end of an unstaged '
        'run, nothing splits', () {
      final DiffHunk unstaged = _numbered('---', oldStart: 9, newStart: 9);
      expect(
        splitHunkIntoScopes(unstaged, barriers: stagedSide('+', start: 11)),
        hasLength(1),
      );
    });

    test('both sides fill the same gap: a multi-line unstaged insertion is '
        'not split by a staged deletion at the same position', () {
      // Both are (10, 1); equal keys on this side have nothing strictly
      // between them, so the three insertions stay one card.
      final DiffHunk unstaged = _numbered('.+++.', oldStart: 10, newStart: 10);
      expect(
        splitHunkIntoScopes(unstaged, barriers: stagedSide('.-.', start: 10)),
        hasLength(1),
      );
    });
  });

  group('merged scopes -- seeded property', () {
    // Builds one consistent pair of diffs over an index of [n] lines: each
    // index line is either untouched, added by staging (absent in HEAD), or
    // removed in the work tree -- or *both*, case (1). Each gap between two
    // index lines may hold HEAD-only lines (staged deletions) and work-tree
    // insertions -- both at once is case (2). One hunk per side, every row
    // present, so the scope split sees the whole file.
    ({DiffHunk staged, DiffHunk unstaged, bool case1, bool case2}) pair(
      Random rng,
      int n,
    ) {
      final StringBuffer staged = StringBuffer();
      final StringBuffer unstaged = StringBuffer();
      bool case1 = false;
      bool case2 = false;
      void gap() {
        final int deletions = rng.nextInt(3) == 0 ? 1 + rng.nextInt(2) : 0;
        final int insertions = rng.nextInt(3) == 0 ? 1 + rng.nextInt(2) : 0;
        staged.write('-' * deletions);
        unstaged.write('+' * insertions);
        if (deletions > 0 && insertions > 0) case2 = true;
      }

      gap();
      for (int line = 1; line <= n; line++) {
        final bool stagedAdds = rng.nextInt(4) == 0;
        final bool unstagedRemoves = rng.nextInt(4) == 0;
        staged.write(stagedAdds ? '+' : '.');
        unstaged.write(unstagedRemoves ? '-' : '.');
        if (stagedAdds && unstagedRemoves) case1 = true;
        gap();
      }
      return (
        staged: _numbered(staged.toString(), oldStart: 1, newStart: 1),
        unstaged: _numbered(unstaged.toString(), oldStart: 1, newStart: 1),
        case1: case1,
        case2: case2,
      );
    }

    IndexKey keyAt(DiffHunk hunk, int i, {required bool staged}) {
      final IndexPosition p = indexPositionOf(hunk, i, staged: staged);
      return (
        line: p.line,
        offset: p.offset,
        rank: indexRankOf(staged: staged),
      );
    }

    test('no two cards of different sides overlap, and a card\'s context '
        'never shares a position with the other side\'s card rows', () {
      final Random rng = Random(20261024);
      int sawCase1 = 0;
      int sawCase2 = 0;
      for (int round = 0; round < 400; round++) {
        final ({DiffHunk staged, DiffHunk unstaged, bool case1, bool case2}) p =
            pair(rng, 2 + rng.nextInt(10));
        if (p.case1) sawCase1++;
        if (p.case2) sawCase2++;
        final DiffFile stagedFile = _file(hunks: <DiffHunk>[p.staged]);
        final DiffFile unstagedFile = _file(hunks: <DiffHunk>[p.unstaged]);
        final List<IndexBarriers> barriers = DiffBarrierMemo().barriersFor(
          <DiffSide>[
            (file: unstagedFile, staged: false),
            (file: stagedFile, staged: true),
          ],
        );
        final List<DiffScope> u = splitHunkIntoScopes(
          p.unstaged,
          barriers: barriers[0],
        );
        final List<DiffScope> st = splitHunkIntoScopes(
          p.staged,
          staged: true,
          barriers: barriers[1],
        );

        for (final DiffScope a in u) {
          final IndexKey aLo = keyAt(
            p.unstaged,
            a.lineIndices.first,
            staged: false,
          );
          final IndexKey aHi = keyAt(
            p.unstaged,
            a.lineIndices.last,
            staged: false,
          );
          for (final DiffScope b in st) {
            final IndexKey bLo = keyAt(
              p.staged,
              b.lineIndices.first,
              staged: true,
            );
            final IndexKey bHi = keyAt(
              p.staged,
              b.lineIndices.last,
              staged: true,
            );
            final bool overlap =
                compareIndexKeys(aLo, bHi) <= 0 &&
                compareIndexKeys(bLo, aHi) <= 0;
            expect(
              overlap,
              isFalse,
              reason:
                  'round $round: ${p.unstaged.lines.map((DiffLine l) => l.kind.name[0]).join()} '
                  'vs ${p.staged.lines.map((DiffLine l) => l.kind.name[0]).join()}',
            );

            // Shared (line, offset) is allowed only between two change rows.
            for (final int i in a.lineIndices) {
              for (final int j in b.lineIndices) {
                final IndexPosition pa = indexPositionOf(
                  p.unstaged,
                  i,
                  staged: false,
                );
                final IndexPosition pb = indexPositionOf(
                  p.staged,
                  j,
                  staged: true,
                );
                if (compareIndexPositions(pa, pb) != 0) continue;
                expect(
                  a.changedLineIndices.contains(i) &&
                      b.changedLineIndices.contains(j),
                  isTrue,
                  reason: 'round $round shares $pa on a context row',
                );
              }
            }
          }
        }
      }
      // The generator has to reach the two tie states, or the property says
      // nothing about them.
      expect(sawCase1, greaterThan(20));
      expect(sawCase2, greaterThan(20));
    });
  });

  group('hiddenContextLines -- one row per index line', () {
    // Extends 使用者裁定 B (「hidden, not drawn twice」) to a context row the
    // other side draws as context too. Survivors: (a) gap vs gap keeps the
    // unstaged copy; (b)(c) gap vs card keeps the card's copy -- a card
    // cannot drop a row from inside itself.
    List<int> paintedIndexLines(DiffHunk unstaged, DiffHunk staged) {
      final List<DiffSide> sides = <DiffSide>[
        (file: _file(hunks: <DiffHunk>[unstaged]), staged: false),
        (file: _file(hunks: <DiffHunk>[staged]), staged: true),
      ];
      final List<IndexBarriers> barriers = DiffBarrierMemo().barriersFor(sides);
      final List<Map<int, List<DiffScope>>> scopes =
          <Map<int, List<DiffScope>>>[
            for (int i = 0; i < 2; i++)
              splitDiffFileIntoScopes(
                sides[i].file!,
                staged: sides[i].staged,
                barriers: barriers[i],
              ),
          ];
      final List<Map<int, Set<int>>> hidden = hiddenContextLines(sides, scopes);
      final List<int> lines = <int>[];
      for (int i = 0; i < 2; i++) {
        final DiffHunk hunk = sides[i].file!.hunks.single;
        for (final DiffSegment segment in hunkSegments(
          hunk,
          scopes[i][0]!,
          hiddenLines: hidden[i][0] ?? const <int>{},
        )) {
          for (final int index in segment.lineIndices) {
            final DiffLine line = hunk.lines[index];
            final int number = sides[i].staged ? line.newLine : line.oldLine;
            // Offset-1 rows hold no index line, so they cannot collide.
            if (number > 0) lines.add(number * 10 + i);
          }
        }
      }
      return lines..sort();
    }

    // Encoded as indexLine * 10 + side (0 unstaged, 1 staged), so one list
    // says both "drawn once" and "by whom".
    test(
      '(a) both sides\' gaps hold index 6-8: the unstaged copy survives',
      () {
        expect(
          paintedIndexLines(
            _numbered('...-', oldStart: 6, newStart: 6),
            _numbered('+...', oldStart: 5, newStart: 5),
          ),
          <int>[51, 60, 70, 80, 90],
        );
      },
    );

    test('(b) a staged card holds index 11, the unstaged gap drops it', () {
      expect(
        paintedIndexLines(
          _numbered('...-', oldStart: 11, newStart: 11),
          _numbered('+.+', oldStart: 10, newStart: 10),
        ),
        // 12 is the staged change (the unstaged copy was already hidden by
        // ruling B); 11 now stays only inside the staged card.
        <int>[101, 111, 121, 130, 140],
      );
    });

    test('(c) an unstaged card holds index 11, the staged gap drops it', () {
      expect(
        paintedIndexLines(
          _numbered('-.-', oldStart: 10, newStart: 10),
          _numbered('..+', oldStart: 11, newStart: 11),
        ),
        <int>[100, 110, 120, 131],
      );
    });

    test('a lone side hides nothing', () {
      final List<DiffSide> sides = <DiffSide>[
        (
          file: _file(
            hunks: <DiffHunk>[_numbered('.-.', oldStart: 1, newStart: 1)],
          ),
          staged: false,
        ),
      ];
      final List<Map<int, Set<int>>> hidden = hiddenContextLines(
        sides,
        <Map<int, List<DiffScope>>>[splitDiffFileIntoScopes(sides[0].file!)],
      );
      expect(hidden.single, isEmpty);
    });
  });

  group('hunkSegments', () {
    List<String> shape(List<DiffSegment> segments) => segments
        .map(
          (DiffSegment s) => switch (s) {
            DiffGapSegment() => 'gap${s.lineIndices}',
            DiffScopeSegment() => 'scope${s.lineIndices}',
            DiffFillSegment() => 'fill',
          },
        )
        .toList(growable: false);

    List<DiffSegment> segmentsOf(String sketch) {
      final DiffHunk hunk = _hunk(sketch);
      return hunkSegments(hunk, splitHunkIntoScopes(hunk));
    }

    // A hidden row is one the staged side draws as a change, so the staged
    // side's barriers are what keeps it out of every unstaged scope too.
    List<DiffSegment> segmentsHiding(String sketch, Set<int> hidden) {
      final DiffHunk hunk = _numbered(sketch, oldStart: 1, newStart: 1);
      return hunkSegments(
        hunk,
        splitHunkIntoScopes(
          hunk,
          barriers: _stagedAdds(<int>[
            for (final int i in hidden) hunk.lines[i].oldLine,
          ]),
        ),
        hiddenLines: hidden,
      );
    }

    test('every line of the hunk is drawn exactly once, in order', () {
      // The property the rendering loop depends on: it walks segments and
      // paints their lines, so a line in neither segment kind vanishes from
      // the screen and a line in both is painted twice.
      for (final String sketch in <String>[
        '...+-...',
        '+...+...+',
        '....',
        '---+++',
        '.+..-.',
        '+',
      ]) {
        final List<int> painted = <int>[
          for (final DiffSegment s in segmentsOf(sketch)) ...s.lineIndices,
        ];
        expect(painted, <int>[
          for (int i = 0; i < sketch.length; i++) i,
        ], reason: 'sketch "$sketch" did not cover its own lines');
      }
    });

    test('context before, between and after the scopes becomes gaps', () {
      expect(shape(segmentsOf('..+...+..')), <String>[
        'gap[0, 1]',
        'scope[2]',
        'gap[3, 4, 5]',
        'scope[6]',
        'gap[7, 8]',
      ]);
    });

    test('a scope touching the start or the end of the hunk has no gap beside '
        'it', () {
      expect(shape(segmentsOf('+..')), <String>['scope[0]', 'gap[1, 2]']);
      expect(shape(segmentsOf('..+')), <String>['gap[0, 1]', 'scope[2]']);
      expect(shape(segmentsOf('+')), <String>['scope[0]']);
    });

    test('a hunk with no change at all is one gap, not zero segments', () {
      expect(shape(segmentsOf('....')), <String>['gap[0, 1, 2, 3]']);
    });

    test('the context the gap rule swallowed stays inside the scope, not in a '
        'gap', () {
      // '.+..-.' merges across two unchanged lines, so 2 and 3 belong to the
      // card. Emitting them as a gap would draw a card, a slab of context and
      // a second card for what is one change.
      expect(shape(segmentsOf('.+..-.')), <String>[
        'gap[0]',
        'scope[1, 2, 3, 4]',
        'gap[5]',
      ]);
    });
    // 使用者裁定 B. A hidden line is not merely skipped: the context run it
    // sits in has to *break* there, or the two halves would be drawn as one
    // contiguous block and the merged list would order both by the first
    // half's position.
    test('a hidden line splits the gap it sits in and is not drawn', () {
      expect(shape(segmentsHiding('++.++', const <int>{2})), <String>[
        'scope[0, 1]',
        'scope[3, 4]',
      ]);
    });

    test('a hidden line inside a longer context run breaks it in two', () {
      expect(shape(segmentsHiding('+....+', const <int>{3})), <String>[
        'scope[0]',
        'gap[1, 2]',
        'gap[4]',
        'scope[5]',
      ]);
    });

    test('hiding nothing leaves every line covered exactly once', () {
      expect(
        shape(segmentsHiding('+....+', const <int>{})),
        shape(segmentsOf('+....+')),
      );
    });
  });

  group('scopeButtonLabel', () {
    test('names the spanned count first and the changed count in parens', () {
      // The user's own worked example: 1 added line plus 2 context lines the
      // gap rule swallowed.
      expect(
        scopeButtonLabel(staged: false, spanned: 3, changed: 1),
        'Stage 3 lines (1 changed)',
      );
    });

    test('drops the parenthetical when the two numbers agree', () {
      expect(
        scopeButtonLabel(staged: false, spanned: 2, changed: 2),
        'Stage 2 lines',
        reason:
            'the parens exist to disclose a gap; with no gap they are noise',
      );
    });

    test('singularises on the spanned count, not the changed one', () {
      expect(
        scopeButtonLabel(staged: false, spanned: 1, changed: 1),
        'Stage 1 line',
      );
      expect(
        scopeButtonLabel(staged: false, spanned: 1, changed: 0),
        'Stage 1 line (0 changed)',
      );
    });

    test('the staged side unstages', () {
      expect(
        scopeButtonLabel(staged: true, spanned: 3, changed: 1),
        'Unstage 3 lines (1 changed)',
      );
    });
  });

  group('splitDiffFileIntoScopes', () {
    test('scopes never span two hunks', () {
      final DiffFile file = DiffFile(
        oldPath: 'a.dart',
        newPath: 'a.dart',
        kind: FileChangeKind.modified,
        oldMode: '',
        newMode: '',
        oldBlob: '',
        newBlob: '',
        binary: false,
        similarity: 0,
        addedLines: 2,
        removedLines: 0,
        displayPath: 'a.dart',
        hunks: <DiffHunk>[_hunk('..+'), _hunk('+..')],
      );

      final Map<int, List<DiffScope>> byHunk = splitDiffFileIntoScopes(file);

      expect(byHunk.keys.toSet(), <int>{0, 1});
      expect(_spans(byHunk[0]!), <List<int>>[
        <int>[2],
      ]);
      expect(
        _spans(byHunk[1]!),
        <List<int>>[
          <int>[0],
        ],
        reason:
            'the last change of hunk 0 and the first of hunk 1 are adjacent '
            'in reading order but belong to different patches',
      );
    });

    test('a binary file has no scopes', () {
      final DiffFile file = DiffFile(
        oldPath: 'a.png',
        newPath: 'a.png',
        kind: FileChangeKind.modified,
        oldMode: '',
        newMode: '',
        oldBlob: '',
        newBlob: '',
        binary: true,
        similarity: 0,
        addedLines: 0,
        removedLines: 0,
        displayPath: 'a.png',
        hunks: const <DiffHunk>[],
      );

      expect(splitDiffFileIntoScopes(file), isEmpty);
    });
  });

  group('DiffScopeCache', () {
    // A counting stand-in for splitDiffFileIntoScopes. Counted, not `any`-ed:
    // the whole claim is "exactly once per file instance", and a cache that
    // split twice would answer every question about the *result* correctly.
    late int calls;
    late DiffScopeCache cache;

    setUp(() {
      calls = 0;
      cache = DiffScopeCache(
        split:
            (
              DiffFile file, {
              int maxGap = kDefaultScopeGap,
              bool staged = false,
              IndexBarriers barriers = IndexBarriers.none,
            }) {
              calls++;
              return splitDiffFileIntoScopes(
                file,
                maxGap: maxGap,
                staged: staged,
                barriers: barriers,
              );
            },
      );
    });

    test('splits once and reuses the answer for the same instance', () {
      final DiffFile file = _file(hunks: <DiffHunk>[_hunk('.+.')]);

      final Map<int, List<DiffScope>> first = cache.scopesOf(file);
      final Map<int, List<DiffScope>> second = cache.scopesOf(file);

      expect(calls, 1, reason: 'a rebuild that changed nothing must not split');
      expect(identical(first, second), isTrue);
      expect(_spans(first[0]!), <List<int>>[
        <int>[1],
      ]);
    });

    // The barrier set is part of the answer, so it has to be part of the key
    // -- a merged list hands the *same* file two different barrier sets as
    // soon as the other side's diff changes, and a cache keyed on the file
    // alone would go on drawing the previous split's cards.
    //
    // Identity, not content: the set is a pure function of the other
    // sources' `DiffFile`s, which the view memoises on those files' own
    // identities. Comparing contents instead would be O(changed lines) on
    // every frame of a selection drag, which is the same order as the split
    // this cache exists to avoid.
    test('a different barrier set re-splits', () {
      final DiffFile file = _file(hunks: <DiffHunk>[_hunk('++.++')]);

      cache.scopesOf(file, staged: false);
      final Map<int, List<DiffScope>> withBarrier = cache.scopesOf(
        file,
        staged: false,
        barriers: _stagedAdds(<int>[1]),
      );

      expect(calls, 2, reason: 'the barrier set is part of the key');
      expect(withBarrier[0], isNotNull);
    });

    test('the same barrier set instance hits', () {
      final DiffFile file = _file(hunks: <DiffHunk>[_hunk('++.++')]);
      final IndexBarriers barriers = _stagedAdds(<int>[1]);

      cache.scopesOf(file, staged: false, barriers: barriers);
      cache.scopesOf(file, staged: false, barriers: barriers);

      expect(calls, 1);
    });

    test('splits again when a new reply arrives for the same path', () {
      // Same path, same content, different object -- which is exactly what a
      // fresh `workingCopyDiffReady` payload produces. The cache must not
      // treat it as unchanged: only object identity can tell the two apart,
      // and the second parse is the one carrying the new staging state.
      final DiffFile before = _file(hunks: <DiffHunk>[_hunk('.+.')]);
      final DiffFile after = _file(hunks: <DiffHunk>[_hunk('.+.')]);

      cache.scopesOf(before);
      cache.scopesOf(after);

      expect(calls, 2);
    });

    test('splits again when the selected file changes', () {
      cache.scopesOf(_file(path: 'a.dart', hunks: <DiffHunk>[_hunk('.+.')]));
      cache.scopesOf(_file(path: 'b.dart', hunks: <DiffHunk>[_hunk('.-.')]));

      expect(calls, 2);
    });

    test('splits again when maxGap changes', () {
      final DiffFile file = _file(hunks: <DiffHunk>[_hunk('.+..+.')]);

      final Map<int, List<DiffScope>> merged = cache.scopesOf(file);
      final Map<int, List<DiffScope>> split = cache.scopesOf(file, maxGap: 1);

      expect(calls, 2, reason: 'maxGap is part of the key, not a hint');
      expect(_spans(merged[0]!), <List<int>>[
        <int>[1, 2, 3, 4],
      ]);
      expect(_spans(split[0]!), <List<int>>[
        <int>[1],
        <int>[4],
      ]);
    });

    test('a null file empties the cache without consulting the splitter', () {
      final DiffFile file = _file(hunks: <DiffHunk>[_hunk('.+.')]);
      cache.scopesOf(file);

      expect(cache.scopesOf(null), isEmpty);
      expect(calls, 1);

      // And the same instance coming back is a miss, not a hit -- otherwise a
      // file deselected and reselected would be answered from a map the
      // deselect was supposed to have dropped.
      cache.scopesOf(file);
      expect(calls, 2);
    });
  });

  group('changedIndexLines', () {
    /// A hunk whose lines carry real numbers on both sides.
    DiffHunk numbered(List<(DiffLineKind, int, int)> spec) => DiffHunk(
      oldStart: 1,
      oldCount: spec.length,
      newStart: 1,
      newCount: spec.length,
      heading: '',
      lines: <DiffLine>[
        for (final (DiffLineKind kind, int old, int now) in spec)
          DiffLine(kind: kind, oldLine: old, newLine: now, text: 'x'),
      ],
    );

    // The added line's `newLine` and the removed line's `oldLine` are
    // deliberately *different* numbers. With both at 2 -- which is how this
    // fixture was first written -- the staged and unstaged answers coincide,
    // and a mutation making the function always read the old side stayed
    // green ([TEST-fixture-cannot-disagree]).
    test('a staged diff reports the index lines it adds', () {
      // Staged is HEAD -> index, so its *new* side is the index. An added
      // line puts a line into the index; a removed one takes a HEAD line
      // away and leaves no index line behind, so it cannot be a barrier --
      // there is nothing at that coordinate for another diff to collide
      // with.
      final DiffFile file = _file(
        hunks: <DiffHunk>[
          numbered(<(DiffLineKind, int, int)>[
            (DiffLineKind.context, 1, 1),
            (DiffLineKind.added, 0, 5),
            (DiffLineKind.removed, 9, 0),
          ]),
        ],
      );
      expect(changedIndexLines(file, staged: true), <int>{5});
    });

    test('an unstaged diff reports the index lines it removes', () {
      // The mirror: unstaged is index -> worktree, so its *old* side is the
      // index and an added line has no index coordinate at all.
      final DiffFile file = _file(
        hunks: <DiffHunk>[
          numbered(<(DiffLineKind, int, int)>[
            (DiffLineKind.context, 1, 1),
            (DiffLineKind.added, 0, 5),
            (DiffLineKind.removed, 9, 0),
          ]),
        ],
      );
      expect(changedIndexLines(file, staged: false), <int>{9});
    });

    test('a null or binary file has no barriers', () {
      expect(changedIndexLines(null, staged: true), isEmpty);
      expect(changedIndexLines(_file(binary: true), staged: true), isEmpty);
    });
  });

  group('IndexBarriers.ofChanges', () {
    test(
      'keys every changed row, offset-1 rows included, sorted with rank',
      () {
        // A staged hunk: index line 4 added, then a HEAD-only line deleted
        // after it (no index number -> (4, 1)); an unstaged hunk removing
        // index line 2. Context rows contribute nothing.
        final IndexBarriers barriers = IndexBarriers.ofChanges(<DiffSide>[
          (
            file: _file(
              hunks: <DiffHunk>[
                DiffHunk(
                  oldStart: 3,
                  oldCount: 2,
                  newStart: 3,
                  newCount: 2,
                  heading: '',
                  lines: <DiffLine>[
                    DiffLine(
                      kind: DiffLineKind.context,
                      oldLine: 3,
                      newLine: 3,
                      text: 'c',
                    ),
                    DiffLine(
                      kind: DiffLineKind.added,
                      oldLine: 0,
                      newLine: 4,
                      text: 'a',
                    ),
                    DiffLine(
                      kind: DiffLineKind.removed,
                      oldLine: 4,
                      newLine: 0,
                      text: 'd',
                    ),
                  ],
                ),
              ],
            ),
            staged: true,
          ),
          (
            file: _file(
              hunks: <DiffHunk>[
                DiffHunk(
                  oldStart: 2,
                  oldCount: 1,
                  newStart: 2,
                  newCount: 0,
                  heading: '',
                  lines: <DiffLine>[
                    DiffLine(
                      kind: DiffLineKind.removed,
                      oldLine: 2,
                      newLine: 0,
                      text: 'r',
                    ),
                  ],
                ),
              ],
            ),
            staged: false,
          ),
        ]);

        expect(barriers.keys, <IndexKey>[
          (line: 2, offset: 0, rank: 0),
          (line: 4, offset: 0, rank: 1),
          (line: 4, offset: 1, rank: 1),
        ]);
      },
    );

    test('at an equal position the unstaged rank sorts first', () {
      // The tie the merged list breaks unstaged-first; [indexRankOf] is the
      // number, compareIndexKeys is the only place it is read.
      expect(
        compareIndexKeys(
          (line: 10, offset: 1, rank: indexRankOf(staged: false)),
          (line: 10, offset: 1, rank: indexRankOf(staged: true)),
        ),
        lessThan(0),
      );
    });

    test('no change anywhere is the shared none instance', () {
      expect(
        identical(
          IndexBarriers.ofChanges(<DiffSide>[(file: null, staged: true)]),
          IndexBarriers.none,
        ),
        isTrue,
      );
    });
  });

  group('DiffBarrierMemo', () {
    /// A file whose one hunk changes exactly the index lines in [indexLines].
    ///
    /// `staged` picks which side carries them, so the two sides of a pair
    /// can be built from the same helper and still disagree about what a
    /// barrier is.
    DiffFile at(List<int> indexLines, {required bool staged}) => _file(
      hunks: <DiffHunk>[
        DiffHunk(
          oldStart: 1,
          oldCount: indexLines.length,
          newStart: 1,
          newCount: indexLines.length,
          heading: '',
          lines: <DiffLine>[
            for (final int line in indexLines)
              DiffLine(
                // Staged is HEAD -> index, so an *added* line is what puts
                // one into the index; unstaged is index -> worktree, so a
                // *removed* one is what takes an index line away. Either
                // way the index-side number is `line`.
                kind: staged ? DiffLineKind.added : DiffLineKind.removed,
                oldLine: staged ? 0 : line,
                newLine: staged ? line : 0,
                text: 'x',
              ),
          ],
        ),
      ],
    );

    test('each side gets the other side\'s changed index lines', () {
      final DiffBarrierMemo memo = DiffBarrierMemo();
      final List<IndexBarriers> barriers = memo.barriersFor(<DiffSide>[
        (file: at(<int>[3], staged: false), staged: false),
        (file: at(<int>[7], staged: true), staged: true),
      ]);

      // Not its own: a side never blocks itself, or every change would end
      // its own scope.
      expect(barriers[0].keys, <IndexKey>[(line: 7, offset: 0, rank: 1)]);
      expect(barriers[1].keys, <IndexKey>[(line: 3, offset: 0, rank: 0)]);
    });

    test('the same files hand back the same set instances', () {
      final DiffBarrierMemo memo = DiffBarrierMemo();
      final DiffFile unstaged = at(<int>[3], staged: false);
      final DiffFile staged = at(<int>[7], staged: true);
      List<DiffSide> sides() => <DiffSide>[
        (file: unstaged, staged: false),
        (file: staged, staged: true),
      ];

      final List<IndexBarriers> first = memo.barriersFor(sides());
      final List<IndexBarriers> second = memo.barriersFor(sides());

      // Identity, not equality: DiffScopeCache keys on `identical`, so an
      // equal-but-new set re-splits every frame and this memo buys nothing.
      expect(identical(first[0], second[0]), isTrue);
      expect(identical(first[1], second[1]), isTrue);
    });

    test('a new file on either side recomputes', () {
      final DiffBarrierMemo memo = DiffBarrierMemo();
      final DiffFile unstaged = at(<int>[3], staged: false);

      final List<IndexBarriers> first = memo.barriersFor(<DiffSide>[
        (file: unstaged, staged: false),
        (file: at(<int>[7], staged: true), staged: true),
      ]);
      final List<IndexBarriers> second = memo.barriersFor(<DiffSide>[
        (file: unstaged, staged: false),
        (file: at(<int>[8], staged: true), staged: true),
      ]);

      expect(first[0].keys, <IndexKey>[(line: 7, offset: 0, rank: 1)]);
      expect(second[0].keys, <IndexKey>[(line: 8, offset: 0, rank: 1)]);
    });

    test('a flipped staged flag recomputes, on the same file', () {
      // The same DiffFile read as the other direction reports different
      // index lines, so identity of the file alone is not the whole key.
      final DiffBarrierMemo memo = DiffBarrierMemo();
      final DiffFile both = _file(
        hunks: <DiffHunk>[
          DiffHunk(
            oldStart: 1,
            oldCount: 2,
            newStart: 1,
            newCount: 2,
            heading: '',
            lines: <DiffLine>[
              DiffLine(
                kind: DiffLineKind.added,
                oldLine: 0,
                newLine: 5,
                text: 'x',
              ),
              DiffLine(
                kind: DiffLineKind.removed,
                oldLine: 9,
                newLine: 0,
                text: 'y',
              ),
            ],
          ),
        ],
      );

      expect(
        memo.barriersFor(<DiffSide>[
          (file: null, staged: false),
          (file: both, staged: true),
        ])[0].keys,
        <IndexKey>[
          (line: 5, offset: 0, rank: 1),
          (line: 5, offset: 1, rank: 1),
        ],
      );
      expect(
        memo.barriersFor(<DiffSide>[
          (file: null, staged: false),
          (file: both, staged: false),
        ])[0].keys,
        <IndexKey>[
          (line: 0, offset: 1, rank: 0),
          (line: 9, offset: 0, rank: 0),
        ],
      );
    });

    test('a lone side gets the const empty set, not a fresh one', () {
      final DiffBarrierMemo memo = DiffBarrierMemo();
      final DiffFile only = at(<int>[3], staged: false);

      final List<IndexBarriers> first = memo.barriersFor(<DiffSide>[
        (file: only, staged: false),
      ]);
      // A fresh empty IndexBarriers would be equal and not identical, so the cache
      // below it would miss on every build -- the `2 file` mode's own case.
      expect(identical(first[0], IndexBarriers.none), isTrue);
    });
  });

  group('splitDiffFileIntoScopes -- barriers', () {
    // The reported case: the unstaged hunk of an untracked file whose middle
    // line is staged. `document` is a context line here and index line 1, so
    // the staged side's own change at index line 1 is what must stop the gap
    // rule folding alpha/bravo and delta/echo into one card.
    DiffFile untrackedUnstaged() => _file(
      hunks: <DiffHunk>[
        DiffHunk(
          oldStart: 1,
          oldCount: 1,
          newStart: 1,
          newCount: 5,
          heading: '',
          lines: <DiffLine>[
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 1,
              text: 'alpha',
            ),
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 2,
              text: 'bravo',
            ),
            DiffLine(
              kind: DiffLineKind.context,
              oldLine: 1,
              newLine: 3,
              text: 'document',
            ),
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 4,
              text: 'delta',
            ),
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 5,
              text: 'echo',
            ),
          ],
        ),
      ],
    );

    test('with no barrier the four additions are one scope', () {
      expect(splitDiffFileIntoScopes(untrackedUnstaged())[0], hasLength(1));
    });

    test('the staged side\'s index line splits them into two', () {
      expect(
        splitDiffFileIntoScopes(
          untrackedUnstaged(),
          staged: false,
          barriers: _stagedAdds(<int>[1]),
        )[0],
        hasLength(2),
      );
    });

    test('a barrier naming an index line this hunk does not hold is inert', () {
      expect(
        splitDiffFileIntoScopes(
          untrackedUnstaged(),
          staged: false,
          barriers: _stagedAdds(<int>[99]),
        )[0],
        hasLength(1),
      );
    });

    test('reading the wrong side finds no barrier at all', () {
      // `staged: true` would look at `newLine`, where index line 1 is the
      // *first* row rather than the context one -- and a barrier on a
      // changed line does nothing. So the side matters, and getting it
      // wrong fails silently rather than loudly.
      expect(
        splitDiffFileIntoScopes(
          untrackedUnstaged(),
          staged: true,
          barriers: _stagedAdds(<int>[1]),
        )[0],
        hasLength(1),
      );
    });
  });

  group('indexPositionOf', () {
    // The unstaged diff is index -> worktree, so its *old* side is the index;
    // the staged diff is HEAD -> index, so its *new* side is. That shared
    // ruler is the whole reason one merged list can be ordered by region
    // without a third git call (U1).
    DiffHunk hunkAt({required int oldStart, required int newStart}) => DiffHunk(
      oldStart: oldStart,
      oldCount: 3,
      newStart: newStart,
      newCount: 3,
      heading: '',
      lines: <DiffLine>[
        DiffLine(
          kind: DiffLineKind.context,
          oldLine: oldStart,
          newLine: newStart,
          text: 'ctx',
        ),
        DiffLine(
          kind: DiffLineKind.added,
          oldLine: 0,
          newLine: newStart + 1,
          text: 'new',
        ),
        DiffLine(
          kind: DiffLineKind.removed,
          oldLine: oldStart + 1,
          newLine: 0,
          text: 'gone',
        ),
      ],
    );

    test('reads the old side for an unstaged diff', () {
      final DiffHunk hunk = hunkAt(oldStart: 10, newStart: 90);
      expect(indexPositionOf(hunk, 0, staged: false), (line: 10, offset: 0));
      // An added line has no old side at all (oldLine == 0), so it does not
      // *occupy* an index line -- it sits between two. `offset: 1` is what
      // says so, and it is the whole difference between「是第 10 行」and
      //「夾在第 10 行後面」. Reading the zero literally would sort every
      // insertion to the top of the file; collapsing it onto 10 with no
      // offset (which is what this used to do) makes it tie with the line
      // itself, so a card from the other diff sitting *on* index line 10
      // could no longer be ordered between them.
      expect(indexPositionOf(hunk, 1, staged: false), (line: 10, offset: 1));
      expect(indexPositionOf(hunk, 2, staged: false), (line: 11, offset: 0));
    });

    test('reads the new side for a staged diff', () {
      final DiffHunk hunk = hunkAt(oldStart: 10, newStart: 90);
      expect(indexPositionOf(hunk, 0, staged: true), (line: 90, offset: 0));
      expect(indexPositionOf(hunk, 1, staged: true), (line: 91, offset: 0));
      // Mirror of the case above: a removed line has no new side.
      expect(indexPositionOf(hunk, 2, staged: true), (line: 91, offset: 1));
    });

    test('a hunk whose first line has no number sits before the start', () {
      // A pure insertion hunk -- `@@ -0,0 +1,2 @@` -- has no old side
      // anywhere in it, so nothing in the loop can supply a line number.
      // These rows land *before* the hunk's first index line, which is
      // `oldStart - 1` with an offset, not `oldStart` itself.
      final DiffHunk hunk = DiffHunk(
        oldStart: 7,
        oldCount: 0,
        newStart: 1,
        newCount: 2,
        heading: '',
        lines: <DiffLine>[
          DiffLine(kind: DiffLineKind.added, oldLine: 0, newLine: 1, text: 'a'),
          DiffLine(kind: DiffLineKind.added, oldLine: 0, newLine: 2, text: 'b'),
        ],
      );
      expect(indexPositionOf(hunk, 0, staged: false), (line: 6, offset: 1));
      expect(indexPositionOf(hunk, 1, staged: false), (line: 6, offset: 1));
    });

    // The reported case, measured in a real repository: a 5-line untracked
    // file whose middle line is staged. `git diff` answers
    // `@@ -1 +1,5 @@ +alpha +bravo ' document' +delta +echo`, and
    // `git diff --cached` answers `@@ -0,0 +1 @@ +document`.
    //
    // Every one of those six rows reported the *same* position 1 before this
    // change, so the sort had nothing to order by and the staged card could
    // only land wherever source order put it -- last, not between the two
    // unstaged runs it belongs between.
    test('an untracked file with its middle line staged orders in three', () {
      final DiffHunk unstaged = DiffHunk(
        oldStart: 1,
        oldCount: 1,
        newStart: 1,
        newCount: 5,
        heading: '',
        lines: <DiffLine>[
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: 0,
            newLine: 1,
            text: 'alpha',
          ),
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: 0,
            newLine: 2,
            text: 'bravo',
          ),
          DiffLine(
            kind: DiffLineKind.context,
            oldLine: 1,
            newLine: 3,
            text: 'document',
          ),
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: 0,
            newLine: 4,
            text: 'delta',
          ),
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: 0,
            newLine: 5,
            text: 'echo',
          ),
        ],
      );
      final DiffHunk staged = DiffHunk(
        oldStart: 0,
        oldCount: 0,
        newStart: 1,
        newCount: 1,
        heading: '',
        lines: <DiffLine>[
          DiffLine(
            kind: DiffLineKind.added,
            oldLine: 0,
            newLine: 1,
            text: 'document',
          ),
        ],
      );

      expect(indexPositionOf(unstaged, 0, staged: false), (line: 0, offset: 1));
      expect(indexPositionOf(unstaged, 1, staged: false), (line: 0, offset: 1));
      expect(indexPositionOf(unstaged, 2, staged: false), (line: 1, offset: 0));
      expect(indexPositionOf(unstaged, 3, staged: false), (line: 1, offset: 1));
      expect(indexPositionOf(unstaged, 4, staged: false), (line: 1, offset: 1));
      // The staged card sits *on* index line 1, so it sorts after the two
      // rows inserted before it and before the two inserted after it.
      expect(indexPositionOf(staged, 0, staged: true), (line: 1, offset: 0));
    });
  });
}
