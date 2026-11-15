// Verifies the variant-to-ThemeData mapping that every surface inherits:
// which variants are dark (the single source `GbmThemeVariant.isDark`), and
// that the shadow tokens follow the theme's brightness rather than one named
// variant.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

void main() {
  test('only darkTechnical is dark among the shipped variants', () {
    expect(GbmThemeVariant.darkTechnical.isDark, isTrue);
    expect(GbmThemeVariant.lightIde.isDark, isFalse);
    expect(GbmThemeVariant.neutralProfessional.isDark, isFalse);
  });

  for (final GbmThemeVariant variant in GbmThemeVariant.values) {
    test('buildGbmTheme($variant) brightness follows isDark', () {
      final ThemeData theme = buildGbmTheme(variant);
      final Brightness expected = variant.isDark
          ? Brightness.dark
          : Brightness.light;
      expect(theme.brightness, expected);
      expect(theme.colorScheme.brightness, expected);
    });
  }

  test('shadow alpha is the deep set on dark, the light set on light', () {
    double alphaOf(List<BoxShadow> shadows) => shadows.single.color.a;

    expect(alphaOf(GbmEffects.shadowSm(Brightness.dark)), closeTo(0.4, 1e-3));
    expect(alphaOf(GbmEffects.shadowMd(Brightness.dark)), closeTo(0.5, 1e-3));
    expect(alphaOf(GbmEffects.shadowLg(Brightness.dark)), closeTo(0.6, 1e-3));
    expect(alphaOf(GbmEffects.shadowSm(Brightness.light)), closeTo(0.08, 1e-3));
    expect(alphaOf(GbmEffects.shadowMd(Brightness.light)), closeTo(0.12, 1e-3));
    expect(alphaOf(GbmEffects.shadowLg(Brightness.light)), closeTo(0.18, 1e-3));
  });
}
