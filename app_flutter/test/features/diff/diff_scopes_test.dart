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
    // A barrier is a hunk line the gap rule may not swallow. In the merged
    // `unified` list it is a line the *other* diff draws as a change of its
    // own, so folding across it would put one card's span over another
    // card's position -- and that is exactly the reported defect: an
    // untracked file whose middle line is staged drew two cards where git
    // sees three regions.
    test('a barrier between two changes splits them, inside the gap', () {
      // `+ + . + +` -- one unchanged line, well inside the gap rule's 2.
      final DiffHunk hunk = _hunk('++.++');
      expect(splitHunkIntoScopes(hunk), hasLength(1));
      expect(splitHunkIntoScopes(hunk, barriers: const <int>{2}), hasLength(2));
    });

    test('the barrier line itself stays out of both scopes', () {
      final List<DiffScope> scopes = splitHunkIntoScopes(
        _hunk('++.++'),
        barriers: const <int>{2},
      );
      expect(scopes[0].lineIndices, <int>[0, 1]);
      expect(scopes[1].lineIndices, <int>[3, 4]);
    });

    test('a barrier outside every gap changes nothing', () {
      // Leading context is already outside every scope, so naming it a
      // barrier cannot split anything -- the split must come from the gap
      // between two changes, not from the barrier's mere presence.
      final DiffHunk hunk = _hunk('.++++');
      expect(splitHunkIntoScopes(hunk, barriers: const <int>{0}), hasLength(1));
    });

    test('a barrier on a changed line does not split its own run', () {
      // The rule is「the gap rule may not *swallow* a barrier」, not「a
      // barrier ends a scope」. A changed line is not swallowed context, and
      // splitting a run of real changes there would fragment the commonest
      // case -- staging part of a block -- for no gain: both sides already
      // get their own card at that position.
      expect(
        splitHunkIntoScopes(_hunk('+++'), barriers: const <int>{1}),
        hasLength(1),
      );
    });
  });

  group('hunkSegments', () {
    List<String> shape(List<DiffSegment> segments) => segments
        .map(
          (DiffSegment s) => switch (s) {
            DiffGapSegment() => 'gap${s.lineIndices}',
            DiffScopeSegment() => 'scope${s.lineIndices}',
          },
        )
        .toList(growable: false);

    List<DiffSegment> segmentsOf(String sketch) {
      final DiffHunk hunk = _hunk(sketch);
      return hunkSegments(hunk, splitHunkIntoScopes(hunk));
    }

    List<DiffSegment> segmentsHiding(String sketch, Set<int> hidden) {
      final DiffHunk hunk = _hunk(sketch);
      return hunkSegments(
        hunk,
        splitHunkIntoScopes(hunk, barriers: hidden),
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
              Set<int> barrierIndexLines = const <int>{},
            }) {
              calls++;
              return splitDiffFileIntoScopes(
                file,
                maxGap: maxGap,
                staged: staged,
                barrierIndexLines: barrierIndexLines,
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
        barrierIndexLines: <int>{0},
      );

      expect(calls, 2, reason: 'the barrier set is part of the key');
      expect(withBarrier[0], isNotNull);
    });

    test('the same barrier set instance hits', () {
      final DiffFile file = _file(hunks: <DiffHunk>[_hunk('++.++')]);
      final Set<int> barriers = <int>{0};

      cache.scopesOf(file, staged: false, barrierIndexLines: barriers);
      cache.scopesOf(file, staged: false, barrierIndexLines: barriers);

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
          barrierIndexLines: const <int>{1},
        )[0],
        hasLength(2),
      );
    });

    test('a barrier naming an index line this hunk does not hold is inert', () {
      expect(
        splitDiffFileIntoScopes(
          untrackedUnstaged(),
          staged: false,
          barrierIndexLines: const <int>{99},
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
          barrierIndexLines: const <int>{1},
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
