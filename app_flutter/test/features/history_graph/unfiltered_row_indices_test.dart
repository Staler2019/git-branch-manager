// The commonest state of the History list is "no filter typed", and in that
// state `matchingRowIndices` used to answer with
// `List<int>.generate(graph.rows.length, (i) => i)` -- a freshly allocated
// N-element list whose i-th element is i.
//
// It is called on **every scroll tick** (CommitGraphView._onScroll ->
// _requestVisibleMeta -> _visibleOids) and again in every `build()`, so a
// fling allocated and threw away one such list per frame. Measured in debug
// JIT with a Stopwatch, matching the DiffScopeCache precedent in
// docs/ledger.md:
//
//     N=703      5.6us/call
//     N=10,000   44.4us/call
//     N=100,000  682.6us/call
//
// Nothing about that list is worth computing: position *is* the row index
// when nothing is filtered. So this is removed rather than cached -- the
// repo's own stated preference ("prefer removing the recomputation to
// caching it"), and it needs no invalidation because there is no state.
//
// Two claims are pinned separately, because either alone can pass while
// the other is broken:
//   1. structural -- the unfiltered answer really is the O(1) view, not a
//      materialised list (otherwise the cost is still being paid);
//   2. behavioural -- the view is indistinguishable from the list it
//      replaced, checked against an independently written oracle.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/commit_search.dart';

/// Independently written oracle: exactly what `matchingRowIndices` returned
/// for an empty query before the fast path existed.
List<int> _oracle(int n) => List<int>.generate(n, (int i) => i);

GraphSnapshotView _graph(int n) => GraphSnapshotView(
  rows: List<GraphRow>.generate(
    n,
    (int i) => GraphRow(
      parentOffset: i,
      edgeOffset: i,
      commitTime: i,
      lane: 0,
      color: 0,
      flags: 1,
    ),
  ),
  // The index goes in the *leading* digits: an oid prefix query is
  // `startsWith`, so trailing-digit indices would give every row the same
  // 8-char prefix and the filter test could not tell two rows apart.
  oidsHex: List<String>.generate(
    n,
    (int i) => '${i.toRadixString(16).padLeft(8, '0')}${'0' * 32}',
  ),
  parentPool: const <int>[],
  laneCount: 1,
  complete: true,
  truncated: false,
);

void main() {
  const Map<String, CommitMeta> noMeta = <String, CommitMeta>{};

  test(
    'an empty query answers with the O(1) view, not a materialised list',
    () {
      final List<int> rows = matchingRowIndices(
        query: '',
        graph: _graph(5000),
        metaCache: noMeta,
      );

      expect(
        rows,
        isA<UnfilteredRowIndices>(),
        reason:
            'A materialised list here is an N-element allocation on every '
            'scroll tick and every build -- 682us/call at 100k commits.',
      );
    },
  );

  test('the view is indistinguishable from the list it replaced', () {
    for (final int n in <int>[0, 1, 703, 5000]) {
      final List<int> rows = matchingRowIndices(
        query: '',
        graph: _graph(n),
        metaCache: noMeta,
      );
      final List<int> oracle = _oracle(n);

      expect(rows.length, oracle.length, reason: 'length differs at n=$n');
      expect(rows, orderedEquals(oracle), reason: 'contents differ at n=$n');
      // The three accessors CommitGraphView actually uses on this list.
      expect(rows.isEmpty, oracle.isEmpty, reason: 'isEmpty differs at n=$n');
      for (int i = 0; i < n; i++) {
        expect(rows[i], oracle[i], reason: 'element $i differs at n=$n');
      }
    }
  });

  test('a non-empty query still answers with a real filtered list', () {
    final GraphSnapshotView graph = _graph(10);
    final List<int> rows = matchingRowIndices(
      query: graph.oidsHex[3].substring(0, 8),
      graph: graph,
      metaCache: noMeta,
    );

    expect(rows, isNot(isA<UnfilteredRowIndices>()));
    expect(rows, <int>[3]);
  });

  test('the view refuses mutation instead of silently accepting it', () {
    final List<int> rows = matchingRowIndices(
      query: '',
      graph: _graph(4),
      metaCache: noMeta,
    );

    expect(() => rows[0] = 9, throwsUnsupportedError);
    expect(() => rows.add(9), throwsUnsupportedError);
  });
}
