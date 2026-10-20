import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/repositories/build_version_repository.dart';
import 'package:gbm_flutter/features/dialogs/about/about_dialog.dart';
import 'package:gbm_flutter/routing/app_router.dart';
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

      expect(find.text('版本 0.30.0'), findsOneWidget);
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

      expect(find.text('開發版本'), findsOneWidget);
      expect(find.textContaining('0.0.0'), findsNothing);
    });

    // Help has no Check for updates… item, in either window, so this button
    // is the whole entry surface for it (~~`WelcomeScreen` renders no menu
    // bar at all~~ -- it does since spec page 15 A, and Help → About opens
    // this dialog there too). Routed, not a callback, so it works
    // identically from either screen.
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

    // `?origin=` rides from About on to Update, so Update's log line lands
    // in the window the user started from (rulings R4, R13).
    testWidgets('passes its origin on to the update check', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final GoRouter router = GoRouter(
        initialLocation: RoutePaths.aboutDialogPath(originWorkDir: '/src/r'),
        routes: <RouteBase>[
          aboutDialogRoute(),
          dialogRoute(
            path: RoutePaths.updateDialog,
            builder: (BuildContext context, GoRouterState state) =>
                Text('update from ${state.uri.queryParameters['origin']}'),
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
      await tester.tap(find.text('Check for updates…'));
      await tester.pumpAndSettle();

      expect(find.text('update from /src/r'), findsOneWidget);
    });

    testWidgets('keeps the existing description', (WidgetTester tester) async {
      await pumpGbmWidget(
        tester,
        child: const AboutDialogContent(),
        overrides: <Override>[
          buildVersionProvider.overrideWithValue(const AppVersion(1, 2, 3)),
        ],
      );

      expect(find.text('給超大型 repository 用的快速 Git 客戶端。'), findsOneWidget);
    });
  });
}
