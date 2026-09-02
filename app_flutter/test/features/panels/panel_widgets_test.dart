// Spec page 19 樣板規則 4: 「右明細一律是 78px 標籤 + 值 的定義列表，值可
// 選取複製」.
//
// Every assertion here is neighbour-relative -- the value's left edge
// measured against the field's own left edge -- rather than a pixel constant
// for the value, per [FLU-finder-proves-existence-not-position]. The one
// literal is 78 itself, which is the spec's number and the thing under test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

Future<void> _pumpField(
  WidgetTester tester, {
  required String label,
  required String value,
  bool mono = false,
  double width = 400,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: PanelDetailField(label: label, value: value, mono: mono),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PanelDetailField is P19 rule 4的 78px label + value', () {
    testWidgets('the value starts exactly 78px in from the field left edge', (
      tester,
    ) async {
      await _pumpField(tester, label: 'Path', value: '/tmp/wt');

      final Rect field = tester.getRect(find.byType(PanelDetailField));
      final Rect value = tester.getRect(find.text('/tmp/wt'));

      expect(
        value.left - field.left,
        78,
        reason: 'the label column is the spec\'s fixed 78px, not intrinsic',
      );
    });

    testWidgets('the label sits in that column rather than above the value', (
      tester,
    ) async {
      await _pumpField(tester, label: 'Path', value: '/tmp/wt');

      final Rect label = tester.getRect(find.text('Path'));
      final Rect value = tester.getRect(find.text('/tmp/wt'));

      // The defect this replaces stacked them: label.bottom <= value.top.
      // Side by side means they share vertical space instead.
      expect(
        label.top,
        value.top,
        reason: 'label and value are one row, not a stacked Column',
      );
      expect(label.right, lessThanOrEqualTo(value.left));
    });

    testWidgets('a value that wraps keeps the label on its first line', (
      tester,
    ) async {
      // The test font draws every glyph `fontSize` wide
      // ([TEST-canvas-is-800x600]), so at textSm (13) this 100-character
      // value needs ~1300px where the value column here gets 400 - 78 = 322,
      // i.e. it wraps to about four lines. A real proportional font would
      // wrap it later, which is the harmless direction -- the fixture
      // over-wraps rather than under-wraps.
      const String longValue =
          '/Users/someone/very/long/path/that/keeps/going/and/going/'
          'until/it/must/finally/wrap/somewhere.txt';
      expect(longValue.length, greaterThan(90));

      await _pumpField(tester, label: 'Path', value: longValue);

      final Rect label = tester.getRect(find.text('Path'));
      final Rect value = tester.getRect(find.text(longValue));

      expect(
        value.height,
        greaterThan(label.height),
        reason: 'the fixture must actually wrap or it tests nothing',
      );
      expect(
        label.top,
        value.top,
        reason:
            'CrossAxisAlignment.start -- the label aligns to the first line, '
            'not to the centre of a multi-line value',
      );
    });

    testWidgets('the value stays selectable, so it can be copied', (
      tester,
    ) async {
      await _pumpField(tester, label: 'HEAD', value: 'a1b2c3d');

      expect(find.byType(SelectableText), findsOneWidget);
    });

    testWidgets('a long value does not overflow its row', (tester) async {
      await _pumpField(
        tester,
        label: 'Path',
        value: 'x' * 200,
        mono: true,
        width: 300,
      );

      // Expanded is what makes this hold: RenderFlex lays out non-flex
      // children first, so a fixed 78px label plus an unbounded value
      // overflows before any flex could rescue it ([FLU-renderflex-non-flex-first]).
      expect(tester.takeException(), isNull);
    });
  });
}
