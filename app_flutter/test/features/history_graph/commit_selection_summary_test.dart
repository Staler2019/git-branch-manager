import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';
import 'package:gbm_flutter/features/history_graph/commit_selection_summary.dart';

void main() {
  const List<String> snapshot = <String>['c5', 'c4', 'c3', 'c2', 'c1'];

  ListSelection<String> selecting(List<String> items) =>
      ListSelection<String>(items: items, anchor: items.lastOrNull);

  group('commitSelectionSummary', () {
    test('is null with nothing selected', () {
      expect(
        commitSelectionSummary(
          selection: const ListSelection<String>(),
          allOids: snapshot,
        ),
        isNull,
      );
    });

    test('is null for a single commit', () {
      // Deliberate: a lone commit has nothing to be contiguous with, so the
      // status bar keeps showing branch/ahead/behind instead of filler.
      expect(
        commitSelectionSummary(
          selection: selecting(<String>['c3']),
          allOids: snapshot,
        ),
        isNull,
      );
    });

    test('reports count and contiguity for an unbroken run', () {
      expect(
        commitSelectionSummary(
          selection: selecting(<String>['c4', 'c3', 'c2']),
          allOids: snapshot,
        ),
        '3 commits · contiguous',
      );
    });

    test('reports a gap as not contiguous', () {
      expect(
        commitSelectionSummary(
          selection: selecting(<String>['c5', 'c3']),
          allOids: snapshot,
        ),
        '2 commits · not contiguous',
      );
    });

    test('selection order does not decide contiguity', () {
      // Ctrl-clicking bottom-up builds the selection in reverse insertion
      // order; the run is still a run.
      expect(
        commitSelectionSummary(
          selection: selecting(<String>['c2', 'c4', 'c3']),
          allOids: snapshot,
        ),
        '3 commits · contiguous',
      );
    });

    test('a commit missing from the snapshot is not contiguous', () {
      // Matches ListSelection.isContiguousIn: an oid the snapshot no longer
      // holds cannot be part of a replayable range, so the honest answer is
      // no -- not a throw, and not a silent drop that would shrink the count.
      expect(
        commitSelectionSummary(
          selection: selecting(<String>['c4', 'gone']),
          allOids: snapshot,
        ),
        '2 commits · not contiguous',
      );
    });
  });
}
