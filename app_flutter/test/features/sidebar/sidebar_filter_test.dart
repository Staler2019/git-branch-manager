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
  group('rule 7: the current branch is pinned and never filtered out', () {
    testWidgets('survives a query it does not match', (tester) async {
      await _pump(tester);
      await _type(tester, 'graph');

      // 'main' matches neither as a substring nor by initials, so without an
      // exemption it disappears -- and the sidebar stops answering "where am
      // I", which is the one question it must always answer.
      expect(_rows(tester), contains('main'));
    });

    testWidgets('is the first row, above the matches', (tester) async {
      await _pump(tester);
      await _type(tester, 'graph');

      expect(_rows(tester).first, 'main');
    });

    testWidgets('is not rendered twice when it does match', (tester) async {
      await _pump(tester);
      await _type(tester, 'main');

      expect(
        _rows(tester).where((String name) => name == 'main').length,
        1,
        reason: 'pinned *instead of* in the tree, never as well as',
      );
    });

    testWidgets('CONTROL: an unfiltered tree is left alone', (tester) async {
      // "置頂" is read as "regardless of the query", not "restructure the
      // sidebar permanently" -- with no query the tree is exactly what
      // buildBranchTree produced, folders and all.
      await _pump(tester);

      expect(_rows(tester), contains('main'));
      expect(find.text('CURRENT'), findsNothing);
    });
  });
}
