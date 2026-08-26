// The pure half of spec P03 SCOPES' one-shot temporary scope: turning "these
// row keys are covered" back into the per-hunk line lists `gbm_stage_lines`
// takes. The widget half is in `scoped_diff_view_test.dart`.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/selection_touch.dart';

void main() {
  group('touchedChangedLines', () {
    const Map<int, Set<int>> changed = <int, Set<int>>{
      0: <int>{1, 4},
      1: <int>{0, 2},
      2: <int>{3},
    };

    test('keeps only the lines that actually move', () {
      // A drag starts and ends in context; those rows are touched but there
      // is nothing about them to stage.
      final Map<int, List<int>> result = touchedChangedLines(<String>{
        selectionRowKey(0, 0),
        selectionRowKey(0, 1),
        selectionRowKey(0, 2),
      }, changed);

      expect(result, <int, List<int>>{
        0: <int>[1],
      });
    });

    test('a selection touching only context yields nothing to stage', () {
      expect(
        touchedChangedLines(<String>{
          selectionRowKey(0, 0),
          selectionRowKey(0, 3),
        }, changed),
        isEmpty,
        reason:
            'an empty result is what tells the view to draw no temporary '
            'scope at all, rather than a card whose button does nothing',
      );
    });

    test('a selection crossing two hunks splits into one entry per hunk', () {
      // gbm_stage_lines takes one hunk index, so a patch spanning two of
      // them is two calls -- the split has to happen before the call, not
      // be discovered by git afterwards.
      final Map<int, List<int>> result = touchedChangedLines(<String>{
        selectionRowKey(0, 4),
        selectionRowKey(1, 0),
        selectionRowKey(1, 2),
      }, changed);

      expect(result, <int, List<int>>{
        0: <int>[4],
        1: <int>[0, 2],
      });
    });

    test('hunks come back in file order, not in set order', () {
      // Three hunks, seeded out of order: with two, a reversal of the
      // insertion order is indistinguishable from a sort, and a test that
      // cannot tell them apart pins nothing.
      final Map<int, List<int>> result = touchedChangedLines(<String>{
        selectionRowKey(2, 3),
        selectionRowKey(0, 1),
        selectionRowKey(1, 0),
      }, changed);

      expect(result.keys.toList(), <int>[0, 1, 2]);
    });

    test('lines within a hunk come back sorted', () {
      final Map<int, List<int>> result = touchedChangedLines(<String>{
        selectionRowKey(0, 4),
        selectionRowKey(0, 1),
      }, changed);

      expect(result[0], <int>[1, 4]);
    });

    test('a key for a hunk that has no changed lines is dropped', () {
      // Positional keys survive a diff reload that the tracker has not been
      // cleared for; a stale one must not conjure a hunk out of nothing.
      expect(
        touchedChangedLines(<String>{selectionRowKey(9, 0)}, changed),
        isEmpty,
      );
    });
  });
}
