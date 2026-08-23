// The graph's *numbers*: dot radius, halo, HEAD ring and connector width,
// each against the mockup that draws them.
//
// This file exists because changing all four broke nothing. The suite was
// green at `r = 3.5` with no halo and green at spec's `4.2` with one, since
// `graph_column_painter_test.dart` locks only `shouldRepaint` and every
// other graph test asserts layout rather than paint. A change no test can
// see is a change the next person undoes by accident -- the same reason the
// 26px row height got its own lock one commit earlier.
//
// The canvas below records draw calls rather than pixels on purpose: these
// are spec's own literals (`spec_logic.js:466-467`, `spec_raw.html:1302`),
// so the assertion that matters is "the painter asked for 4.2", not "a
// rasteriser produced a particular image".
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_column_painter.dart';
import 'package:gbm_flutter/theme/tokens.dart';

class _Circle {
  const _Circle(this.radius, this.paint);
  final double radius;
  final Paint paint;
}

/// Records the calls [GraphRowPainter] makes. `Canvas` has an implicit
/// interface, so implementing it and letting `noSuchMethod` swallow the
/// ~40 methods this painter never calls is cheaper than a `PictureRecorder`
/// whose output is opaque to assertions.
class _RecordingCanvas implements Canvas {
  final List<_Circle> circles = <_Circle>[];
  final List<Paint> strokes = <Paint>[];

  @override
  void drawCircle(Offset c, double radius, Paint paint) =>
      circles.add(_Circle(radius, paint));

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) => strokes.add(paint);

  @override
  void drawPath(Path path, Paint paint) => strokes.add(paint);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// `GraphRow.isHead` is `flags & 0x20`, not the low bit.
const int _kHeadFlag = 0x20;

GraphRow _row({int lane = 0, int color = 0, bool head = false}) => GraphRow(
  parentOffset: 0,
  edgeOffset: 0,
  commitTime: 0,
  lane: lane,
  color: color,
  flags: head ? _kHeadFlag : 0,
);

GraphSnapshotView _graph({
  bool head = false,
  List<GraphEdge> edges = const <GraphEdge>[],
}) => GraphSnapshotView(
  rows: <GraphRow>[
    _row(head: head),
    _row(),
  ],
  oidsHex: const <String>['a', 'b'],
  parentPool: const <int>[],
  laneCount: 2,
  complete: true,
  truncated: false,
  edges: edges,
);

_RecordingCanvas _paint(GraphSnapshotView graph) {
  final _RecordingCanvas canvas = _RecordingCanvas();
  GraphRowPainter(
    row: graph.rows.first,
    rowIndex: 0,
    graph: graph,
    laneWidth: GbmLayout.graphLaneWidth,
    colors: tokensFor(GbmThemeVariant.darkTechnical),
  ).paint(canvas, const Size(34, 26));
  return canvas;
}

void main() {
  final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

  // Colours go through `toARGB32()`: `Paint.color` quantises what it is
  // handed, so a read-back compares unequal to the token it came from while
  // printing identically -- an assertion failure whose two lines are the
  // same text.
  group('the commit dot', () {
    test('is spec\'s 4.2 with a 2px panel-coloured halo', () {
      final List<_Circle> circles = _paint(_graph()).circles;

      expect(circles.length, 2, reason: 'fill + halo, and nothing else');
      expect(circles[0].radius, kGraphDotRadius);
      expect(circles[1].radius, kGraphDotRadius);
      expect(kGraphDotRadius, 4.2);
      expect(kGraphDotHaloWidth, 2.0);
    });

    test('paints the fill first so the halo eats 1px of it, as SVG does', () {
      // SVG centres a stroke on its path and paints it *over* the fill, so
      // `r: 4.2` with a 2px stroke shows a 3.2 core inside a halo reaching
      // 5.2. Reversing these two calls is a one-line edit that looks
      // equivalent and is not -- it would show a 4.2 core.
      final List<_Circle> circles = _paint(_graph()).circles;

      expect(circles[0].paint.style, PaintingStyle.fill);
      expect(
        circles[0].paint.color.toARGB32(),
        colors.graphLanes[0].toARGB32(),
      );
      expect(circles[1].paint.style, PaintingStyle.stroke);
      expect(circles[1].paint.color.toARGB32(), colors.surfacePanel.toARGB32());
      expect(circles[1].paint.strokeWidth, kGraphDotHaloWidth);
    });

    test('does not grow for HEAD -- HEAD gets a ring instead', () {
      final List<_Circle> circles = _paint(_graph(head: true)).circles;

      // The code this replaced drew HEAD as a *bigger* dot (4.5 vs 3.5) with
      // a lane-coloured ring 2px outside it. Spec keeps every dot at 4.2 and
      // gives HEAD a fixed `r: 7` ring in the accent colour, so "you are
      // here" reads identically whichever lane HEAD sits in.
      expect(circles.length, 3);
      expect(circles[0].radius, kGraphDotRadius);

      final _Circle ring = circles[2];
      expect(ring.radius, kGraphHeadRingRadius);
      expect(ring.radius, 7.0);
      expect(ring.paint.style, PaintingStyle.stroke);
      expect(ring.paint.strokeWidth, kGraphHeadRingStrokeWidth);
      expect(ring.paint.strokeWidth, 1.5);
      expect(ring.paint.color.toARGB32(), colors.accent.toARGB32());
    });

    test('the HEAD ring fits inside its lane and its row', () {
      // 7px of radius plus half of a 1.5px stroke is 7.75, against a 17px
      // lane (8.5 to the lane edge) and a 26px row (13). Both spec numbers,
      // but they are only compatible by a small margin -- a future lane
      // pitch below 16 would clip the ring, and this says so out loud.
      const double outer = kGraphHeadRingRadius + kGraphHeadRingStrokeWidth / 2;
      expect(outer, lessThanOrEqualTo(GbmLayout.graphLaneWidth / 2));
      expect(outer, lessThanOrEqualTo(GbmSpacing.rowHeightCompact / 2));
    });
  });

  group('the connectors', () {
    test('are spec\'s 1.75 with a round cap', () {
      final _RecordingCanvas canvas = _paint(
        _graph(
          edges: const <GraphEdge>[
            GraphEdge(
              childRow: 0,
              parentRow: 1,
              lane: 0,
              childLane: 0,
              color: 0,
              kind: EdgeKind.firstParent,
            ),
          ],
        ),
      );

      expect(canvas.strokes, isNotEmpty, reason: 'fixture must draw an edge');
      for (final Paint paint in canvas.strokes) {
        expect(paint.strokeWidth, kGraphEdgeStrokeWidth);
        expect(paint.strokeWidth, 1.75);
        expect(paint.strokeCap, StrokeCap.round);
      }
    });
  });
}
