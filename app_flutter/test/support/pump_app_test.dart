import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'pump_app.dart';

void main() {
  testWidgets('pumpGbmWidget renders child', (tester) async {
    await pumpGbmWidget(tester, child: const Text('test content'));
    expect(find.text('test content'), findsOneWidget);
  });

  testWidgets('pumpGbmWidget applies requested theme variant', (tester) async {
    const variant = GbmThemeVariant.lightIde;
    await pumpGbmWidget(tester, child: const Text('test'), variant: variant);
    final materialApp =
        find.byType(MaterialApp).evaluate().single.widget as MaterialApp;
    expect(materialApp.theme, buildGbmTheme(variant));
  });

  testWidgets('pumpGbmWidget wraps child in Scaffold by default', (
    tester,
  ) async {
    await pumpGbmWidget(tester, child: const Text('test'));
    expect(find.byType(Scaffold), findsOneWidget);
  });

  testWidgets(
    'pumpGbmWidget does not wrap in Scaffold when wrapInScaffold is false',
    (tester) async {
      await pumpGbmWidget(
        tester,
        child: const Text('test'),
        wrapInScaffold: false,
      );
      expect(find.byType(Scaffold), findsNothing);
    },
  );

  testWidgets('pumpGbmWidget returns container for state inspection', (
    tester,
  ) async {
    final container = await pumpGbmWidget(tester, child: const Text('test'));
    expect(container, isNotNull);
    expect(container.read(sharedPreferencesProvider), isNotNull);
  });

  testWidgets(
    'pumpGbmWidget merges caller overrides with SharedPreferences override',
    (tester) async {
      final container = await pumpGbmWidget(
        tester,
        child: const Text('test'),
        overrides: const [],
      );
      // Both the default SharedPreferences override and caller overrides
      // are merged in the container
      expect(container.read(sharedPreferencesProvider), isNotNull);
    },
  );
}
