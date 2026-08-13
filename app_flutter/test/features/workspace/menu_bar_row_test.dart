// MenuBarRow is presentational (no Riverpod/FFI dependency -- see its doc
// comment), so this drives it directly with GoRouter + plain callbacks:
// every menu opens, the History/Working Copy/Repository/Preferences items
// navigate to the expected route, and Fetch/Pull/Push invoke the callbacks
// passed in rather than reaching into a real session.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/workspace/widgets/menu_bar_row.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

const String _repoId = 'repo1';

Future<GoRouter> _pump(
  WidgetTester tester, {
  required VoidCallback onToggleSidebar,
  required VoidCallback onFetch,
  required VoidCallback onPull,
  required VoidCallback onPush,
  bool sidebarVisible = true,
}) async {
  final List<String> visited = <String>[];
  final GoRouter router = GoRouter(
    initialLocation: RoutePaths.historyFor(_repoId),
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) {
          visited.add(state.uri.toString());
          return Scaffold(
            body: MenuBarRow(
              repoId: _repoId,
              sidebarVisible: sidebarVisible,
              onToggleSidebar: onToggleSidebar,
              onFetch: onFetch,
              onPull: onPull,
              onPush: onPush,
            ),
          );
        },
      ),
      GoRoute(
        path: RoutePaths.workingCopy,
        builder: (context, state) =>
            const Scaffold(body: Text('working-copy-page')),
      ),
      dialogRoute(
        path: RoutePaths.preferencesDialog,
        builder: (context, state) => const Text('preferences-dialog'),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      routerConfig: router,
    ),
  );
  return router;
}

/// A minimal stand-in for app_router.dart's own `dialogRoute` helper (a
/// plain overlay-style GoRoute) -- not importing app_router.dart itself to
/// avoid dragging in every other route's dependencies for this test.
GoRoute dialogRoute({
  required String path,
  required Widget Function(BuildContext, GoRouterState) builder,
}) {
  return GoRoute(path: path, builder: builder);
}

void main() {
  testWidgets(
    'opening the View menu shows History/Working Copy/Repository Settings/Preferences',
    (tester) async {
      await _pump(
        tester,
        onToggleSidebar: () {},
        onFetch: () {},
        onPull: () {},
        onPush: () {},
      );
      await tester.tap(find.text('View'));
      await tester.pumpAndSettle();
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Working Copy'), findsOneWidget);
      expect(find.text('Repository Settings'), findsOneWidget);
      expect(find.text('Preferences…'), findsOneWidget);
      // Diff is deliberately not on the menu -- see MenuBarRow's doc comment.
      expect(find.text('Diff'), findsNothing);
    },
  );

  testWidgets('View > Working Copy navigates to the working-copy route', (
    tester,
  ) async {
    await _pump(
      tester,
      onToggleSidebar: () {},
      onFetch: () {},
      onPull: () {},
      onPush: () {},
    );
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Working Copy'));
    await tester.pumpAndSettle();
    expect(find.text('working-copy-page'), findsOneWidget);
  });

  testWidgets('View > Toggle sidebar invokes the callback', (tester) async {
    bool toggled = false;
    await _pump(
      tester,
      onToggleSidebar: () => toggled = true,
      onFetch: () {},
      onPull: () {},
      onPush: () {},
    );
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Toggle sidebar'));
    await tester.pumpAndSettle();
    expect(toggled, isTrue);
  });

  testWidgets('Repository menu Fetch/Pull/Push invoke their callbacks', (
    tester,
  ) async {
    int fetches = 0;
    int pulls = 0;
    int pushes = 0;
    await _pump(
      tester,
      onToggleSidebar: () {},
      onFetch: () => fetches++,
      onPull: () => pulls++,
      onPush: () => pushes++,
    );

    await tester.tap(find.text('Repository'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fetch'));
    await tester.pumpAndSettle();
    expect(fetches, 1);

    await tester.tap(find.text('Repository'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pull'));
    await tester.pumpAndSettle();
    expect(pulls, 1);

    await tester.tap(find.text('Repository'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Push'));
    await tester.pumpAndSettle();
    expect(pushes, 1);
  });

  testWidgets('Branch menu marks Delete branch… as danger', (tester) async {
    await _pump(
      tester,
      onToggleSidebar: () {},
      onFetch: () {},
      onPull: () {},
      onPush: () {},
    );
    await tester.tap(find.text('Branch'));
    await tester.pumpAndSettle();
    final Text label = tester.widget<Text>(find.text('Delete branch…'));
    expect(label.style?.color, tokensFor(GbmThemeVariant.darkTechnical).danger);
  });

  testWidgets('File > Preferences pushes the preferences dialog route', (
    tester,
  ) async {
    await _pump(
      tester,
      onToggleSidebar: () {},
      onFetch: () {},
      onPull: () {},
      onPush: () {},
    );
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preferences'));
    await tester.pumpAndSettle();
    expect(find.text('preferences-dialog'), findsOneWidget);
  });
}
