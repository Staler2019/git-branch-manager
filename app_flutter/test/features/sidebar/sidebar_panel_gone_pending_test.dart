// Spec page 02's three-stage "遠端分支被刪除時怎麼看得到" reaching the real
// sidebar: after a fetch, gonePendingByRemote marks rows and shows a pending
// count, and nothing is deleted.
//
// Drives repoSessionProvider directly and deliberately does NOT override
// repoRefsProvider: that provider derives from the session
// (branch_repository.dart), so leaving it alone is what lets a single
// emit() change both the refs and the pending set -- a fixture pinned to one
// fixed snapshot could not express the transition at all.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
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

final RefInfo _localMain = RefInfo(
  fullName: 'refs/heads/main',
  shortName: 'main',
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: 'refs/remotes/origin/main',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: true,
  isSymbolic: false,
  worktreePath: '',
);

/// Tracks origin/feature, which is the ref the preview will report as gone.
final RefInfo _localFeature = RefInfo(
  fullName: 'refs/heads/feature',
  shortName: 'feature',
  kind: RefKind.localBranch,
  target: 'b' * 40,
  upstream: 'refs/remotes/origin/feature',
  ahead: 0,
  behind: 0,
  // Not derived from `upstream`: a branch exactly in sync reports an empty
  // %(upstream:track), so hasTrackingInfo is false while %(upstream) is
  // populated. Anything asking "does this track a remote" must read
  // `upstream`, and this fixture exists to be able to prove it.
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

/// No local branch tracks this one, so it survives the merge as a
/// remote-only row named "orphan".
final RefInfo _remoteOnlyOrphan = RefInfo(
  fullName: 'refs/remotes/origin/orphan',
  shortName: 'origin/orphan',
  kind: RefKind.remoteBranch,
  target: 'c' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

RepoSessionState _stateWith(Map<String, List<String>> gonePending) =>
    RepoSessionState(
      isOpen: true,
      refs: RefSnapshot(
        head: HeadInfo(
          kind: HeadKind.branch,
          branchName: 'main',
          fullRef: 'refs/heads/main',
          target: 'a' * 40,
        ),
        refs: <RefInfo>[_localMain, _localFeature, _remoteOnlyOrphan],
        refCountGuardTripped: false,
        totalRefCount: 3,
      ),
      gonePendingByRemote: gonePending,
    );

Future<FakeRepoSessionController> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    _stateWith(const <String, List<String>>{}),
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(_identity).overrideWith((ref) => fake),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: SidebarPanel(identity: _identity, filterFocusNode: null),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

bool _rowIsGonePending(WidgetTester tester, String name) {
  final Finder row = find.ancestor(
    of: find.text(name),
    matching: find.byType(BranchTreeItem),
  );
  return tester.widget<BranchTreeItem>(row).isGonePending;
}

void main() {
  testWidgets('nothing is marked before a preview arrives', (tester) async {
    await _pump(tester);

    expect(_rowIsGonePending(tester, 'feature'), isFalse);
    expect(_rowIsGonePending(tester, 'orphan'), isFalse);
    expect(find.text('1 to clean up'), findsNothing);
  });

  testWidgets('a preview marks the local branch that tracks the gone ref', (
    tester,
  ) async {
    final FakeRepoSessionController fake = await _pump(tester);

    fake.emit(
      _stateWith(const <String, List<String>>{
        'origin': <String>['refs/remotes/origin/feature'],
      }),
    );
    await tester.pumpAndSettle();

    expect(_rowIsGonePending(tester, 'feature'), isTrue);
    expect(_rowIsGonePending(tester, 'main'), isFalse);
  });

  testWidgets('a preview marks a remote-only row by its full ref name', (
    tester,
  ) async {
    // The row's shortName is 'orphan' -- mergeLocalAndRemoteBranches strips
    // the remote prefix -- so matching on shortName would miss it entirely.
    final FakeRepoSessionController fake = await _pump(tester);

    fake.emit(
      _stateWith(const <String, List<String>>{
        'origin': <String>['refs/remotes/origin/orphan'],
      }),
    );
    await tester.pumpAndSettle();

    expect(_rowIsGonePending(tester, 'orphan'), isTrue);
  });

  testWidgets('the section header shows how many rows are pending', (
    tester,
  ) async {
    final FakeRepoSessionController fake = await _pump(tester);

    fake.emit(
      _stateWith(const <String, List<String>>{
        'origin': <String>[
          'refs/remotes/origin/feature',
          'refs/remotes/origin/orphan',
        ],
      }),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 to clean up'), findsOneWidget);
  });

  testWidgets('the count ignores refs the snapshot no longer has', (
    tester,
  ) async {
    // The ghost case: pruned in a terminal, so the ref is gone from the
    // snapshot while gonePendingByRemote still lists it. Counting the set's
    // size would claim "1 to clean up" over a tree with nothing marked.
    final FakeRepoSessionController fake = await _pump(tester);

    fake.emit(
      _stateWith(const <String, List<String>>{
        'origin': <String>['refs/remotes/origin/already-pruned'],
      }),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('to clean up'), findsNothing);
  });

  testWidgets('marking a row dispatches no command at all', (tester) async {
    // Stage 3 is the user's to trigger: a fetch must never delete a
    // remote-tracking ref behind their back.
    final FakeRepoSessionController fake = await _pump(tester);

    fake.emit(
      _stateWith(const <String, List<String>>{
        'origin': <String>['refs/remotes/origin/feature'],
      }),
    );
    await tester.pumpAndSettle();

    expect(
      fake.commandLog.where(
        (c) => c.name == 'pruneRemote' || c.name == 'deleteBranch',
      ),
      isEmpty,
    );
  });

  testWidgets('clearing the pending set unmarks the row', (tester) async {
    // What a real Prune produces: the entry is dropped and RefInfo.isGone
    // takes over. Here the ref itself is unchanged, so the row must simply
    // stop being marked rather than stay stuck.
    final FakeRepoSessionController fake = await _pump(tester);

    fake.emit(
      _stateWith(const <String, List<String>>{
        'origin': <String>['refs/remotes/origin/feature'],
      }),
    );
    await tester.pumpAndSettle();
    expect(_rowIsGonePending(tester, 'feature'), isTrue);

    fake.emit(_stateWith(const <String, List<String>>{}));
    await tester.pumpAndSettle();

    expect(_rowIsGonePending(tester, 'feature'), isFalse);
    expect(find.textContaining('to clean up'), findsNothing);
  });
}
