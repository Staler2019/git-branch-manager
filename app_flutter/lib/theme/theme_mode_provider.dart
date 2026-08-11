import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Light/dark/system, the Dart analog of `ThemeManager` (src/app/bridge/
/// ThemeManager.h). `MaterialApp.router`'s own `theme`/`darkTheme`/
/// `themeMode` trio resolves "system" against the OS, so this provider only
/// needs to hold the user's choice -- see app.dart for where `theme`/
/// `darkTheme` are wired to `GbmThemeVariant.lightIde`/`.darkTechnical`.
///
/// `GbmThemeVariant.neutralProfessional` (see theme/tokens.dart) is a third,
/// alternate light look ported from the design doc but not yet wired into
/// this toggle -- Preferences (M8, `features/dialogs/preferences`) is where
/// a user picks it explicitly, the same way ThemeManager's own light variant
/// choice is a settings option rather than something "system" selects.
final StateProvider<ThemeMode> themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
