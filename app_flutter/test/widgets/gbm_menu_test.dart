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
  group('GbmMenuItem.submenu', () {
    test('asserts on nested submenu (submenu child contains submenu)', () {
      expect(
        () => GbmMenuItem.submenu(
          label: 'More',
          children: <GbmMenuItem>[
            GbmMenuItem.submenu(
              label: 'Nested',
              children: <GbmMenuItem>[GbmMenuItem(label: 'Item', onTap: () {})],
            ),
          ],
        ),
        throwsAssertionError,
      );
    });

    test('creates submenu with valid single-level children', () {
      expect(
        () => GbmMenuItem.submenu(
          label: 'More',
          children: <GbmMenuItem>[
            GbmMenuItem(label: 'Item', onTap: () {}),
          ],
        ),
        returnsNormally,
      );
    });
  });

  group('Menu invariants', () {
    test('asserts on >8 top-level non-separator items', () {
      expect(
        () {
          final items = List<GbmMenuItem>.generate(
            9,
            (i) => GbmMenuItem(label: 'Item $i', onTap: () {}),
          );
          validateGbmMenuItems(items);
        },
        throwsAssertionError,
      );
    });

    test('asserts when danger item is not last non-separator', () {
      expect(
        () {
          validateGbmMenuItems(
            <GbmMenuItem>[
              GbmMenuItem(label: 'Checkout', onTap: () {}),
              GbmMenuItem(label: 'Delete', danger: true, onTap: () {}),
              GbmMenuItem(label: 'After danger', onTap: () {}),
            ],
          );
        },
        throwsAssertionError,
      );
    });

    test('asserts when danger item has no separator before it', () {
      expect(
        () {
          validateGbmMenuItems(
            <GbmMenuItem>[
              GbmMenuItem(label: 'Checkout', onTap: () {}),
              GbmMenuItem(label: 'Delete', danger: true, onTap: () {}),
            ],
          );
        },
        throwsAssertionError,
      );
    });

    test('allows valid menu with danger + separator', () {
      expect(
        () {
          validateGbmMenuItems(
            <GbmMenuItem>[
              GbmMenuItem(label: 'Checkout', onTap: () {}),
              const GbmMenuItem.separator(),
              GbmMenuItem(label: 'Delete', danger: true, onTap: () {}),
            ],
          );
        },
        returnsNormally,
      );
    });

    test('allows menu without danger item', () {
      expect(
        () {
          validateGbmMenuItems(
            <GbmMenuItem>[
              GbmMenuItem(label: 'Checkout', onTap: () {}),
              GbmMenuItem(label: 'Rename', onTap: () {}),
            ],
          );
        },
        returnsNormally,
      );
    });
  });

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

    testWidgets('submenu renders label at top level ($variant)', (
      tester,
    ) async {
      await _openMenu(tester, variant, <GbmMenuItem>[
        GbmMenuItem.submenu(
          label: 'More actions',
          children: <GbmMenuItem>[
            GbmMenuItem(label: 'Nested item', onTap: () {}),
          ],
        ),
      ]);
      expect(find.text('More actions'), findsOneWidget);
    });

    testWidgets('submenu children do not render initially ($variant)', (
      tester,
    ) async {
      await _openMenu(tester, variant, <GbmMenuItem>[
        GbmMenuItem.submenu(
          label: 'More actions',
          children: <GbmMenuItem>[
            GbmMenuItem(label: 'Nested item', onTap: () {}),
          ],
        ),
      ]);
      expect(find.text('Nested item'), findsNothing);
    });
  }
}
