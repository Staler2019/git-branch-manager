import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/features/diff/side_by_side_diff.dart';

// Mirrors tests/unit/SideBySideDiffTest.cpp's cases one for one -- see
// pairHunkForSideBySide's doc comment in side_by_side_diff.dart for why this
// Dart port exists and needs to stay in lockstep with the core original.

DiffLine context(String text) =>
    DiffLine(kind: DiffLineKind.context, oldLine: 1, newLine: 1, text: text);
DiffLine removed(String text) =>
    DiffLine(kind: DiffLineKind.removed, oldLine: 1, newLine: 0, text: text);
DiffLine added(String text) =>
    DiffLine(kind: DiffLineKind.added, oldLine: 0, newLine: 1, text: text);

DiffHunk hunkOf(List<DiffLine> lines) => DiffHunk(
  oldStart: 1,
  oldCount: 1,
  newStart: 1,
  newCount: 1,
  heading: '',
  lines: lines,
);

void main() {
  test('context lines pass straight across unchanged', () {
    final DiffHunk hunk = hunkOf(<DiffLine>[
      context('one'),
      removed('two'),
      added('TWO'),
      context('three'),
    ]);
    final List<SideBySideRow> rows = pairHunkForSideBySide(hunk);

    expect(rows.length, 3);
    expect(rows[0].left, same(rows[0].right));
    expect(rows[0].left!.text, 'one');
    expect(rows[2].left, same(rows[2].right));
    expect(rows[2].left!.text, 'three');
  });

  test('pairs an equal-length replace line by line', () {
    final DiffHunk hunk = hunkOf(<DiffLine>[
      removed('old1'),
      removed('old2'),
      added('new1'),
      added('new2'),
    ]);
    final List<SideBySideRow> rows = pairHunkForSideBySide(hunk);

    expect(rows.length, 2);
    expect(rows[0].left!.text, 'old1');
    expect(rows[0].right!.text, 'new1');
    expect(rows[1].left!.text, 'old2');
    expect(rows[1].right!.text, 'new2');
  });

  test('a pure addition leaves the left side blank', () {
    final DiffHunk hunk = hunkOf(<DiffLine>[
      context('keep'),
      added('added1'),
      added('added2'),
    ]);
    final List<SideBySideRow> rows = pairHunkForSideBySide(hunk);

    expect(rows.length, 3);
    expect(rows[1].left, isNull);
    expect(rows[1].right!.text, 'added1');
    expect(rows[2].left, isNull);
    expect(rows[2].right!.text, 'added2');
  });

  test('a pure deletion leaves the right side blank', () {
    final DiffHunk hunk = hunkOf(<DiffLine>[
      context('keep'),
      removed('removed1'),
      removed('removed2'),
    ]);
    final List<SideBySideRow> rows = pairHunkForSideBySide(hunk);

    expect(rows.length, 3);
    expect(rows[1].left!.text, 'removed1');
    expect(rows[1].right, isNull);
    expect(rows[2].left!.text, 'removed2');
    expect(rows[2].right, isNull);
  });

  test('an unequal replace pads the shorter side rather than misaligning', () {
    final DiffHunk hunk = hunkOf(<DiffLine>[
      removed('old1'),
      removed('old2'),
      removed('old3'),
      added('new1'),
    ]);
    final List<SideBySideRow> rows = pairHunkForSideBySide(hunk);

    expect(rows.length, 3);
    expect(rows[0].left!.text, 'old1');
    expect(rows[0].right!.text, 'new1');
    expect(rows[1].left!.text, 'old2');
    expect(rows[1].right, isNull);
    expect(rows[2].left!.text, 'old3');
    expect(rows[2].right, isNull);
  });

  test('handles multiple changed regions in one hunk independently', () {
    final DiffHunk hunk = hunkOf(<DiffLine>[
      context('ctx1'),
      removed('a'),
      added('A'),
      context('ctx2'),
      removed('b'),
      added('B'),
    ]);
    final List<SideBySideRow> rows = pairHunkForSideBySide(hunk);

    expect(rows.length, 4);
    expect(rows[0].left!.text, 'ctx1');
    expect(rows[1].left!.text, 'a');
    expect(rows[1].right!.text, 'A');
    expect(rows[2].left!.text, 'ctx2');
    expect(rows[3].left!.text, 'b');
    expect(rows[3].right!.text, 'B');
  });
}
