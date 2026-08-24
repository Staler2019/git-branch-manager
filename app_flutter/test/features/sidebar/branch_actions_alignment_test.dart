// The trailing ⋯ "Branch actions" button must sit at the same distance from
// the sidebar's right edge on every row, whatever its folder depth.
//
// This is checkable by construction rather than by eye: the folder indent is
// an EdgeInsets.only(left:), so it never touches a row's right edge, and the
// right inset is the leaf wrapper's space1 plus GbmRow's space2 on every row
// at every depth. What actually broke the column was the button being drawn
// only when a row had one of four specific callbacks -- which a tag row never
// has, so the TAGS section had a hole in the column and no visible entry
// point to its own 05-D menu.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/branch_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');
final String _repoIdParam = Uri.encodeComponent(_identity.workDir);

RefInfo _ref(String name, {required RefKind kind, bool isHead = false}) =>
    RefInfo(
      fullName: kind == RefKind.tag ? 'refs/tags/$name' : 'refs/heads/$name',
      shortName: name,
      kind: kind,
      target: 'a' * 40,
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: isHead,
      isSymbolic: isHead,
      worktreePath: '',
    );

/// Rows at three different folder depths plus a tag -- the four row kinds
/// that have to line up into one column.
final RefSnapshot _refs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[
    _ref('main', kind: RefKind.localBranch, isHead: true),
    _ref('feature/auth', kind: RefKind.localBranch),
    _ref('feature/nested/deep', kind: RefKind.localBranch),
    _ref('v1.0.0', kind: RefKind.tag),
  ],
  refCountGuardTripped: false,
  totalRefCount: 4,
);

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    const RepoSessionState(),
  );

  final GoRouter router = GoRouter(
    initialLocation: '/repo/$_repoIdParam/history',
    routes: <RouteBase>[
      GoRoute(
        path: '/repo/:repoId/history',
        builder: (context, state) => Scaffold(
          body: SidebarPanel(identity: _identity, filterFocusNode: null),
        ),
      ),
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoRefsProvider(_identity).overrideWithValue(_refs),
      repoSessionProvider(_identity).overrideWith((ref) => fake),
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

  for (final String folder in <String>['feature', 'nested']) {
    await tester.tap(find.text(folder));
    await tester.pumpAndSettle();
  }
}

/// The ⋯ button belonging to the row that prints [label].
Finder _actionsButtonOf(String label) => find.descendant(
  of: find.ancestor(
    of: find.text(label),
    matching: find.byType(BranchTreeItem),
  ),
  matching: find.byTooltip('Branch actions'),
);

void main() {
  testWidgets('every row kind carries the actions button', (tester) async {
    await _pump(tester);

    // 'main' is HEAD (no delete), 'deep' is three levels down, 'v1.0.0' is a
    // tag with none of the four branch callbacks at all.
    for (final String label in <String>['main', 'auth', 'deep', 'v1.0.0']) {
      expect(
        _actionsButtonOf(label),
        findsOneWidget,
        reason: '$label has a menu, so it must have a way to open it',
      );
    }
  });

  testWidgets('the actions buttons line up, whatever the folder depth', (
    tester,
  ) async {
    await _pump(tester);

    final double mainRight = tester.getRect(_actionsButtonOf('main')).right;

    for (final String label in <String>['auth', 'deep', 'v1.0.0']) {
      expect(
        tester.getRect(_actionsButtonOf(label)).right,
        mainRight,
        reason:
            'the folder indent is left-only, so depth must not move the '
            'right edge of $label',
      );
    }
  });

  testWidgets('the column keeps a constant inset from the panel edge', (
    tester,
  ) async {
    await _pump(tester);

    final double panelRight = tester.getRect(find.byType(SidebarPanel)).right;

    // The *slot*, not the tooltip: a Tooltip measures the icon's own painted
    // box, which sits a pixel inside the button's tap target and would make
    // this assertion about IconButton's internal padding instead of about
    // the column.
    final Finder slot = find.descendant(
      of: find.ancestor(
        of: find.text('main'),
        matching: find.byType(BranchTreeItem),
      ),
      matching: find.byWidgetPredicate(
        (Widget w) => w is SizedBox && w.width == 32,
      ),
    );

    // Three terms, all of them nameable: GbmRow's horizontal space2, the
    // space1 the leaf wrapper adds, and the 1px right border the panel
    // itself paints (sidebar_panel.dart's `Border(right: BorderSide(...))`,
    // which defaults to 1.0 wide). No slack left over.
    const double panelRightBorder = 1;
    expect(
      panelRight - tester.getRect(slot).right,
      GbmSpacing.space2 + GbmSpacing.space1 + panelRightBorder,
    );
  });
}
