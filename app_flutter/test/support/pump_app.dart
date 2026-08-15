import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shared widget test harness for testing GBM components.
///
/// Sets up:
/// - SharedPreferences mock with caller overrides merged into ProviderContainer
/// - UncontrolledProviderScope with the merged container
/// - MaterialApp with the requested theme variant
/// - Optional Scaffold wrapping for convenience
///
/// Returns the ProviderContainer so tests can call `container.read(...)` to
/// inspect state after pumpWidget.
///
/// Example:
/// ```dart
/// testWidgets('button renders with primary styling', (tester) async {
///   await pumpGbmWidget(
///     tester,
///     child: GbmButton(label: 'Push', onPressed: () {}),
///     variant: GbmThemeVariant.darkTechnical,
///   );
///   expect(find.text('Push'), findsOneWidget);
/// });
/// ```
Future<ProviderContainer> pumpGbmWidget(
  WidgetTester tester, {
  required Widget child,
  GbmThemeVariant variant = GbmThemeVariant.darkTechnical,
  List<Override> overrides = const [],
  bool wrapInScaffold = true,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  // Merge caller overrides with the mandatory sharedPreferencesProvider
  // override. If the caller also overrides sharedPreferencesProvider, their
  // override takes precedence (override order: caller first, then defaults).
  final List<Override> mergedOverrides = <Override>[
    sharedPreferencesProvider.overrideWithValue(prefs),
    ...overrides,
  ];

  final ProviderContainer container = ProviderContainer(
    overrides: mergedOverrides,
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(variant),
        home: wrapInScaffold ? Scaffold(body: child) : child,
      ),
    ),
  );

  return container;
}
