import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/repositories/build_version_repository.dart';
import 'package:gbm_flutter/features/dialogs/about/about_dialog.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/pump_app.dart';

void main() {
  group('AboutDialogContent', () {
    testWidgets('shows the running release version', (
      WidgetTester tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: const AboutDialogContent(),
        overrides: <Override>[
          buildVersionProvider.overrideWithValue(const AppVersion(0, 30, 0)),
        ],
      );

      expect(find.text('Version 0.30.0'), findsOneWidget);
    });

    // The `flutter run` case. Rendering "Version 0.0.0" here would be a lie
    // about which build is running, and the update flow reads the same
    // provider to decide it must not offer to replace this build.
    testWidgets('names a developer build instead of inventing a version', (
      WidgetTester tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: const AboutDialogContent(),
        overrides: <Override>[buildVersionProvider.overrideWithValue(null)],
      );

      expect(find.text('Development build'), findsOneWidget);
      expect(find.textContaining('0.0.0'), findsNothing);
    });

    // `WelcomeScreen` renders no menu bar at all, so Help → Check for
    // updates… is unreachable with no repository open. This button is the
    // whole entry surface in that state -- routed, not a callback, so it
    // works identically from either screen.
    testWidgets('offers a route to the update check', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final GoRouter router = GoRouter(
        initialLocation: RoutePaths.aboutDialog,
        routes: <RouteBase>[
          dialogRoute(
            path: RoutePaths.aboutDialog,
            builder: (BuildContext context, GoRouterState state) =>
                const AboutDialogContent(),
          ),
          dialogRoute(
            path: RoutePaths.updateDialog,
            builder: (BuildContext context, GoRouterState state) =>
                const Text('update-dialog'),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            buildVersionProvider.overrideWithValue(const AppVersion(0, 30, 0)),
          ],
          child: MaterialApp.router(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('update-dialog'), findsNothing);

      await tester.tap(find.text('Check for updates…'));
      await tester.pumpAndSettle();

      expect(find.text('update-dialog'), findsOneWidget);
    });

    testWidgets('keeps the existing description', (WidgetTester tester) async {
      await pumpGbmWidget(
        tester,
        child: const AboutDialogContent(),
        overrides: <Override>[
          buildVersionProvider.overrideWithValue(const AppVersion(1, 2, 3)),
        ],
      );

      expect(
        find.text('A fast Git client for very large repositories.'),
        findsOneWidget,
      );
    });
  });
}
