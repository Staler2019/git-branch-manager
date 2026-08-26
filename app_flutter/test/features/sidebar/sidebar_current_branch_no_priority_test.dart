// The current branch gets **no sorting and no filtering privilege** in the
// sidebar. This is a user-ratified deviation from BRANCH_STATES' 目前分支 row
// (「永遠置頂於所屬資料夾內，且不受 filter 影響」) and from P02-14 rule 7 --
// see docs/ledger.md. What survives from that row is only the visual half:
// 「名稱加粗、整列以 selected 底色標示」, which is what tells the user which
// branch is checked out now that position no longer does.
//
// `branch_tree_builder_test.dart` owns the ordering half as a pure function.
// This file owns what only the panel can answer: that a query drops the
// current branch exactly like any other row, and that nothing re-adds it
// behind the filter's back.
//
// Every fixture here puts HEAD **inside a folder** and gives it a name that is
// alphabetically last among its siblings, so a reinstated pin fails them
// rather than passing by coincidence. A fixture with HEAD at the root cannot
// tell 「置頂於所屬資料夾內」 and 「置頂於整棵樹」 apart -- root *is* its
// folder -- which is why `sidebar_filter_test.dart`'s `main` fixture once
// stayed green through a real bug.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

RefInfo _branch(String shortName, {bool isHead = false}) => RefInfo(
  fullName: 'refs/heads/$shortName',
  shortName: shortName,
  kind: RefKind.localBranch,
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

// `feature/zeta` is HEAD: last of its siblings alphabetically, and inside a
// folder that sorts *after* `chore`. So "first row of the tree" and "first row
// of its folder" are different rows, and neither is where a plain sort puts it.
final RefInfo _zeta = _branch('feature/zeta', isHead: true);
final RefInfo _alpha = _branch('feature/alpha');
final RefInfo _choreDocs = _branch('chore/docs');

final RefSnapshot _refs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'feature/zeta',
    fullRef: 'refs/heads/feature/zeta',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[_alpha, _choreDocs, _zeta],
  refCountGuardTripped: false,
  totalRefCount: 3,
);

Future<void> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoRefsProvider(_identity).overrideWithValue(_refs),
      repoSessionProvider(_identity).overrideWith(
        (ref) => FakeRepoSessionController(
          _identity,
          const RepoSessionState(isOpen: true),
        ),
      ),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: SizedBox(
            width: 260,
            height: 700,
            child: SidebarPanel(identity: _identity, filterFocusNode: null),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

/// The branch names on screen, in render order.
List<String> _rows(WidgetTester tester) => tester
    .widgetList<BranchTreeItem>(find.byType(BranchTreeItem))
    .map((BranchTreeItem item) => item.ref.shortName)
    .toList();

void main() {
  group('with no filter', () {
    testWidgets('the current branch sorts alphabetically in its folder', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('feature'));
      await tester.pumpAndSettle();

      // `zeta` is alphabetically last of its siblings and renders there. A
      // reinstated pin reverses these two rows.
      expect(_rows(tester), <String>['feature/alpha', 'feature/zeta']);
    });

    testWidgets('and never leaves its folder', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('chore'));
      await tester.pumpAndSettle();

      // `chore` sorts before `feature`; nothing hoists the current branch
      // above it.
      expect(_rows(tester), <String>['chore/docs']);
    });
  });

  group('while filtering', () {
    testWidgets('a query the current branch does not match drops it', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'docs');

      expect(_rows(tester), <String>['chore/docs']);
    });

    testWidgets('its folder is not drawn when nothing in it matched', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'docs');

      // The mirror of the old behaviour: `feature` used to be rendered with
      // no matching child at all, purely to carry the exempt row.
      expect(find.text('feature'), findsNothing);
    });

    testWidgets('a query it does match keeps it, exactly once', (tester) async {
      await _pump(tester);
      await _type(tester, 'zeta');

      expect(
        _rows(tester).where((String name) => name == 'feature/zeta').length,
        1,
      );
    });

    testWidgets('a query that matches nothing at all leaves an empty tree', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'zzz');

      expect(_rows(tester), isEmpty);
      expect(find.text('No matches'), findsOneWidget);
    });
  });

  group('being on screen is being a result', () {
    testWidgets('↓ lands on the first match with nothing to step over', (
      tester,
    ) async {
      // `firstLeafName` used to take a `skip` for the one row rule 7 forced
      // into the tree. With no such row the first leaf in render order simply
      // *is* the first result.
      await _pump(tester);
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await _type(tester, 'docs');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final Map<String, bool> selected = <String, bool>{
        for (final BranchTreeItem i in tester.widgetList<BranchTreeItem>(
          find.byType(BranchTreeItem),
        ))
          i.ref.shortName: i.selected,
      };
      expect(selected['chore/docs'], isTrue);
      expect(selected.containsKey('feature/zeta'), isFalse);
    });

    testWidgets('the 命中/總數 count is unchanged by any of this', (tester) async {
      await _pump(tester);
      await _type(tester, 'docs');

      // One branch matched out of three refs. The count always read genuine
      // matches, so removing the exemption must not move it either way.
      expect(find.text('1/3'), findsOneWidget);
    });
  });
}
