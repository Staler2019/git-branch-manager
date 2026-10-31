import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/widgets/gbm_dashed.dart';

/// A vertical rule [height] tall, as the [segment]-th of a run of equal
/// segments.
Widget _rule(double height, {int segment = 0}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      height: height,
      child: GbmDashedLine(
        color: const Color(0xFF000000),
        axis: Axis.vertical,
        segment: segment,
      ),
    ),
  ),
);

Finder _painter() => find.descendant(
  of: find.byType(GbmDashedLine),
  matching: find.byType(CustomPaint),
);

void main() {
  testWidgets('the first segment starts on a dash', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(_rule(22));
    expect(
      _painter(),
      paints
        ..line(p1: const Offset(.5, 0), p2: const Offset(.5, 3))
        ..line(p1: const Offset(.5, 5), p2: const Offset(.5, 8))
        ..line(p1: const Offset(.5, 10), p2: const Offset(.5, 13))
        ..line(p1: const Offset(.5, 15), p2: const Offset(.5, 18))
        ..line(p1: const Offset(.5, 20), p2: const Offset(.5, 22)),
    );
  });

  testWidgets('a later segment carries on the rhythm the ones above it left '
      'off, so stacked segments read as one rule', (WidgetTester tester) async {
    // Segment 0 stopped 2px into its last dash (22 = 4 * 5 + 2), so segment
    // 1 owes that dash its last 1px before its own first gap.
    await tester.pumpWidget(_rule(22, segment: 1));
    expect(
      _painter(),
      paints
        ..line(p1: const Offset(.5, 0), p2: const Offset(.5, 1))
        ..line(p1: const Offset(.5, 3), p2: const Offset(.5, 6))
        ..line(p1: const Offset(.5, 8), p2: const Offset(.5, 11))
        ..line(p1: const Offset(.5, 13), p2: const Offset(.5, 16))
        ..line(p1: const Offset(.5, 18), p2: const Offset(.5, 21)),
    );

    // Segment 2 starts 44 = 8 * 5 + 4 along: inside a gap, 1px from the
    // next dash.
    await tester.pumpWidget(_rule(22, segment: 2));
    expect(
      _painter(),
      paints
        ..line(p1: const Offset(.5, 1), p2: const Offset(.5, 4))
        ..line(p1: const Offset(.5, 6), p2: const Offset(.5, 9)),
    );
  });
}
