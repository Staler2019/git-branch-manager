// Verifies ThemeVariantController: default variant, persistence under the
// new 'themeVariant' key, and migration of a stale pre-migration value
// (the old ThemeMode-keyed 'themeMode'/'light'/'dark'/'system' storage this
// replaced) to the design doc's default (dark-technical).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults to darkTechnical when nothing is stored', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ThemeVariantController controller = ThemeVariantController(prefs);
    expect(controller.state, GbmThemeVariant.darkTechnical);
  });

  test(
    'a stale pre-migration value falls back to darkTechnical, not a crash',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'themeMode': 'light',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ThemeVariantController controller = ThemeVariantController(prefs);
      expect(controller.state, GbmThemeVariant.darkTechnical);
    },
  );

  test('reads a previously-persisted variant under the new key', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'themeVariant': 'neutralProfessional',
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ThemeVariantController controller = ThemeVariantController(prefs);
    expect(controller.state, GbmThemeVariant.neutralProfessional);
  });

  test('setVariant updates state and persists under the new key', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ThemeVariantController controller = ThemeVariantController(prefs);
    controller.setVariant(GbmThemeVariant.lightIde);
    expect(controller.state, GbmThemeVariant.lightIde);
    expect(prefs.getString('themeVariant'), 'lightIde');
  });

  test(
    'themeVariantProvider resolves through sharedPreferencesProvider override',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'themeVariant': 'lightIde',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(themeVariantProvider), GbmThemeVariant.lightIde);
    },
  );
}
