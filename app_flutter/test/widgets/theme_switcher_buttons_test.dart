// Verifies ThemeSwitcherButtons offers one swatch per shipped variant and
// that the Dim gray swatch reaches the provider -- the list is hand-written,
// so a new enum value is not on screen until someone adds it here.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_icon_button.dart';
import 'package:gbm_flutter/widgets/theme_switcher_buttons.dart';

import '../support/pump_app.dart';

void main() {
  testWidgets('one swatch per variant', (WidgetTester tester) async {
    await pumpGbmWidget(tester, child: const ThemeSwitcherButtons());
    expect(
      find.byType(GbmIconButton),
      findsNWidgets(GbmThemeVariant.values.length),
    );
  });

  testWidgets('the Dim gray swatch selects dimGray', (
    WidgetTester tester,
  ) async {
    final ProviderContainer container = await pumpGbmWidget(
      tester,
      child: const ThemeSwitcherButtons(),
    );
    expect(container.read(themeVariantProvider), GbmThemeVariant.darkTechnical);

    await tester.tap(find.byTooltip('Dim gray'));
    await tester.pump();

    expect(container.read(themeVariantProvider), GbmThemeVariant.dimGray);
    expect(find.byIcon(Icons.brightness_4_outlined), findsOneWidget);
  });
}
