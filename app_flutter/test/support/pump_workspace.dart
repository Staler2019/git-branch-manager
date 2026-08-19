// Shared harness for pumping the real WorkspaceScreen behind a GoRouter,
// backed by a FakeRepoSessionController -- generalizes the local `_pump`
// helper menu_bar_row_test.dart hand-rolled (GoRouter + MaterialApp.router
// + optional WorkspaceActionShortcuts wrapper), extended to pump the
// screen itself so a test can dispatch through the real
// WorkspaceScreen._buildActionHandlers() instead of a hand-fed handler map.
//
// `isMacOS` is always passed explicitly as `false` unless the caller
// overrides it -- WorkspaceScreen.isMacOS's doc comment explains why this
// can't rely on Platform.isMacOS in CI.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fake_repo_session.dart';

/// Result of [pumpWorkspace]: the [ProviderContainer] for reading/overriding
/// other providers, and the [FakeRepoSessionController] driving the pumped
/// session -- call `controller.emit(...)` to simulate a state transition,
/// or inspect `controller.commandLog` to assert a dispatched action reached
/// the controller.
class PumpedWorkspace {
  const PumpedWorkspace(this.container, this.controller, this.router);

  final ProviderContainer container;
  final FakeRepoSessionController controller;
  final GoRouter router;
}

/// Pumps the real [WorkspaceScreen] for [identity], routed behind a
/// minimal [GoRouter] (history + working-copy children, matching
/// `app_router.dart`'s ShellRoute shape) with [initialState] as the
/// starting [RepoSessionState].
///
/// [extraRoutes] lets a specific test add the one or two ShellRoute-child
/// routes it actually exercises (e.g. the Compare tab route for a
/// tab-switching test) without this shared harness having to replicate all
/// of `app_router.dart`'s ShellRoute children up front.
///
/// [topLevelRoutes] is the equivalent for routes that, in the real router,
/// are siblings of the ShellRoute rather than children of it -- every
/// `dialogRoute(...)` entry (credential/checkout-recovery/
/// delete-branch-recovery/...) and the standalone `conflicts` route that
/// renders [ConflictResolveWindow] (see `app_router.dart`'s "Dialog routes
/// are top-level" comment). Adding one of these to [extraRoutes] instead
/// would nest it under [WorkspaceScreen] as if it were `child`, which is not
/// how the real router resolves it and would let a test pass for the wrong
/// reason.
///
/// `gbmBindingsProvider` is overridden with the same [FakeGbmBindings] the
/// controller uses, so any provider this harness forgot to override throws
/// loudly (via `noSuchMethod`) instead of silently dlopen'ing the real
/// native library.
Future<PumpedWorkspace> pumpWorkspace(
  WidgetTester tester, {
  required RepoIdentity identity,
  // isOpen: true by default -- WorkspaceScreen.build() renders a bare
  // "Opening repository…" Scaffold (no menu bar, no shortcuts, no
  // sidebar) whenever isOpen is false, so most tests want a session that
  // is already open. Pass RepoSessionState(isOpen: false) explicitly for
  // the few tests that want that fallback screen instead.
  RepoSessionState initialState = const RepoSessionState(isOpen: true),
  bool isMacOS = false,
  List<Override> overrides = const <Override>[],
  List<RouteBase> extraRoutes = const <RouteBase>[],
  List<RouteBase> topLevelRoutes = const <RouteBase>[],

  /// Overrides the working-copy ShellRoute child's builder, normally a bare
  /// empty [Scaffold]. A test that needs the real [WorkingCopyView] mounted
  /// (e.g. to prove commit-draft state survives a History<->Working-Copy
  /// round trip) can't add it via [extraRoutes]: `RoutePaths.workingCopy` is
  /// already registered below, and go_router rejects a second [GoRoute] at
  /// the same path. This swaps that one route's builder in place instead.
  Widget Function(BuildContext, GoRouterState)? workingCopyBuilder,

  /// Same as [workingCopyBuilder], for the History ShellRoute child --
  /// swaps in the real [HistoryPage] for a test that needs to navigate to
  /// it and assert on its actual rendered content (e.g. that the shared
  /// [fileListViewModeProvider] carries over across a History<->Working-Copy
  /// round trip), rather than the bare empty [Scaffold] most tests get.
  Widget Function(BuildContext, GoRouterState)? historyBuilder,
  ui.Size surfaceSize = const ui.Size(1400, 900),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController controller = FakeRepoSessionController(
    identity,
    initialState,
  );

  final String repoId = Uri.encodeComponent(identity.workDir);
  final GoRouter router = GoRouter(
    initialLocation: RoutePaths.historyFor(repoId),
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.welcome,
        builder: (context, state) => const Scaffold(body: SizedBox()),
      ),
      ShellRoute(
        builder: (context, state, child) {
          return WorkspaceScreen(
            identity: identity,
            isMacOS: isMacOS,
            child: child,
          );
        },
        routes: <RouteBase>[
          GoRoute(
            path: RoutePaths.history,
            builder:
                historyBuilder ??
                (context, state) => const Scaffold(body: SizedBox()),
          ),
          GoRoute(
            path: RoutePaths.workingCopy,
            builder:
                workingCopyBuilder ??
                (context, state) => const Scaffold(body: SizedBox()),
          ),
          ...extraRoutes,
        ],
      ),
      ...topLevelRoutes,
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      gbmBindingsProvider.overrideWithValue(FakeGbmBindings()),
      repoSessionProvider(identity).overrideWith((ref) => controller),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return PumpedWorkspace(container, controller, router);
}
