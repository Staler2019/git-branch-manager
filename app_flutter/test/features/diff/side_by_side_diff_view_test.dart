// SideBySideDiffView's render contract. The pairing itself is proved in
// `side_by_side_diff_test.dart` against the pure function; what this file
// checks is what the widget does with those pairs -- which side a number is
// read off, and that the two columns really stay level.
//
// Three of these tests exist because the version restored from 7abb728^ got
// them wrong, and no test at any tier could have said so:
//   - a context line's number was `kind == removed ? oldLine : newLine`, so
//     the *left* column showed the *new* number for every unchanged line;
//   - a blank padding cell was a fixed `height: 20`, so it stopped short of
//     a wrapped line opposite it;
//   - there was no SelectionArea, so the diff could not be dragged over.
// Rects are asserted against the paired cell rather than against pixel
// constants: "the two columns are level" is the requirement, and a finder
// proves existence, never position.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/side_by_side_diff_view.dart';
import 'package:gbm_flutter/features/diff/widgets/side_by_side_cell.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

DiffLine _context(String text, {required int oldLine, required int newLine}) =>
    DiffLine(
      kind: DiffLineKind.context,
      oldLine: oldLine,
      newLine: newLine,
      text: text,
    );

DiffLine _removed(String text, {int oldLine = 1}) => DiffLine(
  kind: DiffLineKind.removed,
  oldLine: oldLine,
  newLine: 0,
  text: text,
);

DiffLine _added(String text, {int newLine = 1}) => DiffLine(
  kind: DiffLineKind.added,
  oldLine: 0,
  newLine: newLine,
  text: text,
);

ParsedDiff _diffOf(
  List<DiffLine> lines, {
  int oldStart = 1,
  int newStart = 1,
  bool binary = false,
}) => ParsedDiff(
  files: <DiffFile>[
    DiffFile(
      oldPath: 'a.txt',
      newPath: 'a.txt',
      kind: FileChangeKind.modified,
      oldMode: '100644',
      newMode: '100644',
      oldBlob: 'aaa',
      newBlob: 'bbb',
      binary: binary,
      similarity: 0,
      addedLines: 0,
      removedLines: 0,
      displayPath: 'a.txt',
      hunks: <DiffHunk>[
        DiffHunk(
          oldStart: oldStart,
          oldCount: lines.length,
          newStart: newStart,
          newCount: lines.length,
          heading: '',
          lines: lines,
        ),
      ],
    ),
  ],
  truncated: false,
  inputBytes: 0,
);

Future<void> _pump(WidgetTester tester, ParsedDiff diff) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(body: SideBySideDiffView(diff: diff)),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _cell(SideBySideSide side, {String? text}) => find.byWidgetPredicate(
  (Widget w) =>
      w is SideBySideCell &&
      w.side == side &&
      (text == null || w.line?.text == text),
);

void main() {
  group('SideBySideDiffView', () {
    testWidgets('a paired left and right cell stay exactly level', (
      tester,
    ) async {
      await _pump(tester, _diffOf(<DiffLine>[_removed('old'), _added('new')]));

      final Rect left = tester.getRect(_cell(SideBySideSide.left, text: 'old'));
      final Rect right = tester.getRect(
        _cell(SideBySideSide.right, text: 'new'),
      );

      // Same row: not "roughly aligned", identical top and bottom.
      expect(left.top, right.top);
      expect(left.bottom, right.bottom);
      // Left really is the left one -- a ratio-only claim would still hold
      // with the two columns swapped.
      expect(left.right, lessThanOrEqualTo(right.left));
    });

    testWidgets('a blank padding cell matches the height of a wrapped line '
        'opposite it', (tester) async {
      // The restored version pinned the blank cell to `height: 20`. A long
      // line wraps at the default 800px canvas (halved, minus the gutter),
      // so the real row is several lines tall and the constant fell short.
      final String long = List<String>.filled(60, 'wrap').join(' ');
      await _pump(tester, _diffOf(<DiffLine>[_removed(long)]));

      final Rect left = tester.getRect(_cell(SideBySideSide.left, text: long));
      final Rect right = tester.getRect(_cell(SideBySideSide.right));

      expect(left.height, greaterThan(20));
      expect(right.top, left.top);
      expect(right.bottom, left.bottom);
    });

    testWidgets('a pure addition leaves the left cell blank', (tester) async {
      await _pump(
        tester,
        _diffOf(<DiffLine>[
          _context('keep', oldLine: 1, newLine: 1),
          _added('added1'),
        ]),
      );

      // Exactly one blank left cell: the one opposite the addition.
      final Iterable<SideBySideCell> blanks = tester
          .widgetList<SideBySideCell>(_cell(SideBySideSide.left))
          .where((SideBySideCell c) => c.line == null);
      expect(blanks.length, 1);
      expect(
        tester
            .widget<SideBySideCell>(_cell(SideBySideSide.right, text: 'added1'))
            .line,
        isNotNull,
      );
    });

    testWidgets('a pure deletion leaves the right cell blank', (tester) async {
      await _pump(
        tester,
        _diffOf(<DiffLine>[
          _context('keep', oldLine: 1, newLine: 1),
          _removed('removed1'),
        ]),
      );

      final Iterable<SideBySideCell> blanks = tester
          .widgetList<SideBySideCell>(_cell(SideBySideSide.right))
          .where((SideBySideCell c) => c.line == null);
      expect(blanks.length, 1);
    });

    testWidgets('a context line shows the old number left and the new number '
        'right', (tester) async {
      // The whole point of the fix: with oldStart != newStart the two numbers
      // for one unchanged line differ, and the restored version showed the
      // new one on both sides.
      await _pump(
        tester,
        _diffOf(
          <DiffLine>[_context('keep', oldLine: 10, newLine: 20)],
          oldStart: 10,
          newStart: 20,
        ),
      );

      expect(
        find.descendant(
          of: _cell(SideBySideSide.left, text: 'keep'),
          matching: find.text('10'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _cell(SideBySideSide.right, text: 'keep'),
          matching: find.text('20'),
        ),
        findsOneWidget,
      );
      // And the wrong number is on neither side.
      expect(
        find.descendant(
          of: _cell(SideBySideSide.left, text: 'keep'),
          matching: find.text('20'),
        ),
        findsNothing,
      );
    });

    testWidgets('a removed line numbers only the left, an added only the '
        'right', (tester) async {
      await _pump(
        tester,
        _diffOf(<DiffLine>[
          _removed('old', oldLine: 7),
          _added('new', newLine: 9),
        ]),
      );

      expect(
        find.descendant(
          of: _cell(SideBySideSide.left, text: 'old'),
          matching: find.text('7'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _cell(SideBySideSide.right, text: 'new'),
          matching: find.text('9'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the list is inside a SelectionArea', (tester) async {
      await _pump(tester, _diffOf(<DiffLine>[_removed('old'), _added('new')]));

      expect(
        find.ancestor(
          of: find.byType(SideBySideCell).first,
          matching: find.byType(SelectionArea),
        ),
        findsOneWidget,
      );
    });

    testWidgets('a binary file says so instead of rendering cells', (
      tester,
    ) async {
      await _pump(tester, _diffOf(<DiffLine>[], binary: true));

      expect(find.textContaining('binary'), findsOneWidget);
      expect(find.byType(SideBySideCell), findsNothing);
    });

    testWidgets('an empty diff says there are no changes', (tester) async {
      await _pump(
        tester,
        const ParsedDiff(files: <DiffFile>[], truncated: false, inputBytes: 0),
      );

      expect(find.text('No changes'), findsOneWidget);
    });
  });
}
