import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';
import 'package:gbm_flutter/widgets/gbm_split_button.dart';

/// open-with-apps-spec.html, screen 1: a ghost main segment, a 1px rule,
/// and a ▾ segment that opens a `showGbmMenu` list under itself.
void main() {
  late int mainTaps;
  late int itemTaps;

  Future<void> pump(WidgetTester tester) async {
    mainTaps = 0;
    itemTaps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: Center(
            child: GbmSplitButton(
              label: 'Open in terminal',
              onPressed: () => mainTaps++,
              menuTooltip: '其他開啟方式',
              menuItems: () => <GbmMenuItem>[
                GbmMenuItem(label: 'Rider', onTap: () => itemTaps++),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Finder chevron() => find.byTooltip('其他開啟方式');

  testWidgets('the main segment is the action, and nothing else', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Open in terminal'));
    await tester.pumpAndSettle();
    expect(mainTaps, 1);
    expect(find.text('Rider'), findsNothing);
  });

  testWidgets('the chevron opens the menu under itself', (tester) async {
    await pump(tester);
    await tester.tap(chevron());
    await tester.pumpAndSettle();
    expect(mainTaps, 0);
    expect(find.text('Rider'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Rider')).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(chevron()).dy),
    );
    await tester.tap(find.text('Rider'));
    await tester.pumpAndSettle();
    expect(itemTaps, 1);
  });

  // `.gbm-btn-ghost:hover` is surface-hover; a bare InkWell would inherit
  // ThemeData.hoverColor instead ([FLU-hand-rolled-inkwell-hover]).
  testWidgets('the chevron hovers in surfaceHover', (tester) async {
    await pump(tester);
    final InkWell ink = tester.widget<InkWell>(
      find.descendant(of: chevron(), matching: find.byType(InkWell)),
    );
    expect(
      ink.hoverColor,
      tokensFor(GbmThemeVariant.darkTechnical).surfaceHover,
    );
  });

  testWidgets('the two segments round only their outer corners', (
    tester,
  ) async {
    await pump(tester);
    // The shape the TextButton actually paints, not GbmButton's field: a
    // field nothing reads would pass a field assertion.
    final TextButton main = tester.widget<TextButton>(
      find.descendant(
        of: find.byType(GbmButton),
        matching: find.byWidgetPredicate((Widget w) => w is TextButton),
      ),
    );
    expect(
      (main.style!.shape!.resolve(<WidgetState>{})! as RoundedRectangleBorder)
          .borderRadius,
      const BorderRadius.horizontal(left: Radius.circular(GbmSpacing.radiusMd)),
    );
    final InkWell ink = tester.widget<InkWell>(
      find.descendant(of: chevron(), matching: find.byType(InkWell)),
    );
    expect(
      ink.borderRadius,
      const BorderRadius.horizontal(
        right: Radius.circular(GbmSpacing.radiusMd),
      ),
    );
    expect(
      tester.getSize(chevron()).height,
      30,
      reason: 'the same height as the main segment',
    );
  });
}
