// Shared `.gbm-input` decoration (worktree-dialogs-spec.html's G4): every
// single-line dialog TextField should render at height 30 / radius 6, with
// an accent-coloured focus border (the spec's `focus` field kind, G8) --
// none of which existed before this file, since every dialog built its own
// bare `InputDecoration(isDense, OutlineInputBorder())` inline.
//
// Pure-function tests only: no widget pumped, no BuildContext needed --
// `gbmInputDecoration`/`gbmMultilineInputDecoration` take a resolved
// [GbmColors] directly (every dialog's `build()` already computes one),
// which is what keeps this tier from depending on a widget tree at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_input_decoration.dart';

void main() {
  final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

  group('gbmInputDecoration', () {
    // Deliberately **not** dense -- see the function's own comment: dense
    // is what made the painted outline shorter than its wrapper.
    test('is non-dense, r6, horizontal-only padding at space3', () {
      final InputDecoration decoration = gbmInputDecoration(colors: colors);

      expect(decoration.isDense, isFalse);
      expect(
        decoration.contentPadding,
        const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      );
      final OutlineInputBorder border =
          decoration.border! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(GbmSpacing.radiusMd));
    });

    test('focusedBorder is accent-coloured -- the spec\'s missing focus '
        'field kind (G8)', () {
      final InputDecoration decoration = gbmInputDecoration(colors: colors);
      final OutlineInputBorder focused =
          decoration.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, colors.accent);
    });

    test('passes hintText/suffixText/prefixIcon through', () {
      const Icon icon = Icon(Icons.search);
      final InputDecoration decoration = gbmInputDecoration(
        colors: colors,
        hintText: 'hint',
        suffixText: 'suffix',
        prefixIcon: icon,
      );

      expect(decoration.hintText, 'hint');
      expect(decoration.suffixText, 'suffix');
      expect(decoration.prefixIcon, icon);
    });

    // The error *message* is the caller's external Text; what the
    // decoration owns is the outline colour.
    test('hasError recolours every border state to danger, and takes no '
        'message', () {
      final InputDecoration decoration = gbmInputDecoration(
        colors: colors,
        hasError: true,
      );

      expect(decoration.errorText, isNull);
      expect(decoration.border!.borderSide.color, colors.danger);
      expect(decoration.enabledBorder!.borderSide.color, colors.danger);
      expect(decoration.focusedBorder!.borderSide.color, colors.danger);
    });

    // Regression: labelText's floating label does not fit inside the fixed
    // 30px SizedBox every single-line dialog field wraps this decoration in
    // -- measured (scratch probe, not committed): with labelText set, the
    // label's own rect starts at y=14.9 while the SizedBox starts at
    // y=20, i.e. the label paints outside the box it is meant to sit in and
    // overlaps the value text's leading ~6px. Removing labelText was the
    // fix; this pins the removal so it cannot silently come back.
    test('has no labelText parameter -- see the function doc comment', () {
      final InputDecoration decoration = gbmInputDecoration(colors: colors);
      expect(decoration.labelText, isNull);
    });

    // Measured off a real macOS screenshot (the widget tier cannot see any
    // of this -- see the group comment below): the box drew a **black**
    // outline, because a bare `OutlineInputBorder()` defaults to
    // `BorderSide()`, which is `Colors.black` width 1. The spec's `.box` is
    // `1px solid var(--gbm-border-default)`.
    test(
      'every border state is border-default, never the bare black default',
      () {
        final InputDecoration decoration = gbmInputDecoration(colors: colors);

        for (final MapEntry<String, InputBorder?> entry
            in <String, InputBorder?>{
              'border': decoration.border,
              'enabledBorder': decoration.enabledBorder,
              'disabledBorder': decoration.disabledBorder,
            }.entries) {
          expect(entry.value, isNotNull, reason: entry.key);
          expect(
            entry.value!.borderSide.color,
            colors.borderDefault,
            reason: entry.key,
          );
        }
      },
    );

    // The field now *rests* in the disabled state on Add Worktree (位置 is
    // locked until a branch is picked), so a disabled border left at the
    // Material default would be the first thing a user sees.
    test(
      'disabledBorder exists so the black default cannot resurface there',
      () {
        final InputDecoration decoration = gbmInputDecoration(colors: colors);
        final OutlineInputBorder disabled =
            decoration.disabledBorder! as OutlineInputBorder;
        expect(
          disabled.borderRadius,
          BorderRadius.circular(GbmSpacing.radiusMd),
        );
      },
    );

    // spec `.box`: `background: var(--gbm-surface-panel)`. Unfilled, the box
    // showed the shell's own `surface-panel-raised` through it, so the field
    // read as flush with the dialog instead of sunken into it.
    test('is filled with surface-panel, not left transparent', () {
      final InputDecoration decoration = gbmInputDecoration(colors: colors);

      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, colors.surfacePanel);
    });

    // spec `.box--focus { border-color: var(--gbm-accent); }` -- the colour
    // changes, the width does not. 1.5 was a drawn value with no source.
    test('focus changes only the border colour, keeping width 1', () {
      final InputDecoration decoration = gbmInputDecoration(colors: colors);
      final OutlineInputBorder focused =
          decoration.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.width, 1.0);
    });
  });

  group('gbmMultilineInputDecoration', () {
    test('shares padding/radius/focus but adds vertical padding, no fixed '
        'height contract', () {
      final InputDecoration decoration = gbmMultilineInputDecoration(
        colors: colors,
      );

      expect(decoration.isDense, isTrue);
      expect(
        decoration.contentPadding,
        const EdgeInsets.symmetric(
          horizontal: GbmSpacing.space3,
          vertical: GbmSpacing.space2,
        ),
      );
      final OutlineInputBorder border =
          decoration.border! as OutlineInputBorder;
      expect(border.borderRadius, BorderRadius.circular(GbmSpacing.radiusMd));
      final OutlineInputBorder focused =
          decoration.focusedBorder! as OutlineInputBorder;
      expect(focused.borderSide.color, colors.accent);
    });

    test('shares the border colour and fill treatment', () {
      final InputDecoration decoration = gbmMultilineInputDecoration(
        colors: colors,
      );

      expect(decoration.border!.borderSide.color, colors.borderDefault);
      expect(decoration.enabledBorder!.borderSide.color, colors.borderDefault);
      expect(decoration.filled, isTrue);
      expect(decoration.fillColor, colors.surfacePanel);
    });
  });

  // 使用者回報:「隔壁的瀏覽button畫面與瀏覽textbox高度不同，所以spec你沒有
  // 照做」-- measured on a real macOS screenshot at 23px against the
  // GbmButton's 30.
  //
  // The field's *widget* rect was 30 the whole time, which is why the first
  // probe of this bug found nothing and why every existing test stayed
  // green: `getRect(find.byType(TextField))` reads what the `SizedBox`
  // imposed, not what Material painted. `_RenderDecoration` lays the
  // border/fill out as a **separate child RenderBox**, tight to its own
  // computed `containerHeight` -- so the only assertion that can disagree
  // with this defect is one that measures that child.
  // [TEST-fixture-cannot-disagree] row 14, one level deeper.
  group('the painted box, not the widget box', () {
    Future<Rect> paintedBox(WidgetTester tester, Widget field) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox(width: 300, child: field)),
          ),
        ),
      );
      return tester.getRect(
        find
            .descendant(
              of: find.byType(InputDecorator),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
    }

    testWidgets('fills its fixed-height wrapper exactly', (tester) async {
      final Rect box = await paintedBox(
        tester,
        SizedBox(
          height: GbmSpacing.inputHeight,
          child: TextField(decoration: gbmInputDecoration(colors: colors)),
        ),
      );

      expect(box.height, GbmSpacing.inputHeight);
    });

    // The 10px collapse: with the message inside the decoration, the
    // wrapper's 30 was split between box and subtext.
    testWidgets('an errored field keeps its full height, because the '
        'message is not inside the decoration', (tester) async {
      final Rect box = await paintedBox(
        tester,
        SizedBox(
          height: GbmSpacing.inputHeight,
          child: TextField(
            decoration: gbmInputDecoration(colors: colors, hasError: true),
          ),
        ),
      );

      expect(box.height, GbmSpacing.inputHeight);
    });
  });
}
