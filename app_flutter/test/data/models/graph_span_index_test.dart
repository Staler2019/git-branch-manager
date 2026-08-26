// `GraphSnapshotView.edgesSpanning()` was a linear scan over **every** edge
// in the graph, allocating a fresh list each time. It is called once per
// row per paint (GraphRowPainter.paint -> computeEdgeSegments), so a
// viewport of 25 rows re-scanned the whole edge array 25 times per frame.
//
// Measured in debug JIT with a Stopwatch (docs/ledger.md's precedent):
//
//     N=703      edges=758      8.7us/row     218us per 25-row viewport
//     N=10,000   edges=10,829   21.5us/row    538us
//     N=100,000  edges=108,329  219.4us/row   5,484us  <- a third of a
//                                                         16.7ms frame
//
// This pins the indexed implementation against an independently written
// brute-force oracle. That oracle is the point of the file: CLAUDE.md
// records that a *previously believed* lane invariant
// (`edge.lane == rows[parentRow].lane`) turned out to be false, so any
// structure that leans on graph shape has to be checked against a
// definition of "spans" that assumes nothing at all.
//
// Coverage is deliberately weighted to the shapes an index is most likely
// to get wrong: boundary stubs (whose span is *not* childRow..parentRow),
// overflow-lane rows, edges converging on one parent from several lanes,
// long edges crossing many index blocks, and rows at block boundaries.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/graph_span_index.dart';

/// Independently written oracle. Deliberately a direct transcription of
/// `gbm::Edge::spans()` (src/core/graph/GraphSnapshot.h) rather than a call
/// to the production code, so a bug in the index cannot hide inside the
/// thing that checks it.
List<GraphEdge> oracleSpanning(GraphSnapshotView graph, int rowIndex) {
  final List<GraphEdge> out = <GraphEdge>[];
  for (final GraphEdge edge in graph.edges) {
    final int last = edge.parentRow == kRowBoundary
        ? edge.childRow + 1
        : edge.parentRow;
    if (edge.childRow <= rowIndex && rowIndex <= last) out.add(edge);
  }
  return out;
}

GraphRow _row(int i, {int lane = 0, bool overflow = false}) => GraphRow(
  parentOffset: i,
  edgeOffset: i,
  commitTime: i,
  lane: lane,
  color: lane,
  flags: 1 | (overflow ? 0x80 : 0),
);

/// A graph with every shape the index has to survive.
GraphSnapshotView buildGraph(int n) {
  final List<GraphRow> rows = <GraphRow>[];
  final List<String> oids = <String>[];
  final List<GraphEdge> edges = <GraphEdge>[];

  for (int i = 0; i < n; i++) {
    final int lane = i % 7;
    // Every 23rd row sits in the overflow lane.
    rows.add(_row(i, lane: lane, overflow: i % 23 == 0));
    oids.add('${i.toRadixString(16).padLeft(8, '0')}${'0' * 32}');

    if (i + 1 < n) {
      edges.add(
        GraphEdge(
          childRow: i,
          parentRow: i + 1,
          lane: lane,
          childLane: lane,
          color: lane,
          kind: EdgeKind.firstParent,
        ),
      );
    }
    // Long merge edge: crosses many index blocks.
    if (i % 12 == 0 && i + 97 < n) {
      edges.add(
        GraphEdge(
          childRow: i,
          parentRow: i + 97,
          lane: (lane + 1) % 7,
          childLane: lane,
          color: (lane + 1) % 7,
          kind: EdgeKind.mergeParent,
        ),
      );
    }
    // Second edge converging on the SAME parent from a different lane.
    if (i % 31 == 0 && i + 97 < n) {
      edges.add(
        GraphEdge(
          childRow: i,
          parentRow: i + 97,
          lane: (lane + 3) % 7,
          childLane: lane,
          color: (lane + 3) % 7,
          kind: EdgeKind.mergeParent,
        ),
      );
    }
    // Boundary stub: spans childRow..childRow+1 only, NOT to the end.
    if (i % 41 == 0) {
      edges.add(
        GraphEdge(
          childRow: i,
          parentRow: kRowBoundary,
          lane: (lane + 2) % 7,
          childLane: lane,
          color: (lane + 2) % 7,
          kind: EdgeKind.mergeParent,
        ),
      );
    }
    // Octopus: a third parent far away.
    if (i % 57 == 0 && i + 200 < n) {
      edges.add(
        GraphEdge(
          childRow: i,
          parentRow: i + 200,
          lane: (lane + 4) % 7,
          childLane: lane,
          color: (lane + 4) % 7,
          kind: EdgeKind.octopus,
        ),
      );
    }
  }

  return GraphSnapshotView(
    rows: rows,
    oidsHex: oids,
    parentPool: List<int>.generate(n, (int i) => i),
    laneCount: 7,
    complete: true,
    truncated: false,
    edges: edges,
  );
}

void main() {
  group('GraphSpanIndex matches the brute-force oracle', () {
    for (final int n in <int>[1, 2, 64, 65, 300, 2000]) {
      test('on every row of an n=$n graph', () {
        final GraphSnapshotView graph = buildGraph(n);
        final GraphSpanIndex index = GraphSpanIndex.of(graph);

        // Every row, not a sample: an off-by-one at a block edge shows up
        // on exactly one row and sampling would step straight over it.
        for (int r = 0; r < n; r++) {
          expect(
            index.spanning(r),
            orderedEquals(oracleSpanning(graph, r)),
            reason: 'row $r of $n disagrees with the oracle',
          );
        }
      });
    }
  });

  // The generated graph above emits edges in childRow order, which is what
  // the C++ builder happens to do today -- and under that ordering the
  // index's block carry-over set already comes out in `graph.edges` order,
  // so the order-restoring sort is invisible. Nothing in the Dart layer
  // *guarantees* that ordering (CLAUDE.md records a lane invariant that was
  // believed and false), so this reverses the edge array to give the sort
  // something it has to actually do. Without it the mutation stays green
  // and the order claim is untested.
  test('order follows graph.edges even when edges are not childRow-sorted', () {
    final GraphSnapshotView ordered = buildGraph(300);
    final GraphSnapshotView shuffled = GraphSnapshotView(
      rows: ordered.rows,
      oidsHex: ordered.oidsHex,
      parentPool: ordered.parentPool,
      laneCount: ordered.laneCount,
      complete: true,
      truncated: false,
      edges: ordered.edges.reversed.toList(growable: false),
    );

    final GraphSpanIndex index = GraphSpanIndex.of(shuffled);
    for (int r = 0; r < 300; r++) {
      expect(
        index.spanning(r),
        orderedEquals(oracleSpanning(shuffled, r)),
        reason: 'row $r must paint in graph.edges order, not block order',
      );
    }
  });

  test('out-of-range rows answer empty, as the scan did', () {
    final GraphSnapshotView graph = buildGraph(50);
    final GraphSpanIndex index = GraphSpanIndex.of(graph);

    expect(index.spanning(-1), isEmpty);
    expect(index.spanning(5000), isEmpty);
  });

  test('an empty graph builds an empty index', () {
    final GraphSpanIndex index = GraphSpanIndex.of(GraphSnapshotView.empty);
    expect(index.spanning(0), isEmpty);
  });

  test('the index is built once per snapshot and reused', () {
    final GraphSnapshotView graph = buildGraph(100);

    expect(
      identical(GraphSpanIndex.of(graph), GraphSpanIndex.of(graph)),
      isTrue,
      reason:
          'Rebuilding per call would reintroduce the per-paint cost this '
          'exists to remove.',
    );
  });

  test('a different snapshot gets its own index', () {
    final GraphSnapshotView a = buildGraph(100);
    final GraphSnapshotView b = buildGraph(100);

    expect(identical(GraphSpanIndex.of(a), GraphSpanIndex.of(b)), isFalse);
  });

  test('edgesSpanning routes through the index and stays correct', () {
    final GraphSnapshotView graph = buildGraph(300);

    // Counting, not just asserting on the output: an index rebuilt on every
    // call would answer correctly and look identical from the outside --
    // the exact failure the repo's cache rule says output assertions cannot
    // see. 300 calls, one build.
    final int buildsBefore = GraphSpanIndex.debugBuildCount;
    for (int r = 0; r < 300; r++) {
      expect(graph.edgesSpanning(r), orderedEquals(oracleSpanning(graph, r)));
    }
    expect(
      GraphSpanIndex.debugBuildCount - buildsBefore,
      1,
      reason: '300 edgesSpanning calls must share one index, not rebuild it',
    );
  });

  test('a fresh snapshot builds exactly one more index', () {
    final int before = GraphSpanIndex.debugBuildCount;
    final GraphSnapshotView graph = buildGraph(50);
    graph.edgesSpanning(0);
    graph.edgesSpanning(10);
    expect(GraphSpanIndex.debugBuildCount - before, 1);
  });
}
