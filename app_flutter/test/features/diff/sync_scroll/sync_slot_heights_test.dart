// Slice S2: every segment's slot is as tall as its tallest column, and the
// columns share one prefix of slot tops (plan: Slice S, 「補高度」/「演算法」).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_heights.dart';

SyncSlotHeights _heights(List<List<double>> perColumn) =>
    SyncSlotHeights.forSegments(
      columns: perColumn.length,
      segments: perColumn.first.length,
      estimate: (int column, int segment) => perColumn[column][segment],
    );

void main() {
  test('a slot is its tallest column, and the shorter one pads at its end', () {
    final SyncSlotHeights h = _heights(<List<double>>[
      <double>[10, 40, 20],
      <double>[30, 15, 20],
    ]);
    expect(
      <double>[for (int k = 0; k < 3; k++) h.slotHeight(k)],
      <double>[30, 40, 20],
    );
    expect(
      <double>[for (int k = 0; k < 3; k++) h.offsetOf(k)],
      <double>[0, 30, 70],
    );
    expect(h.totalHeight, 90);
    expect(h.spacerHeight(0, 0), 20);
    expect(h.spacerHeight(1, 0), 0);
    expect(h.spacerHeight(1, 1), 25);
    expect(h.spacerHeight(0, 2), 0);
  });

  test('a measured height replaces the estimate', () {
    final SyncSlotHeights h = _heights(<List<double>>[
      <double>[10, 10],
      <double>[10, 10],
    ]);
    h.report(1, 0, 50);
    expect(h.slotHeight(0), 50);
    expect(h.spacerHeight(0, 0), 40);
    expect(h.offsetOf(1), 50);
  });

  group('locate', () {
    final SyncSlotHeights h = _heights(<List<double>>[
      <double>[10, 0, 30],
      <double>[5, 0, 30],
    ]);

    test('a slot top is within 0 of that slot', () {
      expect(h.locate(0), (segment: 0, within: 0.0));
      expect(h.locate(10), (segment: 2, within: 0.0));
    });

    test('inside a slot', () {
      expect(h.locate(25), (segment: 2, within: 15.0));
    });

    test('outside the slots clamps to the ends', () {
      expect(h.locate(-5), (segment: 0, within: 0.0));
      expect(h.locate(1000), (segment: 2, within: 30.0));
    });

    test('round trip', () {
      final Random rng = Random(7);
      for (int i = 0; i < 200; i++) {
        final double p = rng.nextDouble() * h.totalHeight;
        final ({int segment, double within}) at = h.locate(p);
        expect(h.toOffset(at.segment, at.within), closeTo(p, 1e-9));
      }
    });
  });

  test('10k random reports keep the prefix equal to a direct sum', () {
    final Random rng = Random(20261025);
    const int columns = 3;
    const int segments = 400;
    final List<List<double>> own = <List<double>>[
      for (int c = 0; c < columns; c++)
        <double>[for (int k = 0; k < segments; k++) 20],
    ];
    final SyncSlotHeights h = SyncSlotHeights.forSegments(
      columns: columns,
      segments: segments,
      estimate: (_, _) => 20,
    );
    for (int i = 0; i < 10000; i++) {
      final int c = rng.nextInt(columns);
      final int k = rng.nextInt(segments);
      final double v = rng.nextDouble() * 300;
      own[c][k] = v;
      h.report(c, k, v);
      if (i % 97 != 0) continue;
      double top = 0;
      for (int s = 0; s < segments; s++) {
        expect(h.offsetOf(s), closeTo(top, 1e-6));
        top += <double>[for (int c = 0; c < columns; c++) own[c][s]]
            .reduce(max);
      }
      expect(h.totalHeight, closeTo(top, 1e-6));
    }
  });

  group('counting', () {
    test('an unchanged height does not notify', () {
      final SyncSlotHeights h = _heights(<List<double>>[
        <double>[10, 10],
        <double>[10, 10],
      ]);
      int notified = 0;
      h.addListener(() => notified++);
      h.report(0, 1, 10);
      expect(notified, 0);
      h.report(0, 1, 12);
      expect(notified, 1);
      h.report(0, 1, 12);
      expect(notified, 1);
    });

    test('a shorter column growing still notifies though the slot does not '
        'change', () {
      // Its own spacer shrinks, so it has to repaint.
      final SyncSlotHeights h = _heights(<List<double>>[
        <double>[10],
        <double>[30],
      ]);
      int notified = 0;
      h.addListener(() => notified++);
      h.report(0, 0, 20);
      expect(notified, 1);
      expect(h.spacerHeight(0, 0), 10);
    });

    test('the prefix is rebuilt once per change, not once per read', () {
      final SyncSlotHeights h = _heights(<List<double>>[
        <double>[10, 10, 10],
        <double>[10, 10, 10],
      ]);
      h.offsetOf(2);
      expect(h.prefixBuilds, 1);
      h.offsetOf(1);
      h.locate(15);
      h.totalHeight;
      expect(h.prefixBuilds, 1);
      h.report(0, 0, 11);
      h.report(1, 2, 11);
      expect(h.prefixBuilds, 1, reason: 'reports alone build nothing');
      expect(h.offsetOf(2), 21);
      h.locate(3);
      expect(h.prefixBuilds, 2);
    });
  });
}
