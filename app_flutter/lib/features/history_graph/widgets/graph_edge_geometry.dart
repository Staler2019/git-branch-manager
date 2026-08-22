import 'package:gbm_flutter/data/models/graph_snapshot.dart';

/// Kind of edge segment to draw, for semantic labeling only -- geometry
/// (lane/Y-fraction) is what the painter actually consumes.
enum EdgeSegmentKind {
  /// Edge starts at this row (this row's commit is the child) and departs
  /// downward from the dot toward the parent.
  intoChildDot,

  /// Edge passes through this row (middle row, not start or end).
  passThrough,

  /// Edge ends at this row (this row's commit is the parent), arriving
  /// from above into the dot.
  intoParentDot,

  /// Boundary stub: arrives from above and stops halfway (no real parent
  /// commit to connect to -- shallow-clone boundary).
  boundaryStub,
}

/// Description of one edge segment to paint at a given row, in
/// lane/row-fraction coordinates. Y fractions are 0.0 (row top), 0.5 (row
/// center, where the commit dot sits) or 1.0 (row bottom). The painter maps
/// these directly to canvas pixels and draws a straight line when
/// [startLane] == [endLane], or a bend otherwise -- it makes no decisions
/// about direction itself.
class EdgeSegment {
  const EdgeSegment({
    required this.startLane,
    required this.endLane,
    required this.startYFraction,
    required this.endYFraction,
    required this.kind,
    required this.edgeColor,
    required this.edgeKind,
  });

  /// Lane the segment starts in.
  final int startLane;

  /// Lane the segment ends in.
  final int endLane;

  /// Vertical start position as a fraction of row height (0.0, 0.5, or 1.0).
  final double startYFraction;

  /// Vertical end position as a fraction of row height (0.0, 0.5, or 1.0).
  final double endYFraction;

  /// What this segment represents, for tests/documentation.
  final EdgeSegmentKind kind;

  /// Color index from edge data (0-6 typically).
  final int edgeColor;

  /// Kind of edge (firstParent, mergeParent, octopus).
  final EdgeKind edgeKind;

  /// True if the segment changes lane (a bend/curve is needed to draw it).
  bool get hasBend => startLane != endLane;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgeSegment &&
          runtimeType == other.runtimeType &&
          startLane == other.startLane &&
          endLane == other.endLane &&
          startYFraction == other.startYFraction &&
          endYFraction == other.endYFraction &&
          kind == other.kind &&
          edgeColor == other.edgeColor &&
          edgeKind == other.edgeKind;

  @override
  int get hashCode => Object.hash(
    startLane,
    endLane,
    startYFraction,
    endYFraction,
    kind,
    edgeColor,
    edgeKind,
  );
}

/// Computes which edge segments to paint at a given row.
///
/// Returns a list of [EdgeSegment] describing each edge that contributes
/// to this row's rendering, already resolved to lane/row-fraction
/// coordinates. The CustomPainter then maps these onto canvas pixels and
/// colors without any further branching on edge direction.
///
/// Rules (from src/core/graph/GraphSnapshot.h):
/// - `lane` is the column the edge occupies while descending.
/// - `childLane` is where it starts; when they differ, a bend occurs at
///   the child row.
/// - A second bend can occur at the *parent* row. `GraphBuilder` never
///   rewrites `lane` once an edge is created (`patchIncoming()` fills in
///   `parentRow` and nothing else), so when several edges converge on one
///   commit only the lane `chooseLane()` picked becomes that row's lane --
///   every other arriving edge has to bend into it here, or it would stop
///   beside the dot instead of touching it. `GraphBuilder.cpp`'s own
///   comment calls this out ("Every other incoming lane bends into `lane`
///   here"), and `GraphAsciiRenderer.cpp` implements it by comparing
///   `edge->lane` against `rows[parentRow].lane`.
/// - No per-row pass-through records: straight segments at paint time via
///   interval query, O(N+E) memory instead of O(N x lanes).
List<EdgeSegment> computeEdgeSegments(
  GraphSnapshotView graph,
  int rowIndex,
  List<GraphRow> rowsInView,
) {
  if (graph.rows.isEmpty || rowIndex < 0 || rowIndex >= graph.rows.length) {
    return const <EdgeSegment>[];
  }

  final List<GraphEdge> spanning = graph.edgesSpanning(rowIndex);

  return <EdgeSegment>[
    for (final GraphEdge edge in spanning)
      _edgeSegmentForRow(graph, edge, rowIndex),
  ];
}

EdgeSegment _edgeSegmentForRow(
  GraphSnapshotView graph,
  GraphEdge edge,
  int rowIndex,
) {
  if (edge.childRow == rowIndex && edge.parentRow == rowIndex) {
    // Degenerate: child and parent both resolve to this row. Draw a
    // zero-length segment at the dot center -- nothing to connect.
    return EdgeSegment(
      startLane: edge.childLane,
      endLane: edge.childLane,
      startYFraction: 0.5,
      endYFraction: 0.5,
      kind: EdgeSegmentKind.intoChildDot,
      edgeColor: edge.color,
      edgeKind: edge.kind,
    );
  }

  if (edge.childRow == rowIndex) {
    // This row's commit is the child: the edge departs from the dot
    // center and continues downward at its descending lane.
    return EdgeSegment(
      startLane: edge.childLane,
      endLane: edge.lane,
      startYFraction: 0.5,
      endYFraction: 1.0,
      kind: EdgeSegmentKind.intoChildDot,
      edgeColor: edge.color,
      edgeKind: edge.kind,
    );
  }

  if (edge.parentRow == rowIndex) {
    // This row's commit is the parent: the edge arrives from directly above
    // in its descending lane and bends into the parent's own lane, ending at
    // the dot center. The two lanes are equal for the edge `chooseLane()`
    // picked and differ for every other edge converging here -- see the
    // parent-bend rule on computeEdgeSegments above. Reading `edge.lane` for
    // both ends instead would leave those lines hanging one column over.
    return EdgeSegment(
      startLane: edge.lane,
      endLane: graph.rows[rowIndex].lane,
      startYFraction: 0.0,
      endYFraction: 0.5,
      kind: EdgeSegmentKind.intoParentDot,
      edgeColor: edge.color,
      edgeKind: edge.kind,
    );
  }

  if (edge.parentRow == kRowBoundary && edge.childRow + 1 == rowIndex) {
    // Boundary stub: arrives from above and stops halfway -- no real
    // parent commit exists here.
    return EdgeSegment(
      startLane: edge.lane,
      endLane: edge.lane,
      startYFraction: 0.0,
      endYFraction: 0.5,
      kind: EdgeSegmentKind.boundaryStub,
      edgeColor: edge.color,
      edgeKind: edge.kind,
    );
  }

  // Middle row: edge passes straight through, top to bottom.
  return EdgeSegment(
    startLane: edge.lane,
    endLane: edge.lane,
    startYFraction: 0.0,
    endYFraction: 1.0,
    kind: EdgeSegmentKind.passThrough,
    edgeColor: edge.color,
    edgeKind: edge.kind,
  );
}
