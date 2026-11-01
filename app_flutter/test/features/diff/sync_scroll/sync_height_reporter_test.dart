import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_code_row_marker.dart';
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
              onReport: (double height, double? _) => got.add(height),
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

  // Slice H: an item also tells how far down its first code row starts.
  group('lead', () {
    Future<List<(double, double?)>> reports(
      WidgetTester tester,
      List<double?> above,
    ) async {
      final Object sink = Object();
      final List<(double, double?)> got = <(double, double?)>[];
      for (final double? gap in above) {
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Align(
              alignment: Alignment.topLeft,
              child: SyncHeightReporter(
                epoch: sink,
                onReport: (double h, double? lead) => got.add((h, lead)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // [gap] null: the item draws no code row at all.
                    SizedBox(width: 10, height: 40 - (gap ?? 0)),
                    if (gap != null) ...<Widget>[
                      const SyncCodeRowMarker(
                        child: SizedBox(width: 10, height: 5),
                      ),
                      SizedBox(width: 10, height: gap - 5),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }
      return got;
    }

    testWidgets('the first code row\'s top, or none', (
      WidgetTester tester,
    ) async {
      expect(await reports(tester, <double?>[12]), <(double, double?)>[
        (40, 28),
      ]);
    });

    testWidgets('an item with no code row reports no lead', (
      WidgetTester tester,
    ) async {
      expect(await reports(tester, <double?>[null]), <(double, double?)>[
        (40, null),
      ]);
    });

    // A one-shot block moving within a card keeps its height and moves its
    // first row (plan: Slice H, HB4).
    testWidgets('a lead that changes alone is reported', (
      WidgetTester tester,
    ) async {
      expect(await reports(tester, <double?>[12, 20]), <(double, double?)>[
        (40, 28),
        (40, 20),
      ]);
    });
  });
}
