import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_height_reporter.dart';

void main() {
  Future<List<double>> reports(
    WidgetTester tester,
    List<Object?> epochs,
  ) async {
    final List<double> got = <double>[];
    for (final Object? epoch in epochs) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Align(
            alignment: Alignment.topLeft,
            child: SyncHeightReporter(
              epoch: epoch,
              onHeight: got.add,
              child: const SizedBox(width: 10, height: 30),
            ),
          ),
        ),
      );
      await tester.pump();
    }
    return got;
  }

  testWidgets('an unchanged height is reported once while its sink is the '
      'same', (WidgetTester tester) async {
    final Object sink = Object();
    expect(await reports(tester, <Object?>[sink, sink, sink]), <double>[30]);
  });

  // A `2 file` pane rebuilds its slot heights when a diff, a fill or a
  // loading flag changes, and the new ones start from estimates; an item
  // already laid out kept its height and never told them, so the columns
  // stayed misaligned by the estimate's error (6 px, Slice E's
  // staged-lands-after-unstaged case).
  testWidgets('a new sink hears the height again', (WidgetTester tester) async {
    expect(await reports(tester, <Object?>[Object(), Object()]), <double>[
      30,
      30,
    ]);
  });
}
