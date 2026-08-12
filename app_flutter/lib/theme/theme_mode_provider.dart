import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'tokens.dart';

/// Provided by `main()` before `runApp()` (SharedPreferences.getInstance()
/// is itself async, so it cannot be resolved lazily inside a provider the
/// way `gbmBindingsProvider` resolves `GbmBindings.open()`). Throwing when
/// unoverridden makes a missing override in main.dart/tests fail loudly
/// instead of silently losing persistence.
final Provider<SharedPreferences>
sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError(
    'sharedPreferencesProvider must be overridden with a real SharedPreferences instance',
  );
});

const String _kThemeVariantKey = 'themeVariant';

/// The design doc's top-bar theme swatches switch the active
/// [GbmThemeVariant] directly -- there is no "system" option, unlike the
/// Flutter-native `ThemeMode` this replaces (see this provider's git
/// history for the old light/dark/system shape). Persisted the same way
/// the old controller persisted its choice (`SharedPreferences`), under a
/// new key so a stale `'light'`/`'dark'` string from before this change
/// does not get misread as a variant name.
class ThemeVariantController extends StateNotifier<GbmThemeVariant> {
  ThemeVariantController(this._prefs) : super(_readSaved(_prefs));

  final SharedPreferences _prefs;

  /// Design doc default is `dark-technical`; an unset or unrecognized
  /// stored value (including a pre-migration `'light'`/`'dark'`/`'system'`
  /// leftover from the old `ThemeMode`-keyed storage) falls back to it
  /// rather than guessing at an equivalent.
  static GbmThemeVariant _readSaved(SharedPreferences prefs) {
    return switch (prefs.getString(_kThemeVariantKey)) {
      'lightIde' => GbmThemeVariant.lightIde,
      'neutralProfessional' => GbmThemeVariant.neutralProfessional,
      'darkTechnical' => GbmThemeVariant.darkTechnical,
      _ => GbmThemeVariant.darkTechnical,
    };
  }

  void setVariant(GbmThemeVariant variant) {
    state = variant;
    unawaited(_prefs.setString(_kThemeVariantKey, variant.name));
  }
}

final StateNotifierProvider<ThemeVariantController, GbmThemeVariant>
themeVariantProvider =
    StateNotifierProvider<ThemeVariantController, GbmThemeVariant>(
      (ref) => ThemeVariantController(ref.watch(sharedPreferencesProvider)),
    );
