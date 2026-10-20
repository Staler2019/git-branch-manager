// `?origin=` on the app-level dialogs: which window a dialog was opened over,
// so what it logs goes to that window's Log (rulings R4, R13). The clone
// dialog's convention: a raw work dir, absent for the window with none.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/dialogs/preferences/preferences_dialog.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

const String _workDir = '/src/my repo';

void main() {
  group('path builders', () {
    test('no origin is the bare route', () {
      expect(RoutePaths.aboutDialogPath(), RoutePaths.aboutDialog);
      expect(RoutePaths.updateDialogPath(), RoutePaths.updateDialog);
      expect(RoutePaths.preferencesDialogPath(), RoutePaths.preferencesDialog);
    });

    test('an origin rides as ?origin= and parses back intact', () {
      for (final String path in <String>[
        RoutePaths.aboutDialogPath(originWorkDir: _workDir),
        RoutePaths.updateDialogPath(originWorkDir: _workDir),
        RoutePaths.preferencesDialogPath(originWorkDir: _workDir),
      ]) {
        expect(Uri.parse(path).queryParameters['origin'], _workDir);
      }
      expect(
        Uri.parse(RoutePaths.aboutDialogPath(originWorkDir: _workDir)).path,
        RoutePaths.aboutDialog,
      );
      expect(
        Uri.parse(RoutePaths.updateDialogPath(originWorkDir: _workDir)).path,
        RoutePaths.updateDialog,
      );
    });

    test('Preferences carries section and origin together', () {
      final Uri uri = Uri.parse(
        RoutePaths.preferencesDialogPath(
          section: PreferencesSection.externalApps,
          originWorkDir: _workDir,
        ),
      );
      expect(uri.path, RoutePaths.preferencesDialog);
      expect(uri.queryParameters, <String, String>{
        'section': 'externalApps',
        'origin': _workDir,
      });
    });
  });

  group('originWorkDirOf', () {
    Future<GoRouter> pump(WidgetTester tester, String initial) async {
      final GoRouter router = GoRouter(
        initialLocation: initial,
        routes: <RouteBase>[
          GoRoute(
            path: RoutePaths.welcome,
            builder: (context, state) => const Text('welcome'),
          ),
          GoRoute(
            path: RoutePaths.history,
            builder: (context, state) => const Text('history'),
          ),
          dialogRoute(
            path: RoutePaths.aboutDialog,
            builder: (context, state) => const Text('about'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('the welcome screen has none', (tester) async {
      final GoRouter router = await pump(tester, RoutePaths.welcome);
      expect(originWorkDirOf(router), isNull);
    });

    // `%` included: go_router decodes path parameters itself, so a second
    // decode would throw on `100%` and misread `100%25`.
    for (final String dir in <String>[_workDir, '/a/100%', '/a/100%25x']) {
      testWidgets('a repository screen names its work dir: $dir', (
        tester,
      ) async {
        final GoRouter router = await pump(
          tester,
          RoutePaths.historyFor(repoIdFor(dir)),
        );
        expect(originWorkDirOf(router), dir);
      });
    }

    testWidgets('a dialog pushed over it does not change the answer', (
      tester,
    ) async {
      final GoRouter router = await pump(
        tester,
        RoutePaths.historyFor(repoIdFor(_workDir)),
      );
      pushDialogRouteOn(router, RoutePaths.aboutDialog);
      await tester.pumpAndSettle();
      expect(find.text('about'), findsOneWidget);
      expect(originWorkDirOf(router), _workDir);
    });
  });
}
