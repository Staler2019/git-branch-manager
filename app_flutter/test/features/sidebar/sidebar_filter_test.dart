// Spec P02-14's nine rules, at the seam where they are actually observable.
//
// `branch_filter_test.dart` owns rule 2/3 (the matching semantics) as a pure
// function. Everything else in P02-14 is about what the *panel* does with a
// match -- which folders open, what stays pinned, what the count says, what
// Esc and the arrow keys do -- and none of that is expressible without
// pumping SidebarPanel against a real provider/router seam.
//
// Rule 1 (one box over three sections) and rule 5 (an empty section hides its
// header, leaving no orphan title) were already conformant when this file was
// written and are covered by the existing suite; the rules below were not.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/stash_entry.dart';
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

RefInfo _tag(String shortName) => RefInfo(
  fullName: 'refs/tags/$shortName',
  shortName: shortName,
  kind: RefKind.tag,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

// `main` is HEAD and matches none of the queries below on purpose -- rule 7
// is only observable when the current branch would otherwise be filtered out.
final RefInfo _main = _branch('main', isHead: true);
final RefInfo _graphLanes = _branch('feature/graph-lanes');
final RefInfo _graphColumns = _branch('feature/graph-columns');
final RefInfo _choreDocs = _branch('chore/docs');
final RefInfo _tagV1 = _tag('v1.0.0');

final RefSnapshot _refs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[_main, _graphLanes, _graphColumns, _choreDocs, _tagV1],
  refCountGuardTripped: false,
  totalRefCount: 5,
);

const StashEntry _stash = StashEntry(
  index: 0,
  message: 'WIP on main: fix the thing',
  oid: 'b',
  timestamp: 0,
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
          const RepoSessionState(isOpen: true, stashes: <StashEntry>[_stash]),
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

Finder _filterField() => find.byType(TextField);

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(_filterField(), query);
  await tester.pumpAndSettle();
}

/// The branch names on screen, in render order.
List<String> _rows(WidgetTester tester) => tester
    .widgetList<BranchTreeItem>(find.byType(BranchTreeItem))
    .map((BranchTreeItem item) => item.ref.shortName)
    .toList();

void main() {
  group('the query outlives the widget', () {
    testWidgets('hiding and re-showing the sidebar keeps the filter in force', (
      tester,
    ) async {
      // The value lives in branchFilterQueryProvider, not in
      // _SidebarPanelState, because the History graph converges on it: a
      // sidebar that can be hidden must not be able to take the *only* copy
      // of the filter with it, leaving the graph narrowed with nothing on
      // screen to say why or to clear it.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
          repoRefsProvider(_identity).overrideWithValue(_refs),
          repoSessionProvider(_identity).overrideWith(
            (ref) => FakeRepoSessionController(
              _identity,
              const RepoSessionState(
                isOpen: true,
                stashes: <StashEntry>[_stash],
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      late StateSetter setVisible;
      bool visible = true;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  setVisible = setState;
                  return SizedBox(
                    width: 260,
                    height: 700,
                    child: visible
                        ? SidebarPanel(
                            identity: _identity,
                            filterFocusNode: null,
                          )
                        : const SizedBox.shrink(),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await _type(tester, 'gl');
      expect(_rows(tester), <String>['feature/graph-lanes']);

      setVisible(() => visible = false);
      await tester.pumpAndSettle();
      expect(find.byType(SidebarPanel), findsNothing);

      setVisible(() => visible = true);
      await tester.pumpAndSettle();

      // Both halves: the rows are still narrowed, *and* the box shows the
      // query that narrowed them. A provider that the field did not re-read
      // on mount would pass the first assertion and fail the second, leaving
      // a filter in force with an empty-looking box.
      expect(_rows(tester), <String>['feature/graph-lanes']);
      expect(tester.widget<TextField>(_filterField()).controller?.text, 'gl');
    });
  });

  group('rule 8: Esc clears the filter', () {
    testWidgets('Esc in the filter field empties it and unfilters', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(_filterField());
      await tester.pumpAndSettle();
      await _type(tester, 'graph');
      expect(find.text('2/6'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Both halves: the box is empty *and* the tree is back to unfiltered,
      // which for this fixture means the folders are collapsed again.
      expect(tester.widget<TextField>(_filterField()).controller?.text, '');
      expect(find.textContaining('/6'), findsNothing);
      expect(_rows(tester), isNot(contains('feature/graph-lanes')));
    });

    testWidgets('Esc in the tree still collapses the selection', (
      tester,
    ) async {
      // The tree already binds Esc to DismissIntent for MULTIKEYS' collapse.
      // The filter field sits outside _BranchSelectionShortcuts, so the two
      // bindings never see the same event -- asserted rather than assumed,
      // because "it is a different subtree" is exactly the kind of claim
      // that stops being true after one refactor.
      await _pump(tester);
      await _type(tester, 'graph');

      // A **modifier** click, not a plain one: a plain click on a branch row
      // routes through checkout and never reaches `_onBranchSelect`, so
      // focus stays in the filter box and Esc goes there instead. The first
      // version of this test used a plain tap and failed for that reason --
      // the code was right and the premise was not.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      // The row prints its last segment now (P02 item 12); the filter
      // still matches on the full path.
      await tester.tap(find.text('graph-lanes'));
      await tester.pumpAndSettle();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        tester.widget<TextField>(_filterField()).controller?.text,
        'graph',
        reason: 'Esc with the tree focused must not reach the filter box',
      );
    });
  });

  group('rule 9: the down arrow enters the results', () {
    testWidgets('selects the first match', (tester) async {
      await _pump(tester);
      await tester.tap(_filterField());
      await tester.pumpAndSettle();
      await _type(tester, 'graph');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      final List<BranchTreeItem> items = tester
          .widgetList<BranchTreeItem>(find.byType(BranchTreeItem))
          .toList();
      final BranchTreeItem firstMatch = items.firstWhere(
        (BranchTreeItem i) => i.ref.shortName == 'feature/graph-columns',
      );
      expect(firstMatch.selected, isTrue);
    });

    testWidgets('never lands on a branch the query excluded', (tester) async {
      // `main` matches neither query below. It used to be on screen anyway
      // (rule 7) and `firstLeafName` needed a `skip` to step over it; now it
      // is simply not rendered, so this asserts the absence rather than the
      // exemption.
      await _pump(tester);
      await tester.tap(_filterField());
      await tester.pumpAndSettle();
      await _type(tester, 'graph');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(_rows(tester), isNot(contains('main')));
    });

    testWidgets('does nothing when nothing matched', (tester) async {
      await _pump(tester);
      await tester.tap(_filterField());
      await tester.pumpAndSettle();
      await _type(tester, 'zzz');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(_rows(tester), isEmpty);
    });
  });

  group('rule 4: folders open while filtering', () {
    testWidgets('CONTROL: a folder is collapsed with no query', (tester) async {
      await _pump(tester);

      expect(find.text('feature'), findsOneWidget);
      expect(_rows(tester), isNot(contains('feature/graph-lanes')));
    });

    testWidgets('a match inside a collapsed folder is revealed', (
      tester,
    ) async {
      // Without this the filter is close to useless on a real repository:
      // every branch worth finding lives under a folder, the count says two
      // matched, and the tree shows a closed folder.
      await _pump(tester);
      await _type(tester, 'graph');

      expect(_rows(tester), contains('feature/graph-lanes'));
      expect(_rows(tester), contains('feature/graph-columns'));
    });

    testWidgets('clearing the query restores the previous collapse state', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'graph');
      await _type(tester, '');

      // 「清空後回到原本收合狀態」 -- the auto-expansion is a view of the
      // filtered tree, never a write to the user's own expanded set.
      expect(_rows(tester), isNot(contains('feature/graph-lanes')));
    });

    testWidgets('a folder the user opened stays open afterwards', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('feature'));
      await tester.pumpAndSettle();
      expect(_rows(tester), contains('feature/graph-lanes'));

      await _type(tester, 'chore');
      await _type(tester, '');

      // The other half of "原本收合狀態": restoring must not collapse what
      // was open either. A boolean "expand all" flag gets this right; a
      // filter that mutated _expandedFolders and undid itself would not.
      expect(_rows(tester), contains('feature/graph-lanes'));
    });
  });

  group('rule 6: the hit count', () {
    testWidgets('reports matches over the whole three-section total', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'graph');

      // Four branches + one tag + one stash. `graph` matches the two
      // feature branches and nothing else, and the total is deliberately
      // the total across all three sections rather than per-section --
      // P02-14 is one box over Branches, Tags and Stash.
      expect(find.text('2/6'), findsOneWidget);
    });

    testWidgets('counts the current branch only if it really matched', (
      tester,
    ) async {
      // `main` does not match this query, so it is neither rendered nor
      // counted. It used to be rendered-but-not-counted (rule 7's exemption);
      // the count is sourced from the matches either way, never from the rows.
      await _pump(tester);
      await _type(tester, 'graph');

      expect(_rows(tester), isNot(contains('main')));
      expect(find.text('2/6'), findsOneWidget);
    });

    testWidgets('counts a tag and a stash the same as a branch', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'wip');

      expect(find.text('1/6'), findsOneWidget);
    });

    testWidgets('reports zero rather than hiding when nothing matches', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'zzz');

      expect(find.text('0/6'), findsOneWidget);
    });

    testWidgets('is absent with no query', (tester) async {
      // "6/6" on an untouched sidebar is noise: nothing has been filtered,
      // so there is no ratio to report. Spec describes the count as part of
      // the filter's behaviour, not as a permanent branch counter.
      await _pump(tester);

      expect(find.textContaining('/6'), findsNothing);
    });
  });

  // Rule 7 (「目前分支永遠置頂顯示，即使不符合條件也不會被濾掉」) is a
  // **user-ratified deviation**: the current branch is filtered like any
  // other row. Answering 「where am I」 is the expanded-to-HEAD default's job
  // instead, which a query overrides anyway (rule 4 opens every folder).
  group('the current branch is filtered like any other row', () {
    testWidgets('a query it does not match drops it', (tester) async {
      await _pump(tester);
      await _type(tester, 'graph');

      expect(_rows(tester), isNot(contains('main')));
    });

    testWidgets('a query it does match keeps it, exactly once', (tester) async {
      await _pump(tester);
      await _type(tester, 'main');

      expect(
        _rows(tester).where((String name) => name == 'main').length,
        1,
        reason: 'nothing re-adds it alongside its own matched row',
      );
    });

    testWidgets('a query that matches nothing leaves an empty tree', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'zzz');

      expect(_rows(tester), isEmpty);
      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('CONTROL: an unfiltered tree still carries it', (tester) async {
      await _pump(tester);

      expect(_rows(tester), contains('main'));
    });
  });
}
