// The rule that turns the sidebar's branch filter into a history walk.
//
// A pure function, so this tier can pin the *decision* exhaustively; the
// integration tier pins that the decision reaches the controller, and the
// device tier pins that the FFI signature matches.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/graph_filter_convergence.dart';
import 'package:gbm_flutter/features/sidebar/branch_tree_builder.dart';

RefInfo _branch(
  String shortName, {
  String? fullName,
  RefKind kind = RefKind.localBranch,
}) => RefInfo(
  fullName: fullName ?? 'refs/heads/$shortName',
  shortName: shortName,
  kind: kind,
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

final List<RefInfo> _branches = <RefInfo>[
  _branch('main'),
  _branch('feature/graph-lanes'),
  _branch('feature/graph-columns'),
];

void main() {
  group('historyFilterFor', () {
    test('an empty query leaves the walk alone', () {
      expect(historyFilterFor(_branches, ''), HistoryFilterRequest.none);
      expect(historyFilterFor(_branches, '   '), HistoryFilterRequest.none);
    });

    test('exactly one match collapses the graph to that branch', () {
      // 「只有一個分支：我要有 no merge 的效果，但是不會有平行線」.
      final HistoryFilterRequest request = historyFilterFor(
        _branches,
        'graph-lanes',
      );
      expect(request.includeRefs, <String>['refs/heads/feature/graph-lanes']);
      // --first-parent is exactly what this must NOT set: it drops every
      // commit that arrived through a merge. The single line comes from
      // isLinearWalk()'s bridging in the core, not from narrowing here.
      expect(request.firstParentOnly, isFalse);
      expect(request.noMerges, isTrue);
    });

    test('two matches show the graph as it is today', () {
      // 「兩分支以上，就照目前狀態顯示」. Asserted as a control alongside the
      // case above, because 'graph' and 'graph-lanes' differ only in how many
      // branches they hit -- so this is the same query family, not a
      // different feature.
      expect(filterBranches(_branches, 'graph').length, 2);
      expect(historyFilterFor(_branches, 'graph'), HistoryFilterRequest.none);
    });

    test('a query that matches nothing does not narrow the walk', () {
      // Narrowing to zero refs would hand git no tips at all. Falling back to
      // the full walk keeps the graph readable while the sidebar says 0/N.
      expect(filterBranches(_branches, 'zzz'), isEmpty);
      expect(historyFilterFor(_branches, 'zzz'), HistoryFilterRequest.none);
    });

    test(
      'a remote-only row filters by its full name, not its display name',
      () {
        // mergeLocalAndRemoteBranches strips the '<remote>/' prefix off a
        // remote-only row's shortName so it groups with a same-named local
        // branch. Sending that stripped name to rev-list would resolve to the
        // wrong ref or to none -- the same class of bug as
        // delete_branch_dialog.dart's first-slash split.
        final RefInfo remoteOnly = _branch(
          'staging',
          fullName: 'refs/remotes/origin/staging',
          kind: RefKind.remoteBranch,
        );
        final HistoryFilterRequest request = historyFilterFor(<RefInfo>[
          _branch('main'),
          remoteOnly,
        ], 'staging');

        expect(request.includeRefs, <String>['refs/remotes/origin/staging']);
        expect(request.includeRefs.first, isNot('staging'));
      },
    );

    test('the initials rule reaches the graph too', () {
      // P02-14 rule 3 is one shared matcher; a query that narrows the sidebar
      // by initials must narrow the graph the same way, or the two screens
      // would disagree about what "one branch" means.
      final HistoryFilterRequest request = historyFilterFor(<RefInfo>[
        _branch('main'),
        _branch('feature/graph-lanes'),
      ], 'gl');
      expect(request.includeRefs, <String>['refs/heads/feature/graph-lanes']);
    });

    test(
      'equal requests compare equal, so an identical one can be skipped',
      () {
        // The dispatcher skips a request equal to the last one it sent; without
        // value equality every unrelated rebuild would restart a history walk.
        expect(
          historyFilterFor(_branches, 'graph-lanes'),
          historyFilterFor(_branches, 'graph-lanes'),
        );
        expect(
          historyFilterFor(_branches, 'graph-lanes'),
          isNot(historyFilterFor(_branches, 'graph-columns')),
        );
        expect(
          historyFilterFor(_branches, 'graph-lanes').hashCode,
          historyFilterFor(_branches, 'graph-lanes').hashCode,
        );
      },
    );
  });
}
