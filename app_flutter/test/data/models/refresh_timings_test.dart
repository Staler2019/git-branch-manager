import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/refresh_timings.dart';

void main() {
  group('RefreshTimings', () {
    test('starts with every stamp null', () {
      const RefreshTimings t = RefreshTimings();

      expect(t.focusAt, isNull);
      expect(t.refsAt, isNull);
      expect(t.statusAt, isNull);
      expect(t.firstDiffAt, isNull);
      expect(t.backgroundDoneAt, isNull);
    });

    test('copyWith sets one stamp and leaves the rest alone', () {
      final DateTime focus = DateTime(2026, 1, 1, 12);
      final RefreshTimings t = const RefreshTimings().copyWith(focusAt: focus);

      expect(t.focusAt, focus);
      expect(t.refsAt, isNull);
      expect(t.statusAt, isNull);
    });

    test('stampIfAbsent sets a null field and leaves a set one alone', () {
      final DateTime first = DateTime(2026, 1, 1, 12, 0, 0);
      final DateTime second = DateTime(2026, 1, 1, 12, 0, 5);

      final RefreshTimings once = const RefreshTimings().stampRefsIfAbsent(
        first,
      );
      expect(once.refsAt, first);

      final RefreshTimings twice = once.stampRefsIfAbsent(second);
      expect(
        twice.refsAt,
        first,
        reason:
            'a later event must not overwrite the first stamp -- only a '
            'fresh reset (a new focus regain) may replace it',
      );
    });

    test('statusToFirstDiff is null until both stamps are present', () {
      const RefreshTimings none = RefreshTimings();
      expect(none.statusToFirstDiff, isNull);

      final RefreshTimings statusOnly = none.copyWith(
        statusAt: DateTime(2026, 1, 1, 12, 0, 0),
      );
      expect(statusOnly.statusToFirstDiff, isNull);
    });

    test('statusToFirstDiff is the gap between the two stamps', () {
      final RefreshTimings t = const RefreshTimings().copyWith(
        statusAt: DateTime(2026, 1, 1, 12, 0, 0, 0),
        firstDiffAt: DateTime(2026, 1, 1, 12, 0, 0, 140),
      );

      expect(t.statusToFirstDiff, const Duration(milliseconds: 140));
    });
  });

  group('refreshTimingsLabel', () {
    test('empty until focusAt is set', () {
      expect(refreshTimingsLabel(const RefreshTimings()), '');
    });

    test('shows only the stamps that have landed so far, each as an '
        'offset from focusAt', () {
      final DateTime focus = DateTime(2026, 1, 1, 12, 0, 0, 0);
      final RefreshTimings t = RefreshTimings(
        focusAt: focus,
        refsAt: focus.add(const Duration(milliseconds: 7)),
      );

      expect(refreshTimingsLabel(t), 'refs 7ms');
    });

    test('lists every landed stamp in stage order', () {
      final DateTime focus = DateTime(2026, 1, 1, 12, 0, 0, 0);
      final RefreshTimings t = RefreshTimings(
        focusAt: focus,
        refsAt: focus.add(const Duration(milliseconds: 7)),
        statusAt: focus.add(const Duration(milliseconds: 32)),
        firstDiffAt: focus.add(const Duration(milliseconds: 118)),
      );

      expect(refreshTimingsLabel(t), 'refs 7ms · status 32ms · diff 118ms');
    });
  });
}
