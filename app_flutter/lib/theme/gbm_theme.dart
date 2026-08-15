import 'package:flutter/material.dart';

import 'tokens.dart';

/// Builds a [ThemeData] from a [GbmThemeVariant]'s [GbmColors] +
/// [GbmTypography]/[GbmSpacing] tokens. One function, not a class: there is
/// nothing stateful here, just a pure mapping from tokens to Flutter's
/// theming types.
ThemeData buildGbmTheme(GbmThemeVariant variant) {
  final GbmColors colors = tokensFor(variant);
  final Brightness brightness = variant == GbmThemeVariant.darkTechnical
      ? Brightness.dark
      : Brightness.light;

  final ColorScheme colorScheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: colors.textOnAccent,
    secondary: colors.accentSubtle,
    onSecondary: colors.textPrimary,
    error: colors.danger,
    onError: colors.textOnAccent,
    surface: colors.surfacePanel,
    onSurface: colors.textPrimary,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: colors.surfaceApp,
    canvasColor: colors.surfaceApp,
    dividerColor: colors.borderSubtle,
    fontFamily: GbmTypography.fontUi,
    splashFactory: NoSplash.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surfacePanel,
      foregroundColor: colors.textPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    textTheme: TextTheme(
      bodySmall: TextStyle(
        fontSize: GbmTypography.textXs,
        color: colors.textTertiary,
        height: GbmTypography.leadingNormal,
      ),
      bodyMedium: TextStyle(
        fontSize: GbmTypography.textBase,
        color: colors.textPrimary,
        height: GbmTypography.leadingNormal,
      ),
      bodyLarge: TextStyle(
        fontSize: GbmTypography.textMd,
        color: colors.textPrimary,
        height: GbmTypography.leadingNormal,
      ),
      titleMedium: TextStyle(
        fontSize: GbmTypography.textLg,
        fontWeight: GbmTypography.weightSemibold,
        color: colors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: GbmTypography.textXl,
        fontWeight: GbmTypography.weightSemibold,
        color: colors.textPrimary,
      ),
      labelMedium: TextStyle(
        fontSize: GbmTypography.textSm,
        fontWeight: GbmTypography.weightMedium,
        color: colors.textSecondary,
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[colors],
  );
}

/// Convenience accessor, e.g. `context.gbmColors.accent`.
extension GbmThemeContext on BuildContext {
  GbmColors get gbmColors => Theme.of(this).extension<GbmColors>()!;
}
