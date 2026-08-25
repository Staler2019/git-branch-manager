// Render-site tests for spec P03 變體 B's scope cards. The split itself is
// pure and tested in `diff_scopes_test.dart`; what this file checks is that
// each card's button exists from the start, says how many lines it moves,
// and hands `gbm_stage_lines` exactly those lines -- never the unchanged
// context the gap rule swallowed into the same card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';

import '../../support/pump_app.dart';

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
          _ => DiffLineKind.context,
        },
        oldLine: i + 1,
        newLine: i + 1,
        text: 'line $i',
      ),
  ],
);

DiffFile _file(List<String> sketches, {bool binary = false}) => DiffFile(
  oldPath: 'lib/a.dart',
  newPath: 'lib/a.dart',
  kind: FileChangeKind.modified,
  oldMode: '',
  newMode: '',
  oldBlob: '',
  newBlob: '',
  binary: binary,
  similarity: 0,
  addedLines: 0,
  removedLines: 0,
  displayPath: 'lib/a.dart',
  hunks: <DiffHunk>[for (final String s in sketches) _hunk(s)],
);

void main() {
  group('ScopedDiffView', () {
    late List<({int hunkIndex, List<int> lines})> staged;
    late List<({int hunkIndex, List<int> lines})> discarded;

    setUp(() {
      staged = <({int hunkIndex, List<int> lines})>[];
      discarded = <({int hunkIndex, List<int> lines})>[];
    });

    Future<void> pump(
      WidgetTester tester, {
      DiffFile? file,
      bool isStaged = false,
      bool loading = false,
      bool discardable = true,
      double width = 420,
    }) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: width,
          child: ScopedDiffView(
            title: isStaged ? 'Staged' : 'Unstaged',
            file: file,
            staged: isStaged,
            loading: loading,
            onStageScope: (int h, List<int> l) =>
                staged.add((hunkIndex: h, lines: l)),
            onDiscardScope: discardable
                ? (int h, List<int> l) =>
                      discarded.add((hunkIndex: h, lines: l))
                : null,
          ),
        ),
      );
    }

    testWidgets('every scope gets its own button, present before anything is '
        'selected', (WidgetTester tester) async {
      // Two changes three context lines apart -> two scopes -> two buttons,
      // with nothing clicked first. The checkbox version showed zero
      // buttons until a line was ticked.
      await pump(tester, file: _file(<String>['.+...+.']));

      expect(find.byType(GbmButton), findsNWidgets(2));
      expect(find.text('變更 1'), findsOneWidget);
      expect(find.text('變更 2'), findsOneWidget);
    });

    testWidgets('the button sends exactly the lines that move, not the '
        'context the gap rule swallowed', (WidgetTester tester) async {
      // '.+..-.' is one card spanning indices 1..4, but only 1 and 4 change.
      await pump(tester, file: _file(<String>['.+..-.']));

      await tester.tap(find.text('Stage 2 lines'));

      expect(staged.length, 1);
      expect(staged.single.hunkIndex, 0);
      expect(
        staged.single.lines,
        <int>[1, 4],
        reason:
            'passing 1..4 would ask git to stage two unchanged lines, which '
            'buildLineSelectionPatch would reject or mis-apply',
      );
    });

    testWidgets('the label counts moving lines and singularises at one', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(<String>['.+.']));
      expect(find.text('Stage 1 line'), findsOneWidget);
    });

    testWidgets('the staged side unstages instead of staging', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(<String>['.+-.']), isStaged: true);

      expect(find.text('Unstage 2 lines'), findsOneWidget);
      expect(find.text('Stage 2 lines'), findsNothing);
    });

    testWidgets('scope numbering continues across hunks', (
      WidgetTester tester,
    ) async {
      // A per-hunk counter would draw 變更 1 twice, so "the second one" would
      // name two different cards in the same column.
      await pump(tester, file: _file(<String>['.+.', '.-.']));

      expect(find.text('變更 1'), findsOneWidget);
      expect(find.text('變更 2'), findsOneWidget);
    });

    testWidgets('the head counts the cards below it', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(<String>['.+...+.', '.-.']));
      expect(find.text('3 個 scope'), findsOneWidget);
    });

    testWidgets('a hunk index reaches the callback unshifted', (
      WidgetTester tester,
    ) async {
      // gbm_stage_lines takes a hunk index; getting it wrong stages a
      // different part of the file with no error anywhere.
      await pump(tester, file: _file(<String>['.+.', '.-.']));

      await tester.tap(find.text('Stage 1 line').first);
      await tester.tap(find.text('Stage 1 line').last);

      expect(staged.map((r) => r.hunkIndex).toList(), <int>[0, 1]);
    });

    testWidgets('a loading side keeps its head and shows a spinner', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: null, loading: true);

      expect(find.text('Unstaged'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      // Deliberately no pumpAndSettle: an indeterminate indicator schedules
      // frames forever (#101).
    });

    testWidgets('a side with nothing on it says so instead of spinning', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: null);

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('No changes'), findsOneWidget);
    });

    testWidgets('a binary file names itself and offers no button', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(const <String>[], binary: true));

      expect(find.textContaining('binary file'), findsOneWidget);
      expect(find.byType(GbmButton), findsNothing);
    });

    testWidgets('the card head keeps its button inside the card at a narrow '
        'width', (WidgetTester tester) async {
      // The bound is the card, not the pane: a button can sit inside a
      // 420px pane while hanging off the 200px card it belongs to.
      await pump(
        tester,
        file: _file(<String>['.+-.']),
        width: GbmLayout.splitterWcColumns.minExtent,
      );

      final Rect button = tester.getRect(find.byType(GbmButton));
      final Rect card = tester.getRect(
        find.byKey(const ValueKey<String>('scope-card-1')),
      );

      // Both edges: Expanded would satisfy "does not stick out to the
      // right" while collapsing the button to nothing.
      expect(button.left, greaterThanOrEqualTo(card.left - 0.01));
      expect(button.right, lessThanOrEqualTo(card.right + 0.01));
      expect(
        button.width,
        greaterThan(0),
        reason: 'a zero-width button is not a button that fits',
      );
      expect(tester.getRect(find.text('變更 1')).width, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });
}
