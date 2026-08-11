import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Provided by `main()` before `runApp()` (SharedPreferences.getInstance()
/// is itself async, so it cannot be resolved lazily inside a provider the
/// way `gbmBindingsProvider` resolves `GbmBindings.open()`). Throwing when
/// unoverridden makes a missing override in main.dart/tests fail loudly
/// instead of silently losing persistence.
final Provider<SharedPreferences> sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden with a real SharedPreferences instance');
});

const String _kThemeModeKey = 'themeMode';

/// Light/dark/system, the Dart analog of `ThemeManager` (src/app/bridge/
/// ThemeManager.h), persisted the same way `ThemeManager` persists its own
/// choice (`ThemeManager` uses `QSettings`; here, `SharedPreferences`).
/// `MaterialApp.router`'s own `theme`/`darkTheme`/`themeMode` trio resolves
/// "system" against the OS, so this only needs to hold and persist the
/// user's choice -- see app.dart for where `theme`/`darkTheme` are wired to
/// `GbmThemeVariant.lightIde`/`.darkTechnical`.
///
/// `GbmThemeVariant.neutralProfessional` (see theme/tokens.dart) is a third,
/// alternate light look ported from the design doc but not yet wired into
/// this toggle -- `features/dialogs/preferences` is where a user picks it
/// explicitly, the same way ThemeManager's own light variant choice is a
/// settings option rather than something "system" selects.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._prefs) : super(_readSaved(_prefs));

  final SharedPreferences _prefs;

  static ThemeMode _readSaved(SharedPreferences prefs) {
    return switch (prefs.getString(_kThemeModeKey)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  void setThemeMode(ThemeMode mode) {
    state = mode;
    unawaited(_prefs.setString(_kThemeModeKey, mode.name));
  }
}

final StateNotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
      (ref) => ThemeModeController(ref.watch(sharedPreferencesProvider)),
    );
