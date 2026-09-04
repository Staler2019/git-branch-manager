// Swap on the Compare toolbar, at the surface that draws it.
//
// The reported defect: 「Swap 沒有把兩邊的文字換過來」. The exchange itself
// always worked -- `_updateRefs` swapped the tab spec and the diff really
// was re-fetched the other way round -- but both pickers went on showing
// what they showed at mount, so the screen said one thing and the diff
// underneath it said another.
//
// This test drives the button rather than the picker, because a picker test
// pins the mechanism and not the surface: it is the toolbar that owns
// "left becomes right", and a picker that syncs correctly under a toolbar
// that never re-renders it would pass one and fail the other.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/compare/compare_page.dart';
import 'package:gbm_flutter/features/compare/widgets/compare_ref_picker.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');
final String _repoId = repoIdFor('/test/repo');

/// The text each [CompareRefPicker] is actually showing, left to right.
///
/// Read off the controllers rather than with `find.text`, because the claim
/// is about *which* field carries which ref -- `find.text('develop')` is
/// satisfied by either side ([FLU-finder-proves-existence-not-position]).
List<String> _pickerTexts(WidgetTester tester) => <String>[
  for (final Element element in find.byType(CompareRefPicker).evaluate())
    tester
        .widget<TextField>(
          find.descendant(
            of: find.byWidget(element.widget),
            matching: find.byType(TextField),
          ),
        )
        .controller!
        .text,
];

void main() {
  testWidgets('Swap exchanges what the two ref fields show', (tester) async {
    final FakeRepoSessionController fake = FakeRepoSessionController(
      _identity,
      const RepoSessionState(isOpen: true),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        repoSessionProvider(_identity).overrideWith((ref) => fake),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    final String tab = container
        .read(compareTabsProvider(_identity).notifier)
        .open(left: 'main', right: 'develop');

    final GoRouter router = GoRouter(
      initialLocation: RoutePaths.compareFor(_repoId, tab),
      routes: <RouteBase>[
        GoRoute(
          path: '/repo/:repoId/compare/:tabId',
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: buildComparePageRoute(context, state)),
        ),
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
    await tester.pump();

    expect(_pickerTexts(tester), <String>['main', 'develop']);

    await tester.tap(find.byTooltip('Swap'));
    await tester.pump();
    await tester.pump();

    expect(
      _pickerTexts(tester),
      <String>['develop', 'main'],
      reason: 'the fields must follow the swap, not keep their mount value',
    );

    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.swap_horiz))
          .tooltip,
      'Swap',
      reason: 'the enabled state keeps the plain label',
    );
  });

  // The other half of the same report. Working Copy can only ever be the
  // right side -- gbm_capi's commitVsWorkingTree takes one commit and always
  // compares it against the live tree as the "after" side, so there is no
  // reverse direction. The app expressed that by removing Working Copy from
  // the left picker's options and greying Swap out, and said nothing at all
  // about why, which is what 「有一邊是 working copy 時無法進行比較」 reads
  // like from the outside.
  //
  // Asserting the tooltip *changes* rather than merely being non-empty: a
  // tooltip that reads 'Swap' on a button that will not swap is the defect,
  // not the fix.
  testWidgets('Swap is disabled against Working Copy and says why', (
    tester,
  ) async {
    final FakeRepoSessionController fake = FakeRepoSessionController(
      _identity,
      const RepoSessionState(isOpen: true),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        repoSessionProvider(_identity).overrideWith((ref) => fake),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);

    final String tab = container
        .read(compareTabsProvider(_identity).notifier)
        .open(left: 'main', right: null);

    final GoRouter router = GoRouter(
      initialLocation: RoutePaths.compareFor(_repoId, tab),
      routes: <RouteBase>[
        GoRoute(
          path: '/repo/:repoId/compare/:tabId',
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: buildComparePageRoute(context, state)),
        ),
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
    await tester.pump();

    final IconButton swap = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.swap_horiz),
    );
    expect(swap.onPressed, isNull, reason: 'there is no reverse direction');
    expect(swap.tooltip, isNot('Swap'));
    expect(swap.tooltip, kSwapBlockedTooltip);
    expect(
      kSwapBlockedTooltip,
      contains('Working Copy'),
      reason: 'it has to name the side that cannot move',
    );
  });
}
