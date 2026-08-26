// What `softWrap` actually does to a diff row's layout.
//
// Asserted as *height*, because that is the observable difference: a wrapped
// long line occupies several visual lines and an unwrapped one occupies
// exactly one. Widths are avoided on purpose -- `flutter_test`'s font draws
// every glyph `fontSize` wide, so any width here would be a test-font number
// with no bearing on the real one. Heights are not distorted that way.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

void main() {
  // Narrower than the default 800x600 canvas on purpose: a wrap only shows up
  // when the pane is narrower than the line, and a test sized to its own
  // comfort would never see it.
  const double paneWidth = 300;

  DiffLine lineOf(String text) =>
      DiffLine(kind: DiffLineKind.added, oldLine: 0, newLine: 12, text: text);

  Future<double> pumpHeight(
    WidgetTester tester, {
    required String text,
    required bool softWrap,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: paneWidth,
              child: DiffLineView(line: lineOf(text), softWrap: softWrap),
            ),
          ),
        ),
      ),
    );
    return tester.getSize(find.byType(DiffLineView)).height;
  }

  const String longLine =
      'const value = someFunction(argumentOne, argumentTwo, argumentThree, '
      'argumentFour, argumentFive, argumentSix, argumentSeven);';

  testWidgets('a long line wraps to several rows when soft wrap is on', (
    WidgetTester tester,
  ) async {
    final double short = await pumpHeight(tester, text: 'x', softWrap: true);
    final double long = await pumpHeight(
      tester,
      text: longLine,
      softWrap: true,
    );

    expect(long, greaterThan(short));
  });

  testWidgets('the same line stays one row tall when soft wrap is off', (
    WidgetTester tester,
  ) async {
    final double short = await pumpHeight(tester, text: 'x', softWrap: false);
    final double long = await pumpHeight(
      tester,
      text: longLine,
      softWrap: false,
    );

    // Equal to a one-character line's height -- the exact claim, stated
    // without a pixel constant that would only hold under the test font.
    expect(long, short);
  });

  testWidgets('the gutter is pinnable only when soft wrap is off', (
    WidgetTester tester,
  ) async {
    await pumpHeight(tester, text: longLine, softWrap: false);
    expect(find.byType(GbmPinnedGutter), findsOneWidget);

    await pumpHeight(tester, text: longLine, softWrap: true);
    // Wrapped rows have nowhere to scroll, so there is nothing to pin against
    // and the row keeps its plain Row layout.
    expect(find.byType(GbmPinnedGutter), findsNothing);
  });
}
