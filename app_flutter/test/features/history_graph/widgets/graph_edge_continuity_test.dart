// 圖形連線的「連續性」：一條 edge 從子節點的圓點出發，中途不斷線、不換欄，
// 最後彎進父節點的圓點。
//
// 這是 History 上肉眼唯一會注意到的東西，而既有的 widget/painter 測試看不到它:
// GraphRowPainter 只把 EdgeSegment 的 lane/Y 直接映射到畫布（graph_column_painter
// .dart:46-70），所以只要 computeEdgeSegments() 交出的段落串得起來，畫出來就串得
// 起來 —— 反之亦然。因此連續性完全是這個純函式的責任，在這一層測最划算。
//
// --- Fixture 反證性守則 -----------------------------------------------------
// rows[].lane 與 edge.lane / edge.childLane 一律各自寫死，絕不由對方推導。
// 既有 graph_edge_geometry_test.dart 的 'draws into parent dot' 案例就是踩到這個
// 坑：三列共用同一個 GraphRow(lane: 1) 實例、edge 也是 lane 1，於是「線有沒有彎
// 進圓點」兩種行為都會過 —— 那個 fixture 根本無法表達「匯流」。
//
// 每個 fixture 的 lane 值都錨定在 GraphBuilder 的真實輸出上，推導過程記在各自的
// 註解裡；_mergeAndRejoin() 更直接對應 tests/unit/GraphBuilderTest.cpp 的
// TrunkKeepsLaneZeroAcrossAMerge，它已經斷言過 rows 0/1/3/4 在 lane 0、row 2 在
// lane > 0。
//
// --- 範圍外 -----------------------------------------------------------------
// * overflow lane（RowMeta.FlagLaneOverflow）不在本輪。
// * childRow == parentRow 的退化 edge 不在本輪：GraphBuilder 產不出來，
//   tests/unit/GraphBuilderTest.cpp 的 InvariantEdgesAlwaysPointDownwards 已經
//   把它擋掉了（parentRow 必須嚴格大於 childRow）。
// * 顏色不斷言 —— 連續性與配色無關。

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_edge_geometry.dart';

void main() {
  final Map<String, GraphSnapshotView> fixtures = <String, GraphSnapshotView>{
    'linearHistory': _linearHistory(),
    'mergeAndRejoin': _mergeAndRejoin(),
    'shortMergeAndRejoin': _shortMergeAndRejoin(),
    'mergeIntoNextRow': _mergeIntoNextRow(),
    'boundaryStub': _boundaryStub(),
    'boundaryAtLastRow': _boundaryAtLastRow(),
  };

  group('每一列交出的段數，等於橫跨該列的 edge 數', () {
    // P1。少一段就是某條線在這一列整段消失；多一段就是重複描邊。
    fixtures.forEach((String name, GraphSnapshotView graph) {
      test(name, () {
        for (int row = 0; row < graph.rows.length; row++) {
          final int expected = graph.edges
              .where((GraphEdge e) => _spans(e, row))
              .length;
          expect(
            computeEdgeSegments(graph, row, graph.rows).length,
            expected,
            reason: '$name 第 $row 列：段數與橫跨該列的 edge 數不符',
          );
        }
      });
    });
  });

  group('每條 edge 都串成一條不中斷的線', () {
    // P2（垂直）、P3（橫向）、P4a（起點接上子節點圓點）、P5（boundary 收尾）。
    fixtures.forEach((String name, GraphSnapshotView graph) {
      test(name, () {
        expect(graph.edges, isNotEmpty, reason: '$name 沒有任何 edge 可檢查');
        for (int i = 0; i < graph.edges.length; i++) {
          expectEdgeIsContinuous(graph, i, fixture: name);
        }
      });
    });
  });

  group('匯流點：邊線抵達父節點時必須彎進該列的 lane', () {
    // P4b。分支併回主幹時，edge.lane 停在原本下降的那一欄，而父節點的圓點在
    // rows[parentRow].lane —— 兩者不同時線就停在隔壁欄的半空中，接不到點。
    //
    // 這是渲染層的責任，不是 GraphBuilder 的疏漏：patchIncoming()
    // （GraphBuilder.cpp:59-68）只回填 parentRow，刻意不改寫 edge.lane，而
    // GraphBuilder.cpp:105-110 註明「其餘 incoming lane 在此彎入 lane」。C++ 的
    // 參考渲染器確實照做（GraphAsciiRenderer.cpp:122-127 讀 rows[row+1].lane，
    // 不同就畫 '/'）；Dart 這一側原本漏了，這一組就是那個缺陷的回歸鎖。
    //
    // 會踩雷的只有「一個 commit 收到多條位於不同 lane 的 incoming」——
    // 也就是 mergeAndRejoin 與 shortMergeAndRejoin 兩個 fixture。直線、
    // 相鄰兩列、boundary 都不會，所以修正前後它們都綠。
    fixtures.forEach((String name, GraphSnapshotView graph) {
      test(name, () {
        for (int i = 0; i < graph.edges.length; i++) {
          final GraphEdge edge = graph.edges[i];
          if (edge.parentRow == kRowBoundary) {
            continue; // boundary 沒有父節點圓點可接，由 P5 收尾。
          }
          final EdgeSegment arrival = _segmentOf(graph, i, edge.parentRow);
          expect(
            arrival.endLane,
            graph.rows[edge.parentRow].lane,
            reason:
                '$name edge#$i（第 ${edge.childRow} 列 -> 第 ${edge.parentRow} 列，'
                'lane ${edge.lane}）沒有彎進父節點圓點所在的 '
                'lane ${graph.rows[edge.parentRow].lane}，線會停在半空中',
          );
        }
      });
    });
  });
}

// --- 斷言 helper ------------------------------------------------------------

/// 走訪 `graph.edges[edgeIndex]` 橫跨的每一列，斷言各列的段落串成一條不中斷的線。
///
/// 用「在橫跨清單中的位置」而不是顏色來認段落：真實 snapshot 裡同一條 lane 上的
/// edge 共用同一個顏色（GraphBuilder.cpp 的 colorOf(lane)），逼 fixture 給每條
/// edge 不同顏色才能用顏色辨識，那就是不忠實的 fixture。位置法反過來只依賴
/// computeEdgeSegments() 依 graph.edges 順序輸出 —— 這由 edgesSpanning() 的
/// list comprehension 保證（graph_snapshot.dart:120-131）。
void expectEdgeIsContinuous(
  GraphSnapshotView graph,
  int edgeIndex, {
  required String fixture,
}) {
  final GraphEdge edge = graph.edges[edgeIndex];
  final String where =
      '$fixture edge#$edgeIndex'
      '（第 ${edge.childRow} 列 -> '
      '${edge.parentRow == kRowBoundary ? 'boundary' : '第 ${edge.parentRow} 列'}）';

  final int naturalEnd = edge.parentRow == kRowBoundary
      ? edge.childRow + 1
      : edge.parentRow;
  // 被列數截掉：唯一的情況是最後一列的 boundary stub，它的 childRow + 1 不存在。
  final bool clipped = naturalEnd >= graph.rows.length;
  final int lastRow = clipped ? graph.rows.length - 1 : naturalEnd;

  final List<EdgeSegment> chain = <EdgeSegment>[
    for (int row = edge.childRow; row <= lastRow; row++)
      _segmentOf(graph, edgeIndex, row),
  ];
  expect(chain, isNotEmpty, reason: '$where：沒有橫跨任何一列');

  // P4a：起點必須落在子節點圓點的正中心。
  expect(
    chain.first.startLane,
    graph.rows[edge.childRow].lane,
    reason: '$where：起點不在子節點圓點所在的 lane',
  );
  expect(chain.first.startYFraction, 0.5, reason: '$where：起點不在圓點中心（列高的一半）');

  // P2 + P3：列與列的交界處，上一段收在列底、下一段從列頂接起，且不換欄。
  for (int i = 0; i + 1 < chain.length; i++) {
    final int upper = edge.childRow + i;
    expect(
      chain[i].endYFraction,
      1.0,
      reason: '$where：第 $upper 列沒有畫到列底，線在交界處斷開',
    );
    expect(
      chain[i + 1].startYFraction,
      0.0,
      reason: '$where：第 ${upper + 1} 列沒有從列頂接起，線在交界處斷開',
    );
    expect(
      chain[i + 1].startLane,
      chain[i].endLane,
      reason:
          '$where：第 $upper 列收在 lane ${chain[i].endLane}，'
          '第 ${upper + 1} 列卻從 lane ${chain[i + 1].startLane} 起頭，線橫向斷開',
    );
  }

  // 收尾。
  if (clipped) {
    // 截斷的歷史：線畫到列底往畫面外延伸，這是正確的收尾方式。
    expect(chain.last.endYFraction, 1.0, reason: '$where：被列數截掉的線應該畫到列底延伸出畫面');
    return;
  }
  if (edge.parentRow == kRowBoundary) {
    // P5：boundary stub 是合法終止 —— 沒有真實父節點可接，收在半途。
    expect(
      chain.last.kind,
      EdgeSegmentKind.boundaryStub,
      reason: '$where：走到 childRow + 1 應該是 boundary stub',
    );
    expect(chain.last.endYFraction, 0.5, reason: '$where：boundary stub 應該收在列中');
    return;
  }
  expect(
    chain.last.kind,
    EdgeSegmentKind.intoParentDot,
    reason: '$where：最後一段應該是抵達父節點',
  );
  expect(chain.last.endYFraction, 0.5, reason: '$where：終點不在父節點圓點中心（列高的一半）');
}

/// 取 `graph.edges[edgeIndex]` 在 `rowIndex` 這一列交出的那一段。
EdgeSegment _segmentOf(GraphSnapshotView graph, int edgeIndex, int rowIndex) {
  final List<EdgeSegment> segments = computeEdgeSegments(
    graph,
    rowIndex,
    graph.rows,
  );
  // 在它之前、同樣橫跨這一列的 edge 有幾條，它就排在第幾位。
  int position = 0;
  for (int i = 0; i < edgeIndex; i++) {
    if (_spans(graph.edges[i], rowIndex)) {
      position++;
    }
  }
  expect(
    segments.length,
    greaterThan(position),
    reason: 'edge#$edgeIndex 在第 $rowIndex 列沒有交出段落，線整段消失',
  );
  return segments[position];
}

/// `gbm::Edge::spans()` 的複刻（src/core/graph/GraphSnapshot.h:80-83）。
/// 這裡刻意重寫而非呼叫 edgesSpanning()，讓測試對「哪些列該有線」有自己的說法。
bool _spans(GraphEdge edge, int rowIndex) {
  final int end = edge.parentRow == kRowBoundary
      ? edge.childRow + 1
      : edge.parentRow;
  return edge.childRow <= rowIndex && rowIndex <= end;
}

// --- fixtures ---------------------------------------------------------------

GraphRow _row(int lane, {int color = 0, int flags = 0}) => GraphRow(
  parentOffset: 0,
  edgeOffset: 0,
  commitTime: 0,
  lane: lane,
  color: color,
  flags: flags,
);

GraphSnapshotView _graph(List<GraphRow> rows, List<GraphEdge> edges) =>
    GraphSnapshotView(
      rows: rows,
      oidsHex: List<String>.generate(rows.length, (int i) => 'oid$i'),
      parentPool: const <int>[],
      laneCount:
          1 + rows.fold<int>(0, (int m, GraphRow r) => r.lane > m ? r.lane : m),
      complete: true,
      truncated: false,
      edges: edges,
    );

/// 直線歷史，全程 lane 0，沒有任何彎折。
///
///   * row0
///   * row1
///   * row2
///   * row3
GraphSnapshotView _linearHistory() => _graph(
  <GraphRow>[_row(0), _row(0), _row(0), _row(0)],
  <GraphEdge>[
    for (int child = 0; child < 3; child++)
      GraphEdge(
        childRow: child,
        parentRow: child + 1,
        lane: 0,
        childLane: 0,
        color: 0,
        kind: EdgeKind.firstParent,
      ),
  ],
);

/// 一條分支併出去又併回來 —— tests/unit/GraphBuilderTest.cpp 的
/// TrunkKeepsLaneZeroAcrossAMerge，commit id 對應 row 如下：
///
///   row0  commit 1  parents [2, 5]  lane 0（merge）
///   row1  commit 2  parents [3]     lane 0
///   row2  commit 5  parents [6]     lane 1  ← C++ 測試斷言 > 0
///   row3  commit 3  parents [6]     lane 0
///   row4  commit 6  parents []      lane 0  ← 共同祖先回到主幹
///
/// row4 有兩條 incoming（row2 的 lane 1、row3 的 lane 0），chooseLane() 取兩者中
/// 最左的 first-parent，所以 rows[4].lane 是 0，而 row2 那條 edge 的 lane 仍是 1
/// —— 它必須在 row4 彎進 lane 0 才接得到圓點。
GraphSnapshotView _mergeAndRejoin() => _graph(
  <GraphRow>[
    _row(0, flags: 0x08 | 0x02), // merge，2 個 parent
    _row(0, flags: 0x01),
    _row(1, color: 1, flags: 0x01),
    _row(0, flags: 0x01),
    _row(0),
  ],
  const <GraphEdge>[
    GraphEdge(
      childRow: 0,
      parentRow: 1,
      lane: 0,
      childLane: 0,
      color: 0,
      kind: EdgeKind.firstParent,
    ),
    GraphEdge(
      childRow: 0,
      parentRow: 2,
      lane: 1,
      childLane: 0,
      color: 1,
      kind: EdgeKind.mergeParent,
    ),
    GraphEdge(
      childRow: 1,
      parentRow: 3,
      lane: 0,
      childLane: 0,
      color: 0,
      kind: EdgeKind.firstParent,
    ),
    GraphEdge(
      childRow: 2,
      parentRow: 4,
      lane: 1,
      childLane: 1,
      color: 1,
      kind: EdgeKind.firstParent,
    ),
    GraphEdge(
      childRow: 3,
      parentRow: 4,
      lane: 0,
      childLane: 0,
      color: 0,
      kind: EdgeKind.firstParent,
    ),
  ],
);

/// 同時在子節點與父節點兩端彎折的最短情形：
///
///   row0  A  parents [B, C]  lane 0（merge）
///   row1  B  parents [C]     lane 0
///   row2  C  parents []      lane 0
///
/// A -> C 這條 merge edge 在 row0 由 lane 0 彎到 lane 1（第二個 parent 一律往右），
/// 一路降到 row2；而 row2 的 incoming 同時有 B 的 first-parent（lane 0），
/// chooseLane() 偏好 first-parent，所以 rows[2].lane 是 0。
GraphSnapshotView _shortMergeAndRejoin() => _graph(
  <GraphRow>[_row(0, flags: 0x08 | 0x02), _row(0, flags: 0x01), _row(0)],
  const <GraphEdge>[
    GraphEdge(
      childRow: 0,
      parentRow: 1,
      lane: 0,
      childLane: 0,
      color: 0,
      kind: EdgeKind.firstParent,
    ),
    GraphEdge(
      childRow: 0,
      parentRow: 2,
      lane: 1,
      childLane: 0,
      color: 1,
      kind: EdgeKind.mergeParent,
    ),
    GraphEdge(
      childRow: 1,
      parentRow: 2,
      lane: 0,
      childLane: 0,
      color: 0,
      kind: EdgeKind.firstParent,
    ),
  ],
);

/// 相鄰兩列（中間沒有 pass-through 列），且抵達端不需要彎折：
///
///   row0  A  parents [B, C]  lane 0（merge）
///   row1  C  parents []      lane 1  ← 唯一的 incoming 就是那條 merge edge
///   row2  B  parents []      lane 0
GraphSnapshotView _mergeIntoNextRow() => _graph(
  <GraphRow>[_row(0, flags: 0x08 | 0x02), _row(1, color: 1), _row(0)],
  const <GraphEdge>[
    GraphEdge(
      childRow: 0,
      parentRow: 2,
      lane: 0,
      childLane: 0,
      color: 0,
      kind: EdgeKind.firstParent,
    ),
    GraphEdge(
      childRow: 0,
      parentRow: 1,
      lane: 1,
      childLane: 0,
      color: 1,
      kind: EdgeKind.mergeParent,
    ),
  ],
);

/// 父節點在這次 walk 之外（shallow clone 或被 filter 切掉）：edge 收成一截
/// 短 stub，下一列另有一條無關的線。
GraphSnapshotView _boundaryStub() => _graph(
  <GraphRow>[_row(0, flags: 0x41), _row(0, flags: 0x01), _row(0)],
  const <GraphEdge>[
    GraphEdge(
      childRow: 0,
      parentRow: kRowBoundary,
      lane: 0,
      childLane: 0,
      color: 0,
      kind: EdgeKind.firstParent,
    ),
    GraphEdge(
      childRow: 1,
      parentRow: 2,
      lane: 0,
      childLane: 0,
      color: 0,
      kind: EdgeKind.firstParent,
    ),
  ],
);

/// 歷史被 row cap 截斷：最後一列的 parent 落在 walk 之外，stub 該畫的
/// childRow + 1 根本不存在，線只能畫到列底往畫面外延伸。
GraphSnapshotView _boundaryAtLastRow() => _graph(
  <GraphRow>[_row(0, flags: 0x01), _row(0, flags: 0x41)],
  const <GraphEdge>[
    GraphEdge(
      childRow: 0,
      parentRow: 1,
      lane: 0,
      childLane: 0,
      color: 0,
      kind: EdgeKind.firstParent,
    ),
    GraphEdge(
      childRow: 1,
      parentRow: kRowBoundary,
      lane: 0,
      childLane: 0,
      color: 0,
      kind: EdgeKind.firstParent,
    ),
  ],
);
