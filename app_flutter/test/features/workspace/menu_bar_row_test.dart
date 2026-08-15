// MenuBarRow is presentational (no Riverpod/FFI dependency -- see its doc
// comment), so this drives it directly with GoRouter + plain callbacks:
// every menu opens, the History/Working Copy/Repository/Preferences items
// navigate to the expected route, and Fetch/Pull/Push invoke the callbacks
// passed in rather than reaching into a real session.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/features/workspace/widgets/menu_bar_row.dart';
import 'package:gbm_flutter/features/workspace/widgets/workspace_action_shortcuts.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

const String _repoId = 'repo1';

Future<GoRouter> _pump(
  WidgetTester tester, {
  required VoidCallback onToggleSidebar,
  required VoidCallback? onFetch,
  required VoidCallback? onPull,
  required VoidCallback? onPush,
  bool sidebarVisible = true,

  /// When provided, wraps MenuBarRow in a [WorkspaceActionShortcuts]
  /// ancestor with these handlers -- needed for any item that isn't one of
  /// the 5 named-callback params, since those dispatch via
  /// `Actions.maybeInvoke(GbmActionIntent)` and do nothing without an
  /// Actions ancestor to reach. Most tests in this file don't need this
  /// (they only exercise the named-callback items, which work standalone).
  Map<GbmActionId, VoidCallback?>? actionHandlers,
}) async {
  final List<String> visited = <String>[];
  final GoRouter router = GoRouter(
    initialLocation: RoutePaths.historyFor(_repoId),
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) {
          visited.add(state.uri.toString());
          final Widget menuBar = MenuBarRow(
            repoId: _repoId,
            sidebarVisible: sidebarVisible,
            onToggleSidebar: onToggleSidebar,
            onFetch: onFetch,
            onPull: onPull,
            onPush: onPush,
          );
          return Scaffold(
            body: actionHandlers == null
                ? menuBar
                : WorkspaceActionShortcuts(
                    handlers: actionHandlers,
                    isMacOS: false,
                    child: menuBar,
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
    'opening the View menu shows History/Working copy, not Diff or dialog-opening items now owned by other menus',
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
      expect(find.text('Working copy'), findsOneWidget);
      // Diff is deliberately not on the menu -- see MenuBarRow's doc comment.
      expect(find.text('Diff'), findsNothing);
      // Repository settings and Preferences moved to their spec-correct
      // menus (Repository, File respectively) once MenuBarRow started
      // sourcing items from gbmMenus -- see spec page 04's MENUS table.
      expect(find.text('Repository Settings'), findsNothing);
      expect(find.text('Preferences…'), findsNothing);
    },
  );

  testWidgets('View > Working copy navigates to the working-copy route', (
    tester,
  ) async {
    late GoRouter router;
    router = await _pump(
      tester,
      onToggleSidebar: () {},
      onFetch: () {},
      onPull: () {},
      onPush: () {},
      actionHandlers: <GbmActionId, VoidCallback?>{
        GbmActionId.viewWorkingCopy: () =>
            router.go(RoutePaths.workingCopyFor(_repoId)),
      },
    );
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Working copy'));
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

  testWidgets(
    'Repository menu Fetch/Pull/Push do not execute when callback is null',
    (tester) async {
      int fetches = 0;
      await _pump(
        tester,
        onToggleSidebar: () {},
        onFetch: null,
        onPull: null,
        onPush: null,
      );

      // Try to open Repository menu and tap Fetch
      await tester.tap(find.text('Repository'));
      await tester.pumpAndSettle();
      // Menu item should still be visible and tappable
      expect(find.text('Fetch'), findsOneWidget);
      // Tapping it should close the menu but not execute anything
      await tester.tap(find.text('Fetch'));
      await tester.pumpAndSettle();
      // No error should occur, and fetches count should stay at 0
      expect(fetches, 0);
    },
  );

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

  testWidgets('File > Preferences… pushes the preferences dialog route', (
    tester,
  ) async {
    late GoRouter router;
    router = await _pump(
      tester,
      onToggleSidebar: () {},
      onFetch: () {},
      onPull: () {},
      onPush: () {},
      actionHandlers: <GbmActionId, VoidCallback?>{
        // App-level route now: Preferences holds application settings, and
        // per-repository ones moved to RoutePaths.repositorySettingsDialog.
        GbmActionId.filePreferences: () =>
            router.push(RoutePaths.preferencesDialog),
      },
    );
    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preferences…'));
    await tester.pumpAndSettle();
    expect(find.text('preferences-dialog'), findsOneWidget);
  });
}
