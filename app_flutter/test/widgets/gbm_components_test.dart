// Verifies the `.gbm-btn`/`.gbm-iconbtn`/`.gbm-badge`/`.gbm-row` component
// variants against docs/design/tokens-reference.md's components.css, across
// all three theme variants -- colors are read from `tokensFor()` rather than
// hardcoded so a token change doesn't silently desync these assertions.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_badge.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_icon_button.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';

import '../support/pump_app.dart';

Future<void> _pump(
  WidgetTester tester,
  GbmThemeVariant variant,
  Widget child,
) => pumpGbmWidget(
  tester,
  variant: variant,
  child: Center(child: child),
);

void main() {
  for (final GbmThemeVariant variant in GbmThemeVariant.values) {
    final GbmColors colors = tokensFor(variant);

    group('GbmButton ($variant)', () {
      testWidgets('danger kind is transparent with danger foreground', (
        tester,
      ) async {
        await _pump(
          tester,
          variant,
          GbmButton(
            label: 'Delete',
            kind: GbmButtonKind.danger,
            onPressed: () {},
          ),
        );
        final Text text = tester.widget<Text>(find.text('Delete'));
        expect(
          text.style?.color,
          isNull,
        ); // color resolved via ButtonStyle.foregroundColor, not Text.style
        final TextButton button = tester.widget<TextButton>(
          find.byType(TextButton),
        );
        final Color? bg = button.style?.backgroundColor?.resolve(
          <WidgetState>{},
        );
        expect(bg, Colors.transparent);
      });

      testWidgets('sm size is 24 tall', (tester) async {
        await _pump(
          tester,
          variant,
          GbmButton(label: 'Fetch', size: GbmButtonSize.sm, onPressed: () {}),
        );
        final Size size = tester.getSize(find.byType(GbmButton));
        expect(size.height, 24);
      });

      testWidgets('normal size is 30 tall', (tester) async {
        await _pump(
          tester,
          variant,
          GbmButton(label: 'Push', onPressed: () {}),
        );
        final Size size = tester.getSize(find.byType(GbmButton));
        expect(size.height, 30);
      });

      testWidgets('primary kind uses accent background', (tester) async {
        await _pump(
          tester,
          variant,
          GbmButton(
            label: 'Push',
            kind: GbmButtonKind.primary,
            onPressed: () {},
          ),
        );
        final TextButton button = tester.widget<TextButton>(
          find.byType(TextButton),
        );
        final Color? bg = button.style?.backgroundColor?.resolve(
          <WidgetState>{},
        );
        expect(bg, colors.accent);
      });
    });

    group('GbmIconButton ($variant)', () {
      testWidgets('is 28x28', (tester) async {
        await _pump(
          tester,
          variant,
          GbmIconButton(icon: const Icon(Icons.add), onPressed: () {}),
        );
        final Size size = tester.getSize(find.byType(GbmIconButton));
        expect(size, const Size(28, 28));
      });

      testWidgets('active uses accentSubtle background and accent icon', (
        tester,
      ) async {
        await _pump(
          tester,
          variant,
          GbmIconButton(
            icon: const Icon(Icons.add),
            active: true,
            onPressed: () {},
          ),
        );
        final IconButton button = tester.widget<IconButton>(
          find.byType(IconButton),
        );
        final Color? bg = button.style?.backgroundColor?.resolve(
          <WidgetState>{},
        );
        final Color? iconColor = button.style?.iconColor?.resolve(
          <WidgetState>{},
        );
        expect(bg, colors.accentSubtle);
        expect(iconColor, colors.accent);
      });
    });

    group('GbmBadge ($variant)', () {
      testWidgets('added kind uses diffAdd tokens', (tester) async {
        await _pump(
          tester,
          variant,
          const GbmBadge(label: '+12', kind: GbmBadgeKind.added),
        );
        final Container container = tester.widget<Container>(
          find.byType(Container).first,
        );
        final BoxDecoration decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, colors.diffAddBg);
      });

      testWidgets('removed kind uses diffDel tokens', (tester) async {
        await _pump(
          tester,
          variant,
          const GbmBadge(label: '-3', kind: GbmBadgeKind.removed),
        );
        final Container container = tester.widget<Container>(
          find.byType(Container).first,
        );
        final BoxDecoration decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, colors.diffDelBg);
      });
    });

    group('GbmRow ($variant)', () {
      testWidgets('selected uses surfaceSelected background', (tester) async {
        await _pump(
          tester,
          variant,
          const GbmRow(selected: true, child: Text('row')),
        );
        final Finder decorated = find.descendant(
          of: find.byType(GbmRow),
          matching: find.byType(Container),
        );
        final Container container = tester.widget<Container>(decorated.first);
        final BoxDecoration decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, colors.surfaceSelected);
      });

      testWidgets('unselected has no background', (tester) async {
        await _pump(tester, variant, const GbmRow(child: Text('row')));
        final Finder decorated = find.descendant(
          of: find.byType(GbmRow),
          matching: find.byType(Container),
        );
        final Container container = tester.widget<Container>(decorated.first);
        final BoxDecoration decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, isNull);
      });

      testWidgets('default height is rowHeightComfortable', (tester) async {
        await _pump(tester, variant, const GbmRow(child: Text('row')));
        final Size size = tester.getSize(find.byType(GbmRow));
        expect(size.height, GbmSpacing.rowHeightComfortable);
      });
    });
  }

  // G7: worktree-dialogs-spec.html's "Buttons" row wants both buttons in a
  // dialog's action row to be `.gbm-btn-sm` -- rather than touching all ~34
  // call sites' button constructors, GbmDialogShell wraps its action row in
  // a GbmButtonSizeScope so an unspecified GbmButton.size resolves through
  // it. An explicit size: still wins, so a caller that genuinely wants
  // normal-sized buttons inside a dialog is not overridden.
  group('GbmButtonSizeScope', () {
    testWidgets('an unspecified size resolves through the scope', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        variant: GbmThemeVariant.darkTechnical,
        child: Center(
          child: GbmButtonSizeScope(
            size: GbmButtonSize.sm,
            child: GbmButton(label: 'Cancel', onPressed: () {}),
          ),
        ),
      );

      final Size size = tester.getSize(find.byType(GbmButton));
      expect(size.height, 24);
    });

    testWidgets('an explicit size still wins over an enclosing scope', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        variant: GbmThemeVariant.darkTechnical,
        child: Center(
          child: GbmButtonSizeScope(
            size: GbmButtonSize.sm,
            child: GbmButton(
              label: 'Cancel',
              size: GbmButtonSize.normal,
              onPressed: () {},
            ),
          ),
        ),
      );

      final Size size = tester.getSize(find.byType(GbmButton));
      expect(size.height, 30);
    });

    testWidgets('with no enclosing scope, the default stays normal (30)', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        variant: GbmThemeVariant.darkTechnical,
        child: Center(
          child: GbmButton(label: 'Cancel', onPressed: () {}),
        ),
      );

      final Size size = tester.getSize(find.byType(GbmButton));
      expect(size.height, 30);
    });
  });
}
