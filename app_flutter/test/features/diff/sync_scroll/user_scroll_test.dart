import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/user_scroll.dart';

void main() {
  ScrollMetrics metrics(Axis axis) => FixedScrollMetrics(
    minScrollExtent: 0,
    maxScrollExtent: 100,
    pixels: 0,
    viewportDimension: 50,
    axisDirection: axis == Axis.vertical
        ? AxisDirection.down
        : AxisDirection.right,
    devicePixelRatio: 1,
  );

  testWidgets('a user scroll names its axis; a follower going idle and a '
      'drag-less start name none', (WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    final BuildContext context = tester.element(find.byType(SizedBox));
    for (final Axis axis in Axis.values) {
      expect(
        userScrollAxis(
          UserScrollNotification(
            metrics: metrics(axis),
            context: context,
            direction: ScrollDirection.reverse,
          ),
        ),
        axis,
      );
      expect(
        userScrollAxis(
          ScrollStartNotification(
            metrics: metrics(axis),
            context: context,
            dragDetails: DragStartDetails(),
          ),
        ),
        axis,
      );
      expect(
        userScrollAxis(
          UserScrollNotification(
            metrics: metrics(axis),
            context: context,
            direction: ScrollDirection.idle,
          ),
        ),
        isNull,
      );
      expect(
        userScrollAxis(
          ScrollStartNotification(metrics: metrics(axis), context: context),
        ),
        isNull,
      );
      expect(
        userScrollAxis(
          ScrollUpdateNotification(metrics: metrics(axis), context: context),
        ),
        isNull,
      );
    }
  });
}
