// Spec page 13's 「對既有頁面的連帶修改」 for P2 History: 「狀態列改為顯示
// selection 摘要（數量、是否連續…）」.
//
// Integration tier rather than widget tier, because the two halves that can
// go wrong are both above StatusBar: whether WorkspaceScreen computes
// contiguity against the snapshot at all, and whether it stops rendering the
// summary once History is no longer the visible tab. A widget test feeding
// StatusBar a string proves the string renders -- which is already covered in
// status_bar_test.dart -- not that anything ever produces it.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/routing/route_paths.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');
final String _repoId = Uri.encodeComponent(_identity.workDir);

/// Newest first, as History renders.
final List<String> _oids = <String>[
  for (final String seed in <String>['a', 'b', 'c', 'd']) seed * 40,
];
String _oid(String seed) => seed * 40;

RepoSessionState get _state => RepoSessionState(
  isOpen: true,
  graph: GraphSnapshotView(
    rows: <GraphRow>[
      for (final _ in _oids)
        const GraphRow(
          parentOffset: 0,
          edgeOffset: 0,
          commitTime: 0,
          lane: 0,
          color: 0,
          flags: 0,
        ),
    ],
    oidsHex: _oids,
    parentPool: const <int>[],
    laneCount: 1,
    complete: true,
    truncated: false,
  ),
);

void _select(PumpedWorkspace pumped, List<String> oids) {
  pumped.container.read(commitSelectionProvider(_identity).notifier).state =
      ListSelection<String>(items: oids, anchor: oids.last);
}

void main() {
  testWidgets('History shows the count and contiguity of a selected run', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _state,
    );

    expect(find.textContaining('commits'), findsNothing);

    _select(pumped, <String>[_oid('b'), _oid('c')]);
    await tester.pump();

    expect(find.text('2 commits · contiguous'), findsOneWidget);
  });

  testWidgets('a gap in the snapshot reads as not contiguous', (tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _state,
    );

    // a and c, with b between them: not a range git can replay, which is
    // exactly why MULTIACTS disables cherry-pick/revert for it. The status
    // bar is where the user finds out why.
    _select(pumped, <String>[_oid('a'), _oid('c')]);
    await tester.pump();

    expect(find.text('2 commits · not contiguous'), findsOneWidget);
  });

  testWidgets('a single commit gets no summary', (tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _state,
    );

    _select(pumped, <String>[_oid('b')]);
    await tester.pump();

    expect(find.textContaining('commits'), findsNothing);
  });

  testWidgets('the summary hides on Working Copy and returns on History', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _state,
    );

    _select(pumped, <String>[_oid('b'), _oid('c')]);
    await tester.pump();
    expect(find.text('2 commits · contiguous'), findsOneWidget);

    pumped.router.go(RoutePaths.workingCopyFor(_repoId));
    await tester.pumpAndSettle();

    // The selected rows are off screen; describing them would be describing
    // something the user cannot see.
    expect(find.textContaining('commits'), findsNothing);

    pumped.router.go(RoutePaths.historyFor(_repoId));
    await tester.pumpAndSettle();

    // Selection survives the tab switch (「Selection 在切換分頁與重新整理後
    // 保留」), so the summary comes back rather than being rebuilt empty.
    expect(find.text('2 commits · contiguous'), findsOneWidget);
  });
}
