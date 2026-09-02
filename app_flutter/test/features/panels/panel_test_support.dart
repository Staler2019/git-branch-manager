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
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_toolbar_spec.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
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
  Map<String, Object> initialPrefs = const <String, Object>{},
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  SharedPreferences.setMockInitialValues(initialPrefs);
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

/// Asserts the spec page 19 template facts that are **per panel**, so all
/// twelve state them the same way instead of twelve hand-copied blocks that
/// drift exactly the way twelve hand-copied toolbars did.
///
/// Deliberately *not* here: the 36px row height and the 78px label column.
/// Those belong to `PanelListRow` and `PanelDetailField`, are pinned once
/// each in `panel_list_row_test.dart` and `panel_widgets_test.dart`, and
/// re-asserting them per panel would be twelve tests of one shared widget
/// ([CULT-single-source-of-truth] applied to the tests).
///
/// [primary] / [maintenance] / [external] are button labels in rule 2's
/// segment order; membership is asserted **positionally**, because a label
/// merely being on the toolbar says nothing about which segment drew it.
/// [notOnToolbar] is the rule's other half — the destructive labels that
/// must be absent — and passing the panel's own danger label there is what
/// makes 「破壞性動作不放工具列」 falsifiable rather than assumed.
/// [dangerOnToolbar] names the labels that sit in [maintenance] but are
/// deliberately `danger`-styled rather than ghost.
///
/// It is a **declaration that this panel has a ratified exception**, not a
/// way to relax the segment rule: a label not named here is still held to
/// its segment's kind, and a label named here is held to `danger`, so
/// restyling it silently reddens either way. Two panels use it —
/// interactive-rebase's `Abort` and bisect's `Reset` — because both stay on
/// the toolbar under rule 2 (they restore a prior state rather than
/// destroying work, so they are not 破壞性) while still being the one button
/// on the panel a user should hesitate over.
void expectPanelTemplate(
  WidgetTester tester, {
  List<String> primary = const <String>[],
  List<String> maintenance = const <String>[],
  List<String> external = const <String>[],
  List<String> notOnToolbar = const <String>[],
  Set<String> dangerOnToolbar = const <String>{},
  required String listHeader,
  required Pattern statusBar,
  bool filterEnabled = true,
}) {
  final Finder toolbar = find.byType(PanelToolbarRow);
  expect(toolbar, findsOneWidget, reason: 'rule 2: every panel has a toolbar');

  double leftEdgeOf(String label) => tester
      .getRect(
        find.ancestor(
          of: find.descendant(of: toolbar, matching: find.text(label)),
          matching: find.byType(GbmButton),
        ),
      )
      .left;

  for (final (List<String> segment, GbmButtonKind kind)
      in <(List<String>, GbmButtonKind)>[
        (primary, GbmButtonKind.primary),
        (maintenance, GbmButtonKind.ghost),
      ]) {
    for (final String label in segment) {
      expect(
        find.descendant(of: toolbar, matching: find.text(label)),
        findsOneWidget,
        reason: '「$label」 is missing from the toolbar',
      );
      expect(
        panelButton(tester, label).kind,
        dangerOnToolbar.contains(label) ? GbmButtonKind.danger : kind,
        reason: '「$label」 has the wrong button kind for its segment',
      );
    }
  }

  // Segment *order*, asserted as left-to-right position rather than as list
  // membership -- a spec that fixes the order is not satisfied by a toolbar
  // that merely contains the right buttons.
  final List<String> ordered = <String>[
    ...primary,
    ...maintenance,
    ...external,
  ];
  for (int i = 1; i < ordered.length; i++) {
    expect(
      leftEdgeOf(ordered[i - 1]),
      lessThan(leftEdgeOf(ordered[i])),
      reason: '「${ordered[i - 1]}」 must sit left of 「${ordered[i]}」',
    );
  }

  for (final String label in notOnToolbar) {
    expect(
      find.descendant(of: toolbar, matching: find.textContaining(label)),
      findsNothing,
      reason: 'rule 2: 破壞性動作不放工具列 -- 「$label」 is on the toolbar',
    );
  }

  // 「分隔線」 separates the external segment from what precedes it, and is
  // drawn only when it really separates two occupied segments.
  expect(
    find.descendant(of: toolbar, matching: find.byType(PanelToolbarSeparator)),
    external.isNotEmpty && (primary.isNotEmpty || maintenance.isNotEmpty)
        ? findsOneWidget
        : findsNothing,
  );

  // 「右端固定是 filter」 -- against the toolbar's own right edge, never a
  // pixel constant ([FLU-finder-proves-existence-not-position]).
  final Finder filter = find.byType(PanelFilterField);
  expect(filter, findsOneWidget);
  expect(
    tester.getRect(filter).right,
    closeTo(tester.getRect(toolbar).right - GbmSpacing.space3, 0.5),
  );
  // A filter that cannot be typed into must *say* so rather than simply not
  // work -- 隱藏會讓人以為功能不存在 ([FLU-menu-enabled-is-visual-only]).
  expect(
    tester.widget<PanelFilterField>(filter).enabled,
    filterEnabled,
    reason: filterEnabled
        ? 'this panel has nameable items, so its filter is live'
        : 'a panel whose list is file content has no names to filter',
  );

  // Rules 3 and 6: the counted list header and the status line, which is
  // where 實際數量與耗時 goes.
  expect(find.text(listHeader), findsOneWidget);
  expect(
    find.descendant(
      of: find.byType(PanelStatusBarText),
      matching: find.textContaining(statusBar),
    ),
    findsOneWidget,
  );
}

/// Rule 4's action row: the danger action sits against the **detail
/// column's** right edge.
///
/// Asserted as an edge equality rather than 「danger is to the right」, which
/// is true under `spaceBetween` *and* under `start` and so proves nothing
/// ([TEST-fixture-cannot-disagree] shape 8).
void expectDangerPinnedRight(WidgetTester tester, String label) {
  final Finder row = find.byType(PanelDetailActions);
  expect(row, findsOneWidget, reason: 'rule 4: 動作列在明細底部');

  final GbmButton button = panelButton(tester, label);
  expect(button.kind, GbmButtonKind.danger);

  final Rect danger = tester.getRect(
    find.ancestor(of: find.text(label), matching: find.byType(GbmButton)),
  );
  expect(
    danger.right,
    closeTo(tester.getRect(row).right - GbmSpacing.space3, 0.5),
  );
}
