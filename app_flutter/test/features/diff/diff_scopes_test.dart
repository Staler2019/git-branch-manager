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

List<List<int>> _spans(List<DiffScope> scopes) =>
    scopes.map((DiffScope s) => s.lineIndices).toList(growable: false);

List<List<int>> _changed(List<DiffScope> scopes) =>
    scopes.map((DiffScope s) => s.changedLineIndices).toList(growable: false);

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

  group('hunkSegments', () {
    List<String> shape(List<DiffSegment> segments) => segments
        .map(
          (DiffSegment s) => switch (s) {
            DiffGapSegment() => 'gap${s.lineIndices}',
            DiffScopeSegment(:final int ordinal) =>
              'scope$ordinal${s.lineIndices}',
          },
        )
        .toList(growable: false);

    List<DiffSegment> segmentsOf(String sketch, {int firstOrdinal = 1}) {
      final DiffHunk hunk = _hunk(sketch);
      return hunkSegments(
        hunk,
        splitHunkIntoScopes(hunk),
        firstOrdinal: firstOrdinal,
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
        'scope1[2]',
        'gap[3, 4, 5]',
        'scope2[6]',
        'gap[7, 8]',
      ]);
    });

    test('a scope touching the start or the end of the hunk has no gap beside '
        'it', () {
      expect(shape(segmentsOf('+..')), <String>['scope1[0]', 'gap[1, 2]']);
      expect(shape(segmentsOf('..+')), <String>['gap[0, 1]', 'scope1[2]']);
      expect(shape(segmentsOf('+')), <String>['scope1[0]']);
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
        'scope1[1, 2, 3, 4]',
        'gap[5]',
      ]);
    });

    test('firstOrdinal continues the numbering instead of restarting it', () {
      // Cards are numbered per file, not per hunk, so 變更 N is unique in the
      // pane -- the second hunk's first card must not also say 變更 1.
      expect(shape(segmentsOf('+...+', firstOrdinal: 4)), <String>[
        'scope4[0]',
        'gap[1, 2, 3]',
        'scope5[4]',
      ]);
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
}
