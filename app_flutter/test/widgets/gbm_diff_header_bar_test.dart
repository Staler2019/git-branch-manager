// The one diff header bar: History's and the Working Copy's title bars and the
// read-only diff panes' headers are the same furniture, so they share its
// height, ground, border and path style. Spec:
// docs/claude-design-demo/rename-diff-display-spec.html, 畫面 2.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_diff_header_bar.dart';

import '../support/pump_app.dart';

/// The variant [pumpGbmWidget] defaults to, so the tokens below are the ones
/// actually in effect.
final GbmColors _colors = tokensFor(GbmThemeVariant.darkTechnical);

Future<void> _pump(WidgetTester tester, Widget bar) => pumpGbmWidget(
  tester,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(width: 400, child: bar),
  ),
);

void main() {
  testWidgets('draws the path in the diff title bar style', (tester) async {
    await _pump(tester, const GbmDiffHeaderBar(text: 'a.dart → b.dart'));

    expect(tester.getSize(find.byType(GbmDiffHeaderBar)).height, 38);
    final Container bar = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(GbmDiffHeaderBar),
            matching: find.byType(Container),
          )
          .first,
    );
    final BoxDecoration decoration = bar.decoration! as BoxDecoration;
    expect(decoration.color, same(_colors.surfacePanelRaised));
    expect(
      (decoration.border! as Border).bottom.color,
      same(_colors.borderDefault),
    );
    expect(
      bar.padding,
      const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
    );

    final Text text = tester.widget<Text>(find.text('a.dart → b.dart'));
    expect(text.style!.fontFamily, GbmTypography.fontMono);
    expect(text.style!.fontSize, GbmTypography.textSm);
    expect(text.style!.color, same(_colors.textPrimary));
    expect(text.overflow, TextOverflow.ellipsis);
  });

  testWidgets('trailing controls sit at the right end', (tester) async {
    await _pump(
      tester,
      const GbmDiffHeaderBar(
        text: 'a.dart',
        trailing: <Widget>[SizedBox(key: Key('ctl'), width: 40, height: 20)],
      ),
    );

    final Rect bar = tester.getRect(find.byType(GbmDiffHeaderBar));
    expect(
      tester.getRect(find.byKey(const Key('ctl'))).right,
      bar.right - GbmSpacing.space3,
    );
  });

  testWidgets('a long path elides instead of pushing the controls out', (
    tester,
  ) async {
    await _pump(
      tester,
      GbmDiffHeaderBar(
        text: 'lib/${'very_long_segment/' * 20}file.dart',
        trailing: const <Widget>[
          SizedBox(key: Key('ctl'), width: 120, height: 20),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    final Rect bar = tester.getRect(find.byType(GbmDiffHeaderBar));
    expect(
      tester.getRect(find.byKey(const Key('ctl'))).right,
      bar.right - GbmSpacing.space3,
    );
  });
}
