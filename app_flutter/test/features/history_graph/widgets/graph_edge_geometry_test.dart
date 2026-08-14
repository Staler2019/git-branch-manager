import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_edge_geometry.dart';

void main() {
  group('computeEdgeSegments', () {
    test('returns empty list for row with no spanning edges', () {
      const graph = GraphSnapshotView(
        rows: <GraphRow>[],
        oidsHex: <String>[],
        parentPool: <int>[],
        laneCount: 1,
        complete: false,
        truncated: false,
        edges: <GraphEdge>[],
      );

      final segments = computeEdgeSegments(graph, 0, <GraphRow>[]);

      expect(segments, isEmpty);
    });

    test('edge departing from its child row occupies the bottom half '
        '(dot center -> row bottom), not the top half', () {
      final edge = GraphEdge(
        childRow: 0,
        parentRow: 2,
        lane: 1,
        childLane: 1,
        color: 0,
        kind: EdgeKind.firstParent,
      );
      final row = GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 1,
        color: 0,
        flags: 0,
      );

      final segments = computeEdgeSegments(
        GraphSnapshotView(
          rows: <GraphRow>[row],
          oidsHex: <String>['abc'],
          parentPool: <int>[],
          laneCount: 2,
          complete: false,
          truncated: false,
          edges: <GraphEdge>[edge],
        ),
        0,
        <GraphRow>[row],
      );

      expect(segments.length, 1);
      final segment = segments[0];
      expect(segment.startLane, 1);
      expect(segment.endLane, 1);
      expect(segment.startYFraction, 0.5);
      expect(segment.endYFraction, 1.0);
      expect(segment.hasBend, false);
      expect(segment.kind, EdgeSegmentKind.intoChildDot);
    });

    test('draws bend for edge with childLane != lane, still departing '
        'from the dot center down to the row bottom at the new lane', () {
      final edge = GraphEdge(
        childRow: 0,
        parentRow: 2,
        lane: 2,
        childLane: 1,
        color: 0,
        kind: EdgeKind.mergeParent,
      );
      final row = GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 1,
        color: 0,
        flags: 0,
      );

      final segments = computeEdgeSegments(
        GraphSnapshotView(
          rows: <GraphRow>[row],
          oidsHex: <String>['abc'],
          parentPool: <int>[],
          laneCount: 3,
          complete: false,
          truncated: false,
          edges: <GraphEdge>[edge],
        ),
        0,
        <GraphRow>[row],
      );

      expect(segments.length, 1);
      final segment = segments[0];
      expect(segment.startLane, 1);
      expect(segment.endLane, 2);
      expect(segment.startYFraction, 0.5);
      expect(segment.endYFraction, 1.0);
      expect(segment.hasBend, true);
      expect(segment.kind, EdgeSegmentKind.intoChildDot);
    });

    test('draws short stub for boundary edge at childRow+1', () {
      final edge = GraphEdge(
        childRow: 0,
        parentRow: kRowBoundary,
        lane: 1,
        childLane: 1,
        color: 0,
        kind: EdgeKind.firstParent,
      );
      final row = GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 1,
        color: 0,
        flags: 0,
      );

      final segments = computeEdgeSegments(
        GraphSnapshotView(
          rows: <GraphRow>[row, row],
          oidsHex: <String>['a', 'b'],
          parentPool: <int>[],
          laneCount: 2,
          complete: false,
          truncated: false,
          edges: <GraphEdge>[edge],
        ),
        1,
        <GraphRow>[row],
      );

      expect(segments.length, 1);
      final segment = segments[0];
      expect(segment.startLane, 1);
      expect(segment.endLane, 1);
      expect(segment.startYFraction, 0.0);
      expect(segment.endYFraction, 0.5);
      expect(segment.kind, EdgeSegmentKind.boundaryStub);
    });

    test('draws pass-through line for middle row, top to bottom', () {
      final edge = GraphEdge(
        childRow: 0,
        parentRow: 4,
        lane: 1,
        childLane: 1,
        color: 0,
        kind: EdgeKind.firstParent,
      );
      final row = GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 2,
        color: 0,
        flags: 0,
      );

      final segments = computeEdgeSegments(
        GraphSnapshotView(
          rows: <GraphRow>[row, row, row, row, row],
          oidsHex: <String>['a', 'b', 'c', 'd', 'e'],
          parentPool: <int>[],
          laneCount: 3,
          complete: false,
          truncated: false,
          edges: <GraphEdge>[edge],
        ),
        2,
        <GraphRow>[row],
      );

      expect(segments.length, 1);
      final segment = segments[0];
      expect(segment.startLane, 1);
      expect(segment.endLane, 1);
      expect(segment.startYFraction, 0.0);
      expect(segment.endYFraction, 1.0);
      expect(segment.hasBend, false);
      expect(segment.kind, EdgeSegmentKind.passThrough);
    });

    test('draws into parent dot for edge ending at row, top down to '
        'dot center', () {
      final edge = GraphEdge(
        childRow: 0,
        parentRow: 2,
        lane: 1,
        childLane: 1,
        color: 0,
        kind: EdgeKind.firstParent,
      );
      final row = GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 1,
        color: 0,
        flags: 0,
      );

      final segments = computeEdgeSegments(
        GraphSnapshotView(
          rows: <GraphRow>[row, row, row],
          oidsHex: <String>['a', 'b', 'c'],
          parentPool: <int>[],
          laneCount: 2,
          complete: false,
          truncated: false,
          edges: <GraphEdge>[edge],
        ),
        2,
        <GraphRow>[row],
      );

      expect(segments.length, 1);
      final segment = segments[0];
      expect(segment.startLane, 1);
      expect(segment.endLane, 1);
      expect(segment.startYFraction, 0.0);
      expect(segment.endYFraction, 0.5);
      expect(segment.kind, EdgeSegmentKind.intoParentDot);
    });

    test('handles multiple edges simultaneously', () {
      final edge1 = GraphEdge(
        childRow: 0,
        parentRow: 2,
        lane: 0,
        childLane: 0,
        color: 0,
        kind: EdgeKind.firstParent,
      );
      final edge2 = GraphEdge(
        childRow: 0,
        parentRow: 3,
        lane: 2,
        childLane: 1,
        color: 1,
        kind: EdgeKind.mergeParent,
      );
      final row = GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 1,
        color: 0,
        flags: 0,
      );

      final segments = computeEdgeSegments(
        GraphSnapshotView(
          rows: <GraphRow>[row],
          oidsHex: <String>['abc'],
          parentPool: <int>[],
          laneCount: 3,
          complete: false,
          truncated: false,
          edges: <GraphEdge>[edge1, edge2],
        ),
        0,
        <GraphRow>[row],
      );

      expect(segments.length, 2);
      expect(segments[0].startLane, 0);
      expect(segments[0].endLane, 0);
      expect(segments[1].startLane, 1);
      expect(segments[1].endLane, 2);
    });

    test('draws edge that starts and ends at same row as a degenerate '
        'zero-length segment at the dot center', () {
      final edge = GraphEdge(
        childRow: 1,
        parentRow: 1,
        lane: 1,
        childLane: 1,
        color: 0,
        kind: EdgeKind.firstParent,
      );
      final row = GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 1,
        color: 0,
        flags: 0,
      );

      final segments = computeEdgeSegments(
        GraphSnapshotView(
          rows: <GraphRow>[row, row],
          oidsHex: <String>['a', 'b'],
          parentPool: <int>[],
          laneCount: 2,
          complete: false,
          truncated: false,
          edges: <GraphEdge>[edge],
        ),
        1,
        <GraphRow>[row],
      );

      expect(segments.length, 1);
      final segment = segments[0];
      expect(segment.startYFraction, 0.5);
      expect(segment.endYFraction, 0.5);
      expect(segment.kind, EdgeSegmentKind.intoChildDot);
    });
  });
}
