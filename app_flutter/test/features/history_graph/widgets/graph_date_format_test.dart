import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_date_format.dart';

void main() {
  group('formatGraphDate', () {
    test('shows relative time for commits < 24h old', () {
      final now = DateTime(2026, 8, 15, 12, 0, 0);
      final commitDate = DateTime(2026, 8, 15, 11, 30, 0);

      final result = formatGraphDate(commitDate, now);

      expect(result, '30m ago');
    });

    test('shows absolute date for commits >= 1 day old (same year)', () {
      final now = DateTime(2026, 8, 15, 12, 0, 0);
      final commitDate = DateTime(2026, 8, 13, 12, 0, 0);

      final result = formatGraphDate(commitDate, now);

      expect(result, 'Aug 13');
    });

    test('includes year suffix when crossing year boundary', () {
      final now = DateTime(2026, 1, 5, 12, 0, 0);
      final commitDate = DateTime(2025, 12, 20, 12, 0, 0);

      final result = formatGraphDate(commitDate, now);

      expect(result, 'Dec 20, 2025');
    });
  });

  group('formatGraphDateTooltip', () {
    test('returns ISO 8601 format', () {
      final commitDate = DateTime(2026, 8, 15, 14, 30, 45);

      final result = formatGraphDateTooltip(commitDate);

      expect(result.startsWith('2026-08-15T14:30:45'), true);
    });
  });
}
