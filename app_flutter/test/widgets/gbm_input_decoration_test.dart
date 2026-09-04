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
    test('is dense, r6, horizontal-only padding at space3', () {
      final InputDecoration decoration = gbmInputDecoration(colors: colors);

      expect(decoration.isDense, isTrue);
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

    test(
      'passes labelText/hintText/errorText/suffixText/prefixIcon through',
      () {
        const Icon icon = Icon(Icons.search);
        final InputDecoration decoration = gbmInputDecoration(
          colors: colors,
          labelText: 'label',
          hintText: 'hint',
          errorText: 'error',
          suffixText: 'suffix',
          prefixIcon: icon,
        );

        expect(decoration.labelText, 'label');
        expect(decoration.hintText, 'hint');
        expect(decoration.errorText, 'error');
        expect(decoration.suffixText, 'suffix');
        expect(decoration.prefixIcon, icon);
      },
    );
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
  });
}
