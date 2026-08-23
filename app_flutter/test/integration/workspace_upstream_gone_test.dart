// Spec page 02 stage 2 across the real WorkspaceScreen seam: when HEAD's
// upstream disappears from the remote, the status bar's ahead/behind counts
// are replaced by "upstream gone" and the sidebar row is marked -- and both
// react to the same state transition, from either source of truth.
//
// A widget test on StatusBar alone proves the widget renders the flag; it
// cannot prove workspace_screen.dart ever computes a true one. Per CLAUDE.md's
// testing tiers, that seam is what this file is for.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

RefInfo _head({bool isGone = false}) => RefInfo(
  fullName: 'refs/heads/main',
  shortName: 'main',
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: 'refs/remotes/origin/main',
  ahead: 2,
  behind: 1,
  // Not derived from `upstream` -- see gone_marking.dart's doc comment on
  // why hasTrackingInfo is the wrong test for "tracks a remote".
  hasTrackingInfo: true,
  isGone: isGone,
  isHead: true,
  isSymbolic: false,
  worktreePath: '',
);

RepoSessionState _state({
  bool isGone = false,
  Map<String, List<String>> gonePending = const <String, List<String>>{},
}) => RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'a' * 40,
    ),
    refs: <RefInfo>[_head(isGone: isGone)],
    refCountGuardTripped: false,
    totalRefCount: 1,
  ),
  gonePendingByRemote: gonePending,
);

const Map<String, List<String>> _originMainGone = <String, List<String>>{
  'origin': <String>['refs/remotes/origin/main'],
};

void main() {
  testWidgets('a healthy upstream shows the ahead/behind counts', (
    tester,
  ) async {
    await pumpWorkspace(tester, identity: _identity, initialState: _state());

    expect(find.text('2↑'), findsOneWidget);
    expect(find.text('1↓'), findsOneWidget);
    expect(find.text('upstream gone'), findsNothing);
  });

  testWidgets('a post-fetch preview flips the status bar', (tester) async {
    final PumpedWorkspace w = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _state(),
    );

    w.controller.emit(_state(gonePending: _originMainGone));
    await tester.pumpAndSettle();

    expect(find.text('upstream gone'), findsOneWidget);
    expect(find.text('2↑'), findsNothing);
    expect(find.text('1↓'), findsNothing);
  });

  testWidgets('git reporting [gone] flips it too, with no pending set', (
    tester,
  ) async {
    // The post-prune state. Both sources must reach the same surface, or
    // the status bar would go blank again the moment the user actually
    // prunes.
    await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _state(isGone: true),
    );

    expect(find.text('upstream gone'), findsOneWidget);
  });

  testWidgets('the sidebar row and the status bar agree', (tester) async {
    final PumpedWorkspace w = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _state(),
    );

    w.controller.emit(_state(gonePending: _originMainGone));
    await tester.pumpAndSettle();

    final BranchTreeItem row = tester.widget<BranchTreeItem>(
      find.ancestor(
        of: find.text('main'),
        matching: find.byType(BranchTreeItem),
      ),
    );
    expect(row.isGonePending, isTrue);
    expect(find.text('upstream gone'), findsOneWidget);
  });

  testWidgets('clearing the pending set restores the counts', (tester) async {
    // Round trip, per CLAUDE.md's rule for a new state-dependent gate: the
    // gated surface must come back, not stay stuck.
    final PumpedWorkspace w = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _state(),
    );

    w.controller.emit(_state(gonePending: _originMainGone));
    await tester.pumpAndSettle();
    expect(find.text('upstream gone'), findsOneWidget);

    w.controller.emit(_state());
    await tester.pumpAndSettle();

    expect(find.text('upstream gone'), findsNothing);
    expect(find.text('2↑'), findsOneWidget);
    expect(find.text('1↓'), findsOneWidget);
  });

  testWidgets('a pending ref for a different branch leaves HEAD alone', (
    tester,
  ) async {
    final PumpedWorkspace w = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _state(),
    );

    w.controller.emit(
      _state(
        gonePending: const <String, List<String>>{
          'origin': <String>['refs/remotes/origin/other'],
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('upstream gone'), findsNothing);
    expect(find.text('2↑'), findsOneWidget);
  });
}
