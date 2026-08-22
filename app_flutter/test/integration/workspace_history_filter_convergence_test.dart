// The seam from the sidebar's filter box to gbm_history_set_filter: sidebar
// State -> branchFilterQueryProvider -> historyFilterRequestProvider ->
// WorkspaceScreen's debounced dispatcher -> the controller.
//
// No widget test can see this. The sidebar writes a provider and never calls
// the controller; the dispatcher lives in WorkspaceScreen and reads a
// provider it does not own. Only the real screen behind the real router puts
// the two ends in the same tree.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/branch_filter_repository.dart';
import 'package:gbm_flutter/data/repositories/branch_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/history_graph/graph_filter_convergence.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

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

final RefSnapshot _refs = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[
    _branch('main', isHead: true),
    _branch('feature/graph-lanes'),
    _branch('feature/graph-columns'),
  ],
  refCountGuardTripped: false,
  totalRefCount: 3,
);

/// Every setHistoryFilter the controller actually received.
List<FakeCommand> _filterCalls(FakeRepoSessionController controller) =>
    controller.commandLog
        .where((FakeCommand c) => c.name == 'setHistoryFilter')
        .toList();

Future<PumpedWorkspace> _pump(WidgetTester tester) => pumpWorkspace(
  tester,
  identity: _identity,
  overrides: <Override>[repoRefsProvider(_identity).overrideWithValue(_refs)],
);

/// One keystroke, with no time for the debounce to elapse.
Future<void> _typeWithoutSettling(
  WidgetTester tester,
  PumpedWorkspace pumped,
  String query,
) async {
  pumped.container.read(branchFilterQueryProvider(_identity).notifier).state =
      query;
  await tester.pump(const Duration(milliseconds: 20));
}

/// Types into the filter provider (the sidebar's own `onChanged` does exactly
/// this) and lets the debounce elapse.
Future<void> _filter(
  WidgetTester tester,
  PumpedWorkspace pumped,
  String query,
) async {
  pumped.container.read(branchFilterQueryProvider(_identity).notifier).state =
      query;
  await tester.pump();
  await tester.pump(kHistoryFilterDebounce + const Duration(milliseconds: 1));
}

void main() {
  testWidgets('one matching branch collapses the graph to that branch', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await _pump(tester);
    await _filter(tester, pumped, 'graph-lanes');

    expect(_filterCalls(pumped.controller).length, 1);
    final FakeCommand call = _filterCalls(pumped.controller).single;
    expect(call.args['includeRefs'], <String>[
      'refs/heads/feature/graph-lanes',
    ]);
    expect(call.args['firstParentOnly'], isTrue);
    expect(call.args['noMerges'], isTrue);
  });

  testWidgets('two matching branches leave the walk unfiltered', (
    tester,
  ) async {
    // 「兩分支以上，就照目前狀態顯示」 -- but the dispatcher still has to *say*
    // so once a narrower filter has been in force, or the graph would stay
    // collapsed after the user widened the query.
    final PumpedWorkspace pumped = await _pump(tester);
    await _filter(tester, pumped, 'graph-lanes');
    await _filter(tester, pumped, 'graph');

    expect(_filterCalls(pumped.controller).length, 2);
    final FakeCommand widened = _filterCalls(pumped.controller).last;
    expect(widened.args['includeRefs'], isEmpty);
    expect(widened.args['firstParentOnly'], isFalse);
    expect(widened.args['noMerges'], isFalse);
  });

  testWidgets('typing towards one branch costs a single walk', (tester) async {
    // Measured, not assumed: this passes because
    // `historyFilterRequestProvider`'s value is *equal* for every prefix of
    // "graph-lanes" that does not resolve to exactly one branch, so Riverpod
    // notifies the listener once rather than eleven times. The debounce
    // contributes nothing here -- see the next case for what it does.
    final PumpedWorkspace pumped = await _pump(tester);
    for (int i = 1; i <= 'graph-lanes'.length; i++) {
      await _typeWithoutSettling(tester, pumped, 'graph-lanes'.substring(0, i));
    }
    await tester.pump(kHistoryFilterDebounce + const Duration(milliseconds: 1));

    expect(_filterCalls(pumped.controller).length, 1);
    expect(_filterCalls(pumped.controller).single.args['includeRefs'], <String>[
      'refs/heads/feature/graph-lanes',
    ]);
  });

  testWidgets('a rapid narrow -> wide -> narrow is one walk, not three', (
    tester,
  ) async {
    // What the debounce is actually for. Backspacing out of a query and
    // typing it back moves the request through three *different* values, so
    // the provider's own equality dedupe cannot collapse them and each one
    // reaches the listener. Undebounced this starts three `git rev-list`
    // walks, the first two cancelled mid-flight.
    final PumpedWorkspace pumped = await _pump(tester);
    for (final String query in <String>[
      'graph-lanes',
      'graph',
      'graph-lanes',
    ]) {
      await _typeWithoutSettling(tester, pumped, query);
    }
    await tester.pump(kHistoryFilterDebounce + const Duration(milliseconds: 1));

    expect(_filterCalls(pumped.controller).length, 1);
    expect(_filterCalls(pumped.controller).single.args['includeRefs'], <String>[
      'refs/heads/feature/graph-lanes',
    ]);
  });

  testWidgets('a round trip back to the filter in force sends nothing new', (
    tester,
  ) async {
    // The other half. Once the debounce has coalesced a burst, the value it
    // lands on may be the one already in force -- and `ref.listen` cannot
    // see that, having fired three times with three different values. The
    // comparison against the last request *sent* is what stops the redundant
    // walk.
    final PumpedWorkspace pumped = await _pump(tester);
    await _filter(tester, pumped, 'graph-lanes');
    expect(_filterCalls(pumped.controller).length, 1);

    for (final String query in <String>['graph', 'graph-lanes']) {
      await _typeWithoutSettling(tester, pumped, query);
    }
    await tester.pump(kHistoryFilterDebounce + const Duration(milliseconds: 1));

    expect(_filterCalls(pumped.controller).length, 1);
  });

  testWidgets('two queries that converge on one branch send one filter', (
    tester,
  ) async {
    // 'graph-lanes' and 'gl' are different queries resolving to the same
    // branch (P02-14 rule 3's initials). This one is the *provider* dedupe,
    // not the dispatcher: the request value never changes, so the listener
    // never fires a second time.
    final PumpedWorkspace pumped = await _pump(tester);
    await _filter(tester, pumped, 'graph-lanes');
    await _filter(tester, pumped, 'gl');

    expect(_filterCalls(pumped.controller).length, 1);
  });

  testWidgets('an empty query never dispatches at all', (tester) async {
    // A session opens unfiltered, so there is nothing to say. Dispatching
    // HistoryFilterRequest.none on mount would restart the walk that just
    // finished.
    final PumpedWorkspace pumped = await _pump(tester);
    await _filter(tester, pumped, '');
    await _filter(tester, pumped, '   ');

    expect(_filterCalls(pumped.controller), isEmpty);
  });

  testWidgets('clearing after a filter widens the walk again', (tester) async {
    final PumpedWorkspace pumped = await _pump(tester);
    await _filter(tester, pumped, 'graph-lanes');
    await _filter(tester, pumped, '');

    expect(_filterCalls(pumped.controller).length, 2);
    expect(_filterCalls(pumped.controller).last.args['includeRefs'], isEmpty);
  });
}
