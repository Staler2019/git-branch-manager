import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:git_branch_manager/data/ffi/gbm_bindings.dart';
import 'package:git_branch_manager/data/models/graph_snapshot.dart';

void main() {
  group('GraphEdge decoding', () {
    test('decodes edge fields correctly at correct byte offsets', () {
      final buffer = Uint8List(16);
      final data = ByteData.view(buffer.buffer);
      data.setUint32(0, 10, Endian.little); // childRow
      data.setUint32(4, 20, Endian.little); // parentRow
      data.setUint16(8, 1, Endian.little); // lane
      data.setUint16(10, 2, Endian.little); // childLane
      data.setUint8(12, 5); // color
      data.setUint8(13, 1); // kind = mergeParent

      final edge = GraphEdge(
        childRow: data.getUint32(0, Endian.little),
        parentRow: data.getUint32(4, Endian.little),
        lane: data.getUint16(8, Endian.little),
        childLane: data.getUint16(10, Endian.little),
        color: data.getUint8(12),
        kind: EdgeKind.values[data.getUint8(13)],
      );

      expect(edge.childRow, 10);
      expect(edge.parentRow, 20);
      expect(edge.lane, 1);
      expect(edge.childLane, 2);
      expect(edge.color, 5);
      expect(edge.kind, EdgeKind.mergeParent);
    });

    test('edgesSpanning includes edges that span queried row', () {
      final edges = <GraphEdge>[
        GraphEdge(
          childRow: 5,
          parentRow: 10,
          lane: 0,
          childLane: 0,
          color: 0,
          kind: EdgeKind.firstParent,
        ),
        GraphEdge(
          childRow: 15,
          parentRow: 20,
          lane: 1,
          childLane: 1,
          color: 1,
          kind: EdgeKind.mergeParent,
        ),
      ];
      final view = GraphSnapshotView(
        rows: const <GraphRow>[],
        oidsHex: const <String>[],
        parentPool: const <int>[],
        laneCount: 0,
        complete: false,
        truncated: false,
        edges: edges,
      );

      expect(view.edgesSpanning(7), hasLength(1));
      expect(view.edgesSpanning(7)[0].childRow, 5);
      expect(view.edgesSpanning(17), hasLength(1));
      expect(view.edgesSpanning(17)[0].childRow, 15);
      expect(view.edgesSpanning(3), isEmpty);
      expect(view.edgesSpanning(25), isEmpty);
    });

    test('edgesSpanning excludes edges outside queried row', () {
      final edges = <GraphEdge>[
        GraphEdge(
          childRow: 5,
          parentRow: 10,
          lane: 0,
          childLane: 0,
          color: 0,
          kind: EdgeKind.firstParent,
        ),
      ];
      final view = GraphSnapshotView(
        rows: const <GraphRow>[],
        oidsHex: const <String>[],
        parentPool: const <int>[],
        laneCount: 0,
        complete: false,
        truncated: false,
        edges: edges,
      );

      expect(view.edgesSpanning(4), isEmpty);
      expect(view.edgesSpanning(11), isEmpty);
      expect(view.edgesSpanning(7), hasLength(1));
    });
  });
}
