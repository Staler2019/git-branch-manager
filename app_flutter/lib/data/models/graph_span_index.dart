import 'graph_snapshot.dart';

/// Row-block size for [GraphSpanIndex]. Chosen to comfortably exceed one
/// viewport (a 1440px-tall window at `kCommitRowHeight` 26 shows ~55 rows),
/// so a query almost never walks more than its own block.
const int kGraphSpanBlockSize = 64;

/// Answers "which edges span row r?" without scanning every edge.
///
/// ## What it replaces, and why
///
/// [GraphSnapshotView.edgesSpanning] was a linear pass over the whole edge
/// array, allocating a fresh list per call. `GraphRowPainter.paint()` calls
/// it once per row, so a 25-row viewport re-scanned every edge 25 times per
/// frame. Debug JIT, `Stopwatch`:
///
/// | commits | edges   | per row  | per 25-row viewport |
/// |---------|---------|----------|---------------------|
/// | 703     | 758     | 8.7us    | 218us               |
/// | 10,000  | 10,829  | 21.5us   | 538us               |
/// | 100,000 | 108,329 | 219.4us  | 5,484us             |
///
/// ## The structure
///
/// Two arrays, both O(N + E) overall:
///
/// - `_startsAt[r]` -- edges whose `childRow` is exactly r.
/// - `_activeAtBlockStart[b]` -- edges spanning row `b * blockSize`,
///   computed by an actual sweep of real spans.
///
/// A query for row r takes the active set at r's block start and filters it
/// to those still covering r, then adds any edge starting in
/// `(blockStart, r]` that covers r. That is exact because **a span is
/// contiguous**: an edge that began before the block and still covers r
/// necessarily covers the block start too, so nothing can slip past.
///
/// This deliberately assumes *nothing* about lanes. `graph_edge_geometry`'s
/// own notes and CLAUDE.md both record that a previously believed lane
/// invariant (`edge.lane == rows[parentRow].lane`) is false, so a lane-keyed
/// structure would be resting on the same kind of premise that already
/// broke once. `_activeAtBlockStart` is a measured fact about each block,
/// not a deduction from graph shape.
///
/// Memory is `O(E)` for the starts plus `O(N / blockSize * activeEdges)`
/// for the block sweep -- a `blockSize`-fold reduction on the per-row
/// records `graph_edge_geometry.dart` explicitly rejected for costing
/// `O(N * lanes)`.
///
/// ## Cache contract
///
/// - **Key**: the [GraphSnapshotView] instance, via an [Expando]. Identity
///   is the honest key here for the same reason it is in `DiffScopeCache`:
///   a snapshot is an immutable DTO rebuilt wholesale by
///   `readGraphSnapshot()`, and nothing ever mutates one in place, so the
///   same instance cannot have different edges. `GraphSnapshotView.empty`
///   is `const` and therefore canonicalised, so every empty snapshot shares
///   one slot -- harmless, because its index is empty either way.
/// - **Invalidation**: none needed, and that is the design rather than a
///   gap. A new snapshot is a new object and so misses the Expando; the old
///   entry dies with the old snapshot, because an [Expando] does not keep
///   its key alive.
/// - **Symptom if this were wrong**: rows would paint another snapshot's
///   connectors -- lines to nowhere, or missing lines -- rather than merely
///   being slow. `graph_span_index_test.dart` checks every row of six graph
///   sizes against an independently written oracle.
class GraphSpanIndex {
  GraphSpanIndex._(this._edges, this._startsAt, this._activeAtBlockStart);

  /// Builds, or returns the already-built index for, [graph].
  factory GraphSpanIndex.of(GraphSnapshotView graph) =>
      _cache[graph] ??= GraphSpanIndex._build(graph);

  factory GraphSpanIndex._build(GraphSnapshotView graph) {
    debugBuildCount++;
    final List<GraphEdge> edges = graph.edges;

    // Extent comes from the edges, not from `rows`. `edgesSpanning` is
    // contractually a pure function of `edges`: graph_snapshot_test.dart
    // queries a view whose `rows` is empty while its edges span rows 5..20,
    // and sizing this off `rows.length` silently answered "no edges span
    // anything" there. `rows.length` still participates, so a graph with
    // trailing edge-free rows keeps a slot for each of them.
    int extent = graph.rows.length;
    for (final GraphEdge edge in edges) {
      final int last = _lastRow(edge);
      if (last + 1 > extent) extent = last + 1;
      if (edge.childRow + 1 > extent) extent = edge.childRow + 1;
    }

    final List<List<int>> startsAt = List<List<int>>.generate(
      extent,
      (_) => const <int>[],
      growable: false,
    );
    for (int e = 0; e < edges.length; e++) {
      final int childRow = edges[e].childRow;
      if (childRow < 0 || childRow >= extent) continue;
      final List<int> existing = startsAt[childRow];
      startsAt[childRow] = existing.isEmpty ? <int>[e] : (existing..add(e));
    }

    // Sweep once, recording the active set at each block boundary.
    final int blockCount = extent == 0
        ? 0
        : (extent + kGraphSpanBlockSize - 1) ~/ kGraphSpanBlockSize;
    final List<List<int>> activeAtBlockStart = List<List<int>>.generate(
      blockCount,
      (_) => const <int>[],
      growable: false,
    );
    final List<int> active = <int>[];
    for (int r = 0; r < extent; r++) {
      // Drop edges that ended before r, then admit those starting at r.
      active.removeWhere((int e) => _lastRow(edges[e]) < r);
      active.addAll(startsAt[r]);
      if (r % kGraphSpanBlockSize == 0) {
        activeAtBlockStart[r ~/ kGraphSpanBlockSize] = active.isEmpty
            ? const <int>[]
            : List<int>.of(active, growable: false);
      }
    }

    return GraphSpanIndex._(edges, startsAt, activeAtBlockStart);
  }

  /// Number of indexes built this isolate, for the counting test the cache
  /// rule requires: an index rebuilt on every call would answer correctly
  /// and be indistinguishable from a working one by its output alone.
  static int debugBuildCount = 0;

  static final Expando<GraphSpanIndex> _cache = Expando<GraphSpanIndex>(
    'GraphSpanIndex',
  );

  final List<GraphEdge> _edges;
  final List<List<int>> _startsAt;
  final List<List<int>> _activeAtBlockStart;

  /// Last row an edge covers. A boundary parent draws as a two-row stub
  /// (`childRow`..`childRow + 1`), not all the way to the end of the graph
  /// -- mirrors `gbm::Edge::spans()` (src/core/graph/GraphSnapshot.h).
  static int _lastRow(GraphEdge edge) =>
      edge.parentRow == kRowBoundary ? edge.childRow + 1 : edge.parentRow;

  /// Edges spanning [rowIndex], in `graph.edges` order.
  ///
  /// Order is part of the contract, not an accident: connectors overlap, so
  /// painting them in a different sequence changes what the user sees where
  /// two lines cross.
  List<GraphEdge> spanning(int rowIndex) {
    if (rowIndex < 0 || rowIndex >= _startsAt.length) {
      return const <GraphEdge>[];
    }

    final int block = rowIndex ~/ kGraphSpanBlockSize;
    final int blockStart = block * kGraphSpanBlockSize;

    final List<int> hits = <int>[];
    for (final int e in _activeAtBlockStart[block]) {
      if (_lastRow(_edges[e]) >= rowIndex) hits.add(e);
    }
    for (int r = blockStart + 1; r <= rowIndex; r++) {
      for (final int e in _startsAt[r]) {
        if (_lastRow(_edges[e]) >= rowIndex) hits.add(e);
      }
    }

    // Restore `graph.edges` order: the block's carry-over set and the
    // in-block starters are collected separately, so the concatenation is
    // not sorted by edge index on its own.
    hits.sort();
    return <GraphEdge>[for (final int e in hits) _edges[e]];
  }
}
