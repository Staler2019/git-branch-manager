// Shared harness for the spec page 19 management panels.
//
// Every panel is the same shape -- GbmPanelTabShell with a toolbar, a left
// list and a right detail pane -- so every panel test needs the same three
// things: a fake session carrying the panel's data, a SharedPreferences
// override (GbmSplitPane reads it in initState to restore the splitter, so
// the shell cannot mount without one), and a surface wide enough that the
// two columns both have room.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity panelTestIdentity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

/// What [pumpPanel] hands back: the fake controller (inspect
/// `commandLog` to assert a toolbar action reached the session) and the
/// container (to read other providers).
class PumpedPanel {
  const PumpedPanel(this.container, this.fake, this.router);

  final ProviderContainer container;
  final FakeRepoSessionController fake;
  final GoRouter router;
}

/// Pumps [panel] behind a minimal GoRouter with [state] as the session.
///
/// A router is always present, not just for panels that navigate: several
/// panels push a dialog from their toolbar, and `context.push` on a widget
/// with no Router above it throws rather than failing the assertion the
/// test actually wrote.
Future<PumpedPanel> pumpPanel(
  WidgetTester tester,
  Widget panel, {
  required RepoSessionState state,
  List<Override> overrides = const <Override>[],
  List<RouteBase> extraRoutes = const <RouteBase>[],
  Size surfaceSize = const Size(1200, 800),
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    panelTestIdentity,
    state,
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(panelTestIdentity).overrideWith((ref) => fake),
      ...overrides,
    ],
  );
  addTearDown(container.dispose);

  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(body: panel),
      ),
      ...extraRoutes,
    ],
  );
  addTearDown(router.dispose);

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
  return PumpedPanel(container, fake, router);
}

/// The toolbar [GbmButton] whose label is [label] -- panels gate their
/// toolbar on the current selection, so `onPressed == null` is the
/// assertion most of these tests care about.
GbmButton panelButton(WidgetTester tester, String label) =>
    tester.widget<GbmButton>(
      find.ancestor(of: find.text(label), matching: find.byType(GbmButton)),
    );
