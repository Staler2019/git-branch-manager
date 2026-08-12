// Verifies TopBar's three theme swatches: the currently-active variant
// renders `active` (accentSubtle background per GbmIconButton), and tapping
// a swatch updates themeVariantProvider -- confirming neutralProfessional,
// which the old ThemeMode-based menu could never reach, is now selectable.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/workspace/widgets/top_bar.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_icon_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: TopBar(
            repoName: 'gbm',
            repoState: null,
            isRefreshing: false,
            onRefresh: () {},
            onBack: () {},
          ),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('the active variant swatch is marked active', (tester) async {
    final ProviderContainer container = await _pump(tester);
    expect(container.read(themeVariantProvider), GbmThemeVariant.darkTechnical);

    final List<GbmIconButton> buttons = tester
        .widgetList<GbmIconButton>(find.byType(GbmIconButton))
        .toList();
    expect(buttons.where((b) => b.active).length, 1);
    expect(buttons.firstWhere((b) => b.active).tooltip, 'Dark technical');
  });

  testWidgets('tapping the neutral-professional swatch selects it', (
    tester,
  ) async {
    final ProviderContainer container = await _pump(tester);
    await tester.tap(find.byTooltip('Neutral professional'));
    await tester.pump();
    expect(
      container.read(themeVariantProvider),
      GbmThemeVariant.neutralProfessional,
    );
  });

  testWidgets('tapping the light-ide swatch selects it', (tester) async {
    final ProviderContainer container = await _pump(tester);
    await tester.tap(find.byTooltip('Light IDE'));
    await tester.pump();
    expect(container.read(themeVariantProvider), GbmThemeVariant.lightIde);
  });
}
