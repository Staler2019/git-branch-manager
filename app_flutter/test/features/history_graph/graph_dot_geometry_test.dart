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
  const _Circle(this.centre, this.radius, this.paint);
  final Offset centre;
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
      circles.add(_Circle(c, radius, paint));

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
  int lane = 0,
  List<GraphEdge> edges = const <GraphEdge>[],
}) => GraphSnapshotView(
  rows: <GraphRow>[
    _row(lane: lane, head: head),
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
    test('is the user-ruled 5.0, not spec\'s 4.2, with the halo still 2px', () {
      // **A user-ratified deviation.** `spec_logic.js:466` is `r: 4.2` and
      // that is what shipped; the user then asked for a bigger dot after the
      // lane pitch went 17 -> 11, and 5.0 is the largest radius that still
      // satisfies the next test. The halo stays 2.0 -- widening it would eat
      // the growth back, since the visible core is `radius - halo / 2`.
      //
      // Do not "fix" this back to 4.2 on the spec citation's authority; the
      // citation is still true and no longer decides the number. Same
      // precedent as the 11px pitch next door.
      final List<_Circle> circles = _paint(_graph()).circles;

      expect(circles.length, 2, reason: 'fill + halo, and nothing else');
      expect(circles[0].radius, kGraphDotRadius);
      expect(circles[1].radius, kGraphDotRadius);
      expect(kGraphDotRadius, 5.0);
      expect(kGraphDotHaloWidth, 2.0);
    });

    test('stops short of the HEAD ring rather than crowding it', () {
      // This is what picks 5.0 out of "bigger", and it is the constraint the
      // user's ruling left standing: the ring keeps spec's `r: 7` at a 1.5
      // stroke, so its *inner* edge is 6.25. A dot whose halo reaches past
      // that leaves no background between the two, and HEAD's ring stops
      // reading as a ring at all -- it reads as a thick edge on the dot.
      //
      // The ring is painted after the dot, so nothing is overdrawn and no
      // exception is thrown either way. Only this arithmetic can see it.
      const double dotOuter = kGraphDotRadius + kGraphDotHaloWidth / 2;
      const double ringInner =
          kGraphHeadRingRadius - kGraphHeadRingStrokeWidth / 2;

      expect(dotOuter, lessThanOrEqualTo(ringInner));
      expect(ringInner - dotOuter, closeTo(0.25, 1e-9));
    });

    test('sits at the inset plus whole pitches, not half a pitch in', () {
      // Spec's own geometry says the same thing: `spec_logic.js:428` is
      // `const L0 = 15, L1 = 32`, i.e. two centres one pitch apart with
      // lane 0 *not* at half a pitch. The `lane + 0.5` this replaced put
      // lane 0 at 8.5, which leaves a 7.75 HEAD ring 0.75px of clearance
      // against the column's left edge -- and none at all once the pitch
      // shrinks. Which lane a centre belongs to is now the inset's job, so
      // the ring's room stops being a function of the pitch.
      expect(_paint(_graph()).circles.first.centre.dx, kGraphLaneInset);
      expect(
        _paint(_graph(lane: 1)).circles.first.centre.dx,
        kGraphLaneInset + GbmLayout.graphLaneWidth,
      );
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

    test('the HEAD ring is drawn whole: inside the column, and clear of '
        'the next lane', () {
      // **What this replaced was a proxy.** «the ring fits inside half a
      // lane» was true only because lane 0's centre sat at half a lane, and
      // it stood in for the two claims below -- which is why it said out
      // loud that "a future lane pitch below 16 would clip the ring". Now
      // that the centre comes from [kGraphLaneInset] rather than from the
      // pitch, both can be stated directly, and neither is a function of
      // the pitch any more.
      //
      // 7px of radius plus half of a 1.5px stroke is 7.75.
      const double outer = kGraphHeadRingRadius + kGraphHeadRingStrokeWidth / 2;

      // 1. Lane 0's ring is not clipped. `commit_row.dart` wraps the
      //    painter in a `ClipRect`, so a ring reaching left of x = 0 loses
      //    its edge on the one lane HEAD sits in most often: the trunk.
      expect(outer, lessThanOrEqualTo(kGraphLaneInset));

      // 2. It does not touch the next lane's connector, whose near edge is
      //    half a stroke inside the pitch. This is the claim the half-lane
      //    proxy was really making, and it is the looser of the two -- a
      //    ring may cross the nominal lane boundary as long as it stops
      //    short of what is actually painted there.
      expect(
        outer,
        lessThanOrEqualTo(GbmLayout.graphLaneWidth - kGraphEdgeStrokeWidth / 2),
      );

      // 3. Vertically unchanged: the ring is centred in a 26px row.
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
