// BRANCH_STATES' 目前分支 row: 「名稱加粗、整列以 selected 底色標示，永遠置頂於
// 所屬資料夾內，且不受 filter 影響。」
//
// Two clauses, and the panel honoured neither. It pinned the current branch
// above the *entire* tree, and only while a filter was active -- so with no
// query the pin did not exist at all, and with one it sat outside the folder
// it belongs to.
//
// `branch_tree_builder_test.dart` owns the ordering half as a pure function.
// This file owns what only the panel can answer: that the pin survives a query
// it does not match (P02-14 rule 7, 「即使不符合條件也不會被濾掉」) *while
// staying inside its folder*, and that being on screen for that reason still
// does not make it a search result.
//
// Every fixture here puts HEAD **inside a folder** and gives it a name that is
// alphabetically last among its siblings. A fixture with HEAD at the root
// cannot tell the two readings apart -- root *is* its folder, so 「置頂於所屬
// 資料夾內」 and 「置頂於整棵樹」 name the same row, which is exactly why
// `sidebar_filter_test.dart`'s `main` fixture stayed green through the bug.
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
  group(
    'with no filter (「不受 filter 影響」, read as "not only while filtering")',
    () {
      testWidgets('the current branch leads its own folder', (tester) async {
        await _pump(tester);
        // Folders start collapsed, so the pin is only observable once `feature`
        // is open -- the bug was in the ordering, not in the expansion.
        await tester.tap(find.text('feature'));
        await tester.pumpAndSettle();

        expect(_rows(tester), <String>['feature/zeta', 'feature/alpha']);
      });

      testWidgets('and does not leave its folder to do it', (tester) async {
        await _pump(tester);
        await tester.tap(find.text('chore'));
        await tester.pumpAndSettle();

        // `chore` sorts before `feature`, so if the pin were hoisted to the root
        // this would open with `feature/zeta` above `chore/docs`.
        expect(_rows(tester), <String>['chore/docs']);
      });
    },
  );

  group('while filtering (P02-14 rule 7)', () {
    testWidgets('a current branch the query excludes still renders', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'docs');

      expect(_rows(tester), contains('feature/zeta'));
    });

    testWidgets('and renders inside its folder, not above the tree', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'docs');

      // The whole point: `chore/docs` is the only match and `chore` sorts
      // first, so a pin scoped to its own folder lands *second*. Hoisting it
      // to the top -- the previous behaviour -- reverses these two rows.
      expect(_rows(tester), <String>['chore/docs', 'feature/zeta']);
    });

    testWidgets('its folder is drawn even though nothing in it matched', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'docs');

      // A row cannot sit inside a folder that is not on screen. `feature` is
      // present only to carry the pin.
      expect(find.text('feature'), findsOneWidget);
    });

    testWidgets('it is not rendered twice when it does match', (tester) async {
      await _pump(tester);
      await _type(tester, 'zeta');

      expect(
        _rows(tester).where((String name) => name == 'feature/zeta').length,
        1,
      );
    });

    testWidgets('it survives a query that matches nothing at all', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'zzz');

      expect(_rows(tester), <String>['feature/zeta']);
      expect(
        find.text('No matches'),
        findsOneWidget,
        reason:
            'the pin is now inside the tree, so an emptiness check written '
            'against the tree would stop reporting zero matches',
      );
    });
  });

  group('being pinned is not being a result', () {
    testWidgets('↓ skips the pinned branch and lands on a real match', (
      tester,
    ) async {
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
      expect(selected['feature/zeta'], isFalse);
    });

    testWidgets('the 命中/總數 count does not include it', (tester) async {
      await _pump(tester);
      await _type(tester, 'docs');

      // One branch matched out of three refs. Counting the rendered rows
      // instead would say 2/3.
      expect(find.text('1/3'), findsOneWidget);
    });
  });
}
