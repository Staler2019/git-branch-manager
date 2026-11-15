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

  for (final GbmThemeVariant variant in GbmThemeVariant.values) {
    test('scrollbar thumb is the scrollbarThumb token ($variant)', () {
      // spec: `::-webkit-scrollbar-thumb{background:var(--scrollbar-thumb)}`.
      // Unset, every Scrollbar painted Material's onSurface-derived default.
      final ThemeData theme = buildGbmTheme(variant);
      expect(
        theme.scrollbarTheme.thumbColor?.resolve(<WidgetState>{})?.toARGB32(),
        tokensFor(variant).scrollbarThumb.toARGB32(),
      );
    });
  }

  test('light-ide link and accent hover are the spec accent-600', () {
    // colors.css `[data-theme="light-ide"]`: `--text-link:#1f6ce0;
    // --accent-hover:#1f6ce0`. The Qt port had it (ThemeTokens.cpp kLightIde);
    // the Flutter port wrote accent-700 with no ruling behind it.
    final GbmColors colors = tokensFor(GbmThemeVariant.lightIde);
    expect(colors.textLink.toARGB32(), 0xFF1F6CE0);
    expect(colors.accentHover.toARGB32(), 0xFF1F6CE0);
  });

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
