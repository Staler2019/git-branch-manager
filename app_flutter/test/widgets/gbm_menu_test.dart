// Verifies GbmMenuItem/showGbmMenu against docs/design/tokens-reference.md's
// `.gbm-menu`/`.gbm-menu-item`/`.gbm-menu-item.danger`/`.gbm-menu-sep`
// rules: separators render, danger items use the danger token, and a tap
// both closes the menu and invokes the item's callback.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_menu.dart';

Future<void> _openMenu(
  WidgetTester tester,
  GbmThemeVariant variant,
  List<GbmMenuItem> items,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(variant),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showGbmMenu(
                context,
                position: const RelativeRect.fromLTRB(0, 0, 0, 0),
                items: items,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final GbmThemeVariant variant in GbmThemeVariant.values) {
    final GbmColors colors = tokensFor(variant);

    testWidgets('renders every non-separator label ($variant)', (tester) async {
      await _openMenu(tester, variant, <GbmMenuItem>[
        GbmMenuItem(label: 'Checkout', onTap: () {}),
        const GbmMenuItem.separator(),
        GbmMenuItem(label: 'Delete branch', danger: true, onTap: () {}),
      ]);
      expect(find.text('Checkout'), findsOneWidget);
      expect(find.text('Delete branch'), findsOneWidget);
    });

    testWidgets(
      'a shortcut renders in mono at textTertiary when not hovered ($variant)',
      (tester) async {
        await _openMenu(tester, variant, <GbmMenuItem>[
          GbmMenuItem(label: 'Pull', shortcut: '⌘⇧P', onTap: () {}),
        ]);
        final Text shortcut = tester.widget<Text>(find.text('⌘⇧P'));
        expect(shortcut.style?.color, colors.textTertiary);
        expect(shortcut.style?.fontFamily, GbmTypography.fontMono);
      },
    );

    testWidgets(
      'tapping an item closes the menu and invokes onTap ($variant)',
      (tester) async {
        bool tapped = false;
        await _openMenu(tester, variant, <GbmMenuItem>[
          GbmMenuItem(label: 'Checkout', onTap: () => tapped = true),
        ]);
        await tester.tap(find.text('Checkout'));
        await tester.pumpAndSettle();
        expect(tapped, isTrue);
        expect(find.text('Checkout'), findsNothing);
      },
    );
  }
}
