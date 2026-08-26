// SideBySideDiffView under the two wrap modes.
//
// This surface arrived from main *after* the soft-wrap round started, with a
// doc comment that read 「Lines wrap, exactly as DiffPage's do」 -- true when
// it was written and false by the time the two branches met, because DiffPage
// stopped wrapping by default. Bringing it in line is what closes 「有關 file
// 的都要」 over the merged tree.
//
// **No pinned gutter here, and that is a decision rather than an omission.**
// Two columns mean two line-number gutters, and only the left one is at the
// viewport's left edge. Pinning that one alone would make the two columns
// disagree about where their numbers live -- the left column's numbers frozen
// while the right column's slide -- which reads as a broken layout rather
// than a helpful one. So both gutters scroll with their own column, the pair
// stays aligned, and `GbmPinnedGutter` is deliberately absent.
//
// Widths are test-font units (`flutter_test` draws every glyph `fontSize`
// wide), so the fixture overflows far more readily than the same string would
// in JetBrains Mono -- the safe direction for a test that needs the overflow.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/side_by_side_diff_view.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/features/diff/widgets/side_by_side_cell.dart';
import 'package:gbm_flutter/widgets/code_line_metrics.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _longLine =
    'const result = compute(alpha, beta, gamma, delta, epsilon, zeta, eta);';

ParsedDiff _diff(String text, {String suffix = ' // and then some'}) =>
    ParsedDiff(
      truncated: false,
      inputBytes: 0,
      files: <DiffFile>[
        DiffFile(
          oldPath: 'lib/a.dart',
          newPath: 'lib/a.dart',
          kind: FileChangeKind.modified,
          oldMode: '',
          newMode: '',
          oldBlob: '',
          newBlob: '',
          binary: false,
          similarity: 0,
          addedLines: 1,
          removedLines: 1,
          displayPath: 'lib/a.dart',
          hunks: <DiffHunk>[
            DiffHunk(
              oldStart: 1,
              oldCount: 1,
              newStart: 1,
              newCount: 1,
              heading: '',
              lines: <DiffLine>[
                DiffLine(
                  kind: DiffLineKind.removed,
                  oldLine: 1,
                  newLine: 0,
                  text: text,
                ),
                DiffLine(
                  kind: DiffLineKind.added,
                  oldLine: 0,
                  newLine: 1,
                  text: '$text$suffix',
                ),
              ],
            ),
          ],
        ),
      ],
    );

Future<void> _pump(
  WidgetTester tester, {
  required bool softWrap,
  String text = _longLine,
  String suffix = ' // and then some',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'appPrefs.softWrapEnabled': softWrap,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 420,
              height: 300,
              child: SideBySideDiffView(diff: _diff(text, suffix: suffix)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Finder _horizontalScroller() => find.byWidgetPredicate(
  (Widget w) =>
      w is SingleChildScrollView && w.scrollDirection == Axis.horizontal,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a pair too wide for the pane scrolls sideways by default', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: false);
    expect(_horizontalScroller(), findsOneWidget);
  });

  testWidgets('turning soft wrap on removes the sideways scroll', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: true);
    expect(_horizontalScroller(), findsNothing);
  });

  testWidgets('a pair that already fits gets no scroller either way', (
    WidgetTester tester,
  ) async {
    // Both lines short, suffix included: the pair's width is twice one
    // column, so a fixture that shortens only the left side still overflows
    // and the test would be asserting the opposite of its own name.
    await _pump(tester, softWrap: false, text: 'x', suffix: '');
    expect(_horizontalScroller(), findsNothing);
  });

  testWidgets('every cell carries the flag, not just the pane', (
    WidgetTester tester,
  ) async {
    // The scroller is a property of the pane; `softWrap` on the code Text is
    // a property of each cell, and the two are set from one read on
    // different widgets. Asserting only the pane leaves the cell flag free
    // to be wrong -- and there are two cells per pair, so a count is what
    // catches one side being missed.
    await _pump(tester, softWrap: false);
    final Iterable<Text> code = tester
        .widgetList<Text>(find.byType(Text))
        .where((Text t) => (t.data ?? '').contains('compute('));
    expect(code, hasLength(2));
    for (final Text t in code) {
      expect(t.softWrap, isFalse);
    }

    await _pump(tester, softWrap: true);
    for (final Text t
        in tester
            .widgetList<Text>(find.byType(Text))
            .where((Text t) => (t.data ?? '').contains('compute('))) {
      expect(t.softWrap, isTrue);
    }
  });

  testWidgets('the well is wide enough for both columns, not one', (
    WidgetTester tester,
  ) async {
    // The oracle is measured here rather than restated from the widget: a
    // cell that is only half as wide as it should be still produces a
    // scroller and still overflows the pane, so every other test in this
    // file passes with the pair width computed for one column. What it does
    // *not* do is leave room for the line -- with `softWrap: false` inside
    // an `Expanded` the paragraph takes its parent's width, so the rendered
    // Text is measurably narrower than the text it holds.
    await _pump(tester, softWrap: false);

    final double widest = widestLineWidth(
      '$_longLine // and then some',
      kSideBySideCodeTextStyle,
    );
    for (final String shown in <String>[
      _longLine,
      '$_longLine // and then some',
    ]) {
      expect(
        tester.getRect(find.text(shown)).width,
        greaterThanOrEqualTo(widest - 1),
        reason: 'this column has to fit the longest line in the pair',
      );
    }
  });

  testWidgets('neither column pins its gutter', (WidgetTester tester) async {
    await _pump(tester, softWrap: false);
    expect(
      find.byType(GbmPinnedGutter),
      findsNothing,
      reason:
          'only one of the two gutters is at the viewport edge; pinning that '
          'one alone would desynchronise the pair (see this file\'s header)',
    );
  });
}
