import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/conflict_resolution/conflict_line_order.dart';

void main() {
  group('ConflictLineOrderState', () {
    test('initial state creates regions with empty sequences', () {
      final state = ConflictLineOrderState.initial(2);

      expect(state.regionCount, 2);
      expect(state.getOrderedLines(0), isEmpty);
      expect(state.getOrderedLines(1), isEmpty);
      expect(state.isManuallyEdited(0), false);
      expect(state.isManuallyEdited(1), false);
    });

    test(
      'appendLine appends ours then theirs produces [ours, theirs] order',
      () {
        final state = ConflictLineOrderState.initial(1);

        final after1 = state.appendLine(0, ConflictLineSource.ours, 'line1\n');
        final after2 = after1.appendLine(
          0,
          ConflictLineSource.theirs,
          'line2\n',
        );

        final ordered = after2.getOrderedLines(0);
        expect(ordered.length, 2);
        expect(ordered[0].source, ConflictLineSource.ours);
        expect(ordered[0].lineContent, 'line1\n');
        expect(ordered[1].source, ConflictLineSource.theirs);
        expect(ordered[1].lineContent, 'line2\n');
      },
    );

    test(
      'appendLine appends theirs then ours produces [theirs, ours] order',
      () {
        final state = ConflictLineOrderState.initial(1);

        final after1 = state.appendLine(
          0,
          ConflictLineSource.theirs,
          'line1\n',
        );
        final after2 = after1.appendLine(0, ConflictLineSource.ours, 'line2\n');

        final ordered = after2.getOrderedLines(0);
        expect(ordered.length, 2);
        expect(ordered[0].source, ConflictLineSource.theirs);
        expect(ordered[0].lineContent, 'line1\n');
        expect(ordered[1].source, ConflictLineSource.ours);
        expect(ordered[1].lineContent, 'line2\n');
      },
    );

    test('removeAt middle entry renumbers correctly', () {
      final state = ConflictLineOrderState.initial(1);

      final after1 = state.appendLine(0, ConflictLineSource.ours, 'line1\n');
      final after2 = after1.appendLine(0, ConflictLineSource.theirs, 'line2\n');
      final after3 = after2.appendLine(0, ConflictLineSource.ours, 'line3\n');

      // Remove middle entry (index 1)
      final afterRemove = after3.removeAt(0, 1);

      final ordered = afterRemove.getOrderedLines(0);
      expect(ordered.length, 2);
      expect(ordered[0].source, ConflictLineSource.ours);
      expect(ordered[0].lineContent, 'line1\n');
      expect(ordered[1].source, ConflictLineSource.ours);
      expect(ordered[1].lineContent, 'line3\n');
    });

    test('undoLastRemoval restores removed entry at original position', () {
      final state = ConflictLineOrderState.initial(1);

      final after1 = state.appendLine(0, ConflictLineSource.ours, 'line1\n');
      final after2 = after1.appendLine(0, ConflictLineSource.theirs, 'line2\n');
      final after3 = after2.appendLine(0, ConflictLineSource.ours, 'line3\n');

      // Remove middle entry (index 1)
      final afterRemove = after3.removeAt(0, 1);
      expect(afterRemove.getOrderedLines(0).length, 2);

      // Undo removal
      final afterUndo = afterRemove.undoLastRemoval(0);

      final ordered = afterUndo.getOrderedLines(0);
      expect(ordered.length, 3);
      expect(ordered[0].source, ConflictLineSource.ours);
      expect(ordered[0].lineContent, 'line1\n');
      expect(ordered[1].source, ConflictLineSource.theirs);
      expect(ordered[1].lineContent, 'line2\n');
      expect(ordered[2].source, ConflictLineSource.ours);
      expect(ordered[2].lineContent, 'line3\n');
    });

    test('markManuallyEdited throws StateError when appending', () {
      final state = ConflictLineOrderState.initial(1);

      final afterAppend = state.appendLine(
        0,
        ConflictLineSource.ours,
        'line1\n',
      );
      final afterEdit = afterAppend.markManuallyEdited(0);

      expect(
        () => afterEdit.appendLine(0, ConflictLineSource.theirs, 'line2\n'),
        throwsStateError,
      );
    });

    test('markManuallyEdited throws StateError when removing', () {
      final state = ConflictLineOrderState.initial(1);

      final afterAppend = state.appendLine(
        0,
        ConflictLineSource.ours,
        'line1\n',
      );
      final afterEdit = afterAppend.markManuallyEdited(0);

      expect(() => afterEdit.removeAt(0, 0), throwsStateError);
    });

    test('markManuallyEdited throws StateError when undoing', () {
      final state = ConflictLineOrderState.initial(1);

      final afterAppend = state.appendLine(
        0,
        ConflictLineSource.ours,
        'line1\n',
      );
      final afterEdit = afterAppend.markManuallyEdited(0);

      expect(() => afterEdit.undoLastRemoval(0), throwsStateError);
    });

    test('resetRegion clears sequence and manuallyEdited flag', () {
      final state = ConflictLineOrderState.initial(1);

      final after1 = state.appendLine(0, ConflictLineSource.ours, 'line1\n');
      final after2 = after1.appendLine(0, ConflictLineSource.theirs, 'line2\n');
      final afterEdit = after2.markManuallyEdited(0);

      expect(afterEdit.getOrderedLines(0).length, 2);
      expect(afterEdit.isManuallyEdited(0), true);

      final afterReset = afterEdit.resetRegion(0);

      expect(afterReset.getOrderedLines(0), isEmpty);
      expect(afterReset.isManuallyEdited(0), false);
    });

    test('assembledResult joins ordered lines with line endings preserved', () {
      final state = ConflictLineOrderState.initial(1);

      final after1 = state.appendLine(0, ConflictLineSource.ours, 'line1\n');
      final after2 = after1.appendLine(0, ConflictLineSource.theirs, 'line2\n');
      final after3 = after2.appendLine(0, ConflictLineSource.ours, 'line3');

      final result = after3.assembledResult(0);

      expect(result, 'line1\nline2\nline3');
    });
  });
}
