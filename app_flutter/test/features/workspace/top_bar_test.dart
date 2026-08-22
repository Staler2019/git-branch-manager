// Two concerns:
//
// 1. TopBar's three theme swatches -- the currently-active variant renders
//    `active` (accentSubtle background per GbmIconButton), and tapping a
//    swatch updates themeVariantProvider, confirming neutralProfessional,
//    which the old ThemeMode-based menu could never reach, is selectable.
//
// 2. Narrow-window behaviour. `repoName` and `repoState.describe` used to be
//    non-flex Texts with no ellipsis, so a long repository name pushed the
//    Refresh button and theme swatches past the right edge and threw a
//    RenderFlex overflow. Unlike MenuBarRow/TabRow/StatusBar, which all wrap
//    their variable-width content in `Expanded > SingleChildScrollView`,
//    TopBar had no guard at all.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_state.dart' as model;
import 'package:gbm_flutter/features/workspace/widgets/top_bar.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_icon_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [width] null means "unconstrained" (the theme-swatch tests, which do not
/// care about layout). A number wraps TopBar in a SizedBox of that width,
/// which is how the narrow-window group drives the overflow path -- setting
/// tester.view.physicalSize would also resize the enclosing MaterialApp and
/// make the assertion about the harness rather than about TopBar.
Future<ProviderContainer> _pump(
  WidgetTester tester, {
  String repoName = 'gbm',
  model.RepoState? repoState,
  double? width,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: TopBar(
                repoName: repoName,
                repoState: repoState,
                isRefreshing: false,
                onRefresh: () {},
                onBack: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return container;
}

void main() {
  testWidgets('the active variant swatch is marked active', (tester) async {
    final ProviderContainer container = await _pump(tester);
    expect(container.read(themeVariantProvider), GbmThemeVariant.darkTechnical);

    final List<GbmIconButton> buttons = tester
        .widgetList<GbmIconButton>(find.byType(GbmIconButton))
        .toList();
    expect(buttons.where((b) => b.active).length, 1);
    expect(buttons.firstWhere((b) => b.active).tooltip, 'Dark technical');
  });

  testWidgets('tapping the neutral-professional swatch selects it', (
    tester,
  ) async {
    final ProviderContainer container = await _pump(tester);
    await tester.tap(find.byTooltip('Neutral professional'));
    await tester.pump();
    expect(
      container.read(themeVariantProvider),
      GbmThemeVariant.neutralProfessional,
    );
  });

  testWidgets('tapping the light-ide swatch selects it', (tester) async {
    final ProviderContainer container = await _pump(tester);
    await tester.tap(find.byTooltip('Light IDE'));
    await tester.pump();
    expect(container.read(themeVariantProvider), GbmThemeVariant.lightIde);
  });

  // Widths are 400/480, not the 200-ish a "narrow" test might reach for.
  // TopBar spans the whole window (it sits above the sidebar splitter), so
  // its width IS the window width, and the app's own default is 1280x720.
  // Measured after the fix: the non-flex remainder -- back button, Refresh,
  // divider, three theme swatches -- needs ~327 logical px under the test
  // font, so 320 still overflows by 7.2px with the repo name already at
  // zero. That floor is below any real window and would need the trailing
  // controls themselves to degrade; it is deliberately not chased here.
  group('narrow window', () {
    // A merge state, so `describe` is non-empty and the row carries every
    // variable-width element at once. Fields other than `describe` are the
    // model's neutral values -- TopBar reads nothing else off RepoState.
    const model.RepoState merging = model.RepoState(
      flags: model.RepoStateFlags.merge,
      isClean: false,
      isSequencerOperation: false,
      rebaseStep: 0,
      rebaseTotal: 0,
      rebaseOntoLabel: '',
      indexLocked: false,
      indexLockAgeSeconds: null,
      describe: 'MERGING',
    );

    const String longName = 'a-very-long-repository-name-that-does-not-fit';

    testWidgets('a long repo name does not overflow at 480px', (tester) async {
      await _pump(tester, repoName: longName, repoState: merging, width: 480);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long repo name does not overflow at 400px', (tester) async {
      await _pump(tester, repoName: longName, repoState: merging, width: 400);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the repo name ellipsizes instead of pushing the row', (
      tester,
    ) async {
      await _pump(tester, repoName: longName, repoState: merging, width: 480);

      final Text name = tester.widget<Text>(find.text(longName));
      expect(name.overflow, TextOverflow.ellipsis);
      expect(name.maxLines, 1);
    });

    testWidgets('the repo name keeps a readable width, not zero', (
      tester,
    ) async {
      await _pump(tester, repoName: longName, repoState: merging, width: 480);

      // Flexible can silently collapse to zero without ever overflowing, so
      // "no exception" alone would pass on an invisible name. The repo name
      // is the one thing this bar exists to identify.
      expect(tester.getSize(find.text(longName)).width, greaterThan(0));
    });

    testWidgets('the Refresh button stays inside the bar at 480px', (
      tester,
    ) async {
      await _pump(tester, repoName: longName, repoState: merging, width: 480);

      // The trailing controls are what a non-ellipsizing name used to push
      // off-screen, so their right edge is the real regression signal.
      final Rect refresh = tester.getRect(find.text('Refresh'));
      expect(refresh.right, lessThanOrEqualTo(480));
    });

    testWidgets('a short name at a wide width keeps the state label', (
      tester,
    ) async {
      // Control case: the degradation must not fire when there is room, or
      // the tests above would pass for the wrong reason.
      await _pump(tester, repoName: 'gbm', repoState: merging, width: 900);

      expect(tester.takeException(), isNull);
      expect(find.text('MERGING'), findsOneWidget);
      expect(find.text('gbm'), findsOneWidget);
    });
  });
}
