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
          children: <GbmMenuItem>[GbmMenuItem(label: 'Item', onTap: () {})],
        ),
        returnsNormally,
      );
    });
  });

  group('Menu invariants', () {
    test('asserts on >8 top-level non-separator items', () {
      expect(() {
        final items = List<GbmMenuItem>.generate(
          9,
          (i) => GbmMenuItem(label: 'Item $i', onTap: () {}),
        );
        validateGbmMenuItems(items);
      }, throwsAssertionError);
    });

    test('asserts when danger item is not last non-separator', () {
      expect(() {
        validateGbmMenuItems(<GbmMenuItem>[
          GbmMenuItem(label: 'Checkout', onTap: () {}),
          GbmMenuItem(label: 'Delete', danger: true, onTap: () {}),
          GbmMenuItem(label: 'After danger', onTap: () {}),
        ]);
      }, throwsAssertionError);
    });

    test('asserts when danger item has no separator before it', () {
      expect(() {
        validateGbmMenuItems(<GbmMenuItem>[
          GbmMenuItem(label: 'Checkout', onTap: () {}),
          GbmMenuItem(label: 'Delete', danger: true, onTap: () {}),
        ]);
      }, throwsAssertionError);
    });

    test('allows valid menu with danger + separator', () {
      expect(() {
        validateGbmMenuItems(<GbmMenuItem>[
          GbmMenuItem(label: 'Checkout', onTap: () {}),
          const GbmMenuItem.separator(),
          GbmMenuItem(label: 'Delete', danger: true, onTap: () {}),
        ]);
      }, returnsNormally);
    });

    test('allows menu without danger item', () {
      expect(() {
        validateGbmMenuItems(<GbmMenuItem>[
          GbmMenuItem(label: 'Checkout', onTap: () {}),
          GbmMenuItem(label: 'Rename', onTap: () {}),
        ]);
      }, returnsNormally);
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

  group('submenu flyout', () {
    testWidgets('a submenu trigger renders a chevron, not a shortcut', (
      tester,
    ) async {
      await _openMenu(tester, GbmThemeVariant.darkTechnical, <GbmMenuItem>[
        GbmMenuItem.submenu(
          label: 'More actions',
          children: <GbmMenuItem>[
            GbmMenuItem(label: 'Nested item', onTap: () {}),
          ],
        ),
      ]);

      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
    });

    testWidgets('tapping the trigger opens the flyout and keeps the parent', (
      tester,
    ) async {
      await _openMenu(tester, GbmThemeVariant.darkTechnical, <GbmMenuItem>[
        GbmMenuItem(label: 'Copy path', onTap: () {}),
        GbmMenuItem.submenu(
          label: 'More actions',
          children: <GbmMenuItem>[
            GbmMenuItem(label: 'Nested item', onTap: () {}),
          ],
        ),
      ]);

      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();

      expect(find.text('Nested item'), findsOneWidget);
      // The parent is still standing underneath -- a submenu trigger is not
      // an action, so it must not dismiss the menu it lives in.
      expect(find.text('Copy path'), findsOneWidget);
    });

    testWidgets('choosing a child fires its callback and closes both menus', (
      tester,
    ) async {
      bool tapped = false;
      await _openMenu(tester, GbmThemeVariant.darkTechnical, <GbmMenuItem>[
        GbmMenuItem(label: 'Copy path', onTap: () {}),
        GbmMenuItem.submenu(
          label: 'More actions',
          children: <GbmMenuItem>[
            GbmMenuItem(label: 'Nested item', onTap: () => tapped = true),
          ],
        ),
      ]);

      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nested item'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
      expect(find.text('Nested item'), findsNothing);
      expect(find.text('Copy path'), findsNothing);
    });

    testWidgets('a child action that pushes a route keeps that route', (
      tester,
    ) async {
      // The ordering guarantee _openSubmenu documents. Menu items routinely
      // push a dialog; if the parent menu were popped *after* the action ran,
      // that pop would take the dialog down instead of the menu, and the user
      // would see the dialog flash and vanish.
      late BuildContext outerContext;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                outerContext = context;
                return Center(
                  child: ElevatedButton(
                    onPressed: () => showGbmMenu(
                      context,
                      position: const RelativeRect.fromLTRB(0, 0, 0, 0),
                      items: <GbmMenuItem>[
                        GbmMenuItem(label: 'Copy path', onTap: () {}),
                        GbmMenuItem.submenu(
                          label: 'More actions',
                          children: <GbmMenuItem>[
                            GbmMenuItem(
                              label: 'Nested item',
                              onTap: () => showDialog<void>(
                                context: outerContext,
                                builder: (_) =>
                                    const AlertDialog(title: Text('Pushed')),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    child: const Text('open'),
                  ),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nested item'));
      await tester.pumpAndSettle();

      expect(find.text('Pushed'), findsOneWidget);
      expect(find.text('Copy path'), findsNothing);
      expect(find.text('Nested item'), findsNothing);
    });

    testWidgets('a disabled child changes nothing and leaves the parent open', (
      tester,
    ) async {
      await _openMenu(tester, GbmThemeVariant.darkTechnical, <GbmMenuItem>[
        GbmMenuItem(label: 'Copy path', onTap: () {}),
        GbmMenuItem.submenu(
          label: 'More actions',
          children: <GbmMenuItem>[
            const GbmMenuItem(
              label: 'Nested item',
              enabled: false,
              onTap: null,
            ),
          ],
        ),
      ]);

      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nested item'));
      await tester.pumpAndSettle();

      expect(find.text('Copy path'), findsOneWidget);
    });

    testWidgets('a separator inside a submenu still renders as a separator', (
      tester,
    ) async {
      await _openMenu(tester, GbmThemeVariant.darkTechnical, <GbmMenuItem>[
        GbmMenuItem.submenu(
          label: 'More actions',
          children: <GbmMenuItem>[
            GbmMenuItem(label: 'First', onTap: () {}),
            const GbmMenuItem.separator(),
            GbmMenuItem(label: 'Second', onTap: () {}),
          ],
        ),
      ]);

      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();

      expect(find.text('First'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);
    });
  });

  group('multi-select affordances (spec page 13)', () {
    testWidgets('showGbmContextMenu renders the title as a non-item header', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () => showGbmContextMenu(
                    context,
                    const Offset(20, 20),
                    <GbmMenuItem>[GbmMenuItem(label: 'Copy SHA', onTap: () {})],
                    title: '3 items',
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

      expect(find.text('3 items'), findsOneWidget);
      expect(find.text('Copy SHA'), findsOneWidget);
    });

    testWidgets(
      'a title does not consume any of the 8-item context-menu budget',
      (tester) async {
        // validateGbmMenuItems caps *actions* at 8 (spec page 05). A header
        // that names the selection is not an action, so a full 8-item menu
        // must still be legal with a title on top -- if the title were ever
        // counted, this would trip the assert and fail.
        await tester.pumpWidget(
          MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () => showGbmContextMenu(
                      context,
                      const Offset(20, 20),
                      <GbmMenuItem>[
                        for (int i = 0; i < 8; i++)
                          GbmMenuItem(label: 'Item $i', onTap: () {}),
                      ],
                      title: '5 items',
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

        expect(find.text('5 items'), findsOneWidget);
        expect(find.text('Item 7'), findsOneWidget);
      },
    );

    testWidgets('a disabled item carries its tooltip', (tester) async {
      await _openMenu(tester, GbmThemeVariant.darkTechnical, <GbmMenuItem>[
        const GbmMenuItem(
          label: 'Rename…',
          enabled: false,
          tooltip: 'Only one branch at a time',
          onTap: null,
        ),
      ]);

      final Tooltip tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Only one branch at a time');
    });

    testWidgets('a submenu child keeps its tooltip through the re-wrap', (
      tester,
    ) async {
      // The flyout rebuilds every child to graft on "close the parent
      // first" (see _openSubmenu). A field left out of that rebuild is
      // silently dropped, which is invisible until someone opens a submenu.
      await _openMenu(tester, GbmThemeVariant.darkTechnical, <GbmMenuItem>[
        GbmMenuItem.submenu(
          label: 'More actions',
          children: const <GbmMenuItem>[
            GbmMenuItem(
              label: 'Reset branch to here…',
              enabled: false,
              tooltip: 'Needs a single target commit',
              onTap: null,
            ),
          ],
        ),
      ]);

      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();

      final Tooltip tooltip = tester.widget<Tooltip>(
        find.ancestor(
          of: find.text('Reset branch to here…'),
          matching: find.byType(Tooltip),
        ),
      );
      expect(tooltip.message, 'Needs a single target commit');
    });
  });
}
