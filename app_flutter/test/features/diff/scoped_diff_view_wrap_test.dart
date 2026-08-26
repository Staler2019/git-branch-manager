// ScopedDiffView under the two wrap modes.
//
// The staging behaviour is covered next door in `scoped_diff_view_test.dart`,
// which now pumps `softWrap: false` -- the shipped default -- so those tests
// already run against this layout. What is left for this file is the layout
// claim itself: with wrapping off the well scrolls sideways and the gutter
// does not go with it.
//
// Widths here are test-font units: `flutter_test` draws every glyph
// `fontSize` wide, so the "long" line below is far longer relative to the
// pane than the same string would be in JetBrains Mono. That is the safe
// direction -- it guarantees the overflow the test needs to see.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

import '../../support/pump_app.dart';

const String _longLine =
    'const result = compute(alpha, beta, gamma, delta, epsilon, zeta, eta);';

/// A second long line, on the *context* side. A scope card and a gap block
/// build their rows separately and each carries its own copy of the flag, so
/// a fixture whose only long line sits in the card cannot tell whether the
/// gap block ever received it -- that mutation came back green until this
/// line existed.
const String _longContextLine =
    'previously(existing, code, that, was, already, here, unchanged, ok);';

DiffFile _fileWith(String text, String contextText) => DiffFile(
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
  removedLines: 0,
  displayPath: 'lib/a.dart',
  hunks: <DiffHunk>[
    DiffHunk(
      oldStart: 1,
      oldCount: 2,
      newStart: 1,
      newCount: 2,
      heading: '',
      lines: <DiffLine>[
        DiffLine(
          kind: DiffLineKind.context,
          oldLine: 1,
          newLine: 1,
          text: contextText,
        ),
        DiffLine(kind: DiffLineKind.added, oldLine: 0, newLine: 2, text: text),
      ],
    ),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  required bool softWrap,
  String text = _longLine,
  String contextText = _longContextLine,
}) {
  return pumpGbmWidget(
    tester,
    child: SizedBox(
      width: 420,
      child: ScopedDiffView(
        softWrap: softWrap,
        title: 'Unstaged',
        file: _fileWith(text, contextText),
        staged: false,
        onStageScope: (int h, List<int> l) {},
      ),
    ),
  );
}

void main() {
  testWidgets('a line too wide for the well gets a horizontal scroller', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: false);

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // Counted, not `any`: the two rows come from different builders -- one
    // from the scope card, one from the gap block -- and each carries its own
    // copy of the flag. A finder that only asked "is there a pinned gutter"
    // stayed green with the gap block's copy hardcoded back to wrapping.
    expect(find.byType(GbmPinnedGutter), findsNWidgets(2));
  });

  testWidgets('a line that fits needs no scroller at all', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: false, text: 'x', contextText: 'y');
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('soft wrap on never scrolls sideways, however long the line', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: true);
    expect(find.byType(SingleChildScrollView), findsNothing);
    expect(find.byType(GbmPinnedGutter), findsNothing);
  });

  testWidgets('the line numbers stay put while the code scrolls under them', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: false);

    // Measured *below* the gutter's own Transform, not at it: a
    // `RenderTransform` applies its transform to its children, so
    // `localToGlobal` on the transform itself reports the untranslated
    // position and a rect taken there moves with the scroll no matter what
    // the widget does. Finding the wrong render object is the position-level
    // version of "a finder proves existence, never position".
    final Finder gutter = find.descendant(
      of: find.byType(GbmPinnedGutter).first,
      matching: find.byType(ColoredBox),
    );
    final Finder code = find.text(_longLine);
    final double gutterBefore = tester.getRect(gutter).left;
    final double codeBefore = tester.getRect(code).left;

    await tester.drag(find.byType(SingleChildScrollView), const Offset(-90, 0));
    await tester.pump();

    // The code moved -- without this the gutter assertion below is vacuous.
    expect(tester.getRect(code).left, lessThan(codeBefore));
    expect(tester.getRect(gutter).left, closeTo(gutterBefore, 0.5));
  });

  testWidgets('a card overrides the backdrop its rows pin against', (
    WidgetTester tester,
  ) async {
    // A scope card sits on surfacePanel while the well behind it is
    // surfaceSunken. A pinned gutter paints its own backdrop so the code can
    // pass under it, so taking the well's colour would draw a seam down the
    // left edge of every card.
    await _pump(tester, softWrap: false);

    final BuildContext context = tester.element(find.byType(ScopedDiffView));
    final GbmColors colors = context.gbmColors;
    final GbmPinnedGutterBackdrop backdrop = tester
        .widgetList<GbmPinnedGutterBackdrop>(
          find.byType(GbmPinnedGutterBackdrop),
        )
        .first;

    expect(backdrop.color.toARGB32(), colors.surfacePanel.toARGB32());
    expect(backdrop.color.toARGB32(), isNot(colors.surfaceSunken.toARGB32()));
  });
}
