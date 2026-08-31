// The uncommitted row's diamond and the line that leaves it.
//
// The diamond is **hollow** -- `PaintingStyle.stroke`, deliberately, so it
// cannot be mistaken for a commit dot at a glance down the column. That is
// exactly what makes its geometry different from a commit's: a commit dot is
// filled and haloed, so a connector drawn from its centre is covered. A line
// drawn from this one's centre crosses the transparent interior and pokes out
// through the lower vertex.
//
// The painter was private until this file existed, which is why nothing could
// see that.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_column_painter.dart';
import 'package:gbm_flutter/features/history_graph/widgets/working_copy_row.dart';

class _Line {
  const _Line(this.from, this.to, this.paint);
  final Offset from;
  final Offset to;
  final Paint paint;
}

class _RecordingCanvas implements Canvas {
  final List<_Line> lines = <_Line>[];
  final List<Paint> paths = <Paint>[];

  @override
  void drawLine(Offset p1, Offset p2, Paint paint) =>
      lines.add(_Line(p1, p2, paint));

  @override
  void drawPath(Path path, Paint paint) => paths.add(paint);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

const Size _kSize = Size(16, 26);
const double _kCentreY = 13.0;

_RecordingCanvas _paint({required bool connectsDown}) {
  final _RecordingCanvas canvas = _RecordingCanvas();
  WorkingCopyDotPainter(
    color: const Color(0xFF00FF00),
    connectsDown: connectsDown,
  ).paint(canvas, _kSize);
  return canvas;
}

void main() {
  test(
    'the connector leaves the diamond at its lower vertex, not its centre',
    () {
      final _Line line = _paint(connectsDown: true).lines.single;

      expect(
        line.from.dy,
        _kCentreY + kWorkingCopyDotRadius,
        reason:
            'from the centre it would cross the hollow interior and show '
            'through -- the diamond has no fill to hide it behind',
      );
      expect(line.to.dy, _kSize.height, reason: 'and runs to the row boundary');
      expect(line.from.dx, kGraphLaneInset);
      expect(line.to.dx, kGraphLaneInset);
    },
  );

  test('and it is drawn like every other connector in the graph', () {
    final Paint paint = _paint(connectsDown: true).lines.single.paint;

    expect(
      paint.strokeWidth,
      kGraphEdgeStrokeWidth,
      reason:
          'the same constant the lanes use, not a literal that has to be '
          'kept in step by hand',
    );
    expect(
      paint.strokeCap,
      StrokeCap.round,
      reason:
          'GraphRowPainter caps every edge this way; the join between '
          'this line and those must not be visible',
    );
  });

  test('a clean-topped row draws the diamond and no line at all', () {
    final _RecordingCanvas canvas = _paint(connectsDown: false);

    expect(canvas.lines, isEmpty);
    expect(canvas.paths.length, 1, reason: 'the diamond is still drawn');
  });
}
