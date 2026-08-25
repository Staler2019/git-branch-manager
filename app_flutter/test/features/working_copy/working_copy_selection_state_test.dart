import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/file_tree.dart';
import 'package:gbm_flutter/features/working_copy/working_copy_selection_state.dart';

void main() {
  group('WorkingCopySelectionState', () {
    final testPaths = <String>[
      'file1.txt',
      'file2.txt',
      'file3.txt',
      'file4.txt',
      'file5.txt',
    ];

    test('empty state initializes correctly', () {
      final state = WorkingCopySelectionState(allPaths: testPaths);
      expect(state.selected, isEmpty);
      expect(state.lastClickedPath, isNull);
      expect(state.allPaths, equals(testPaths));
    });

    group('single file selection', () {
      test('select single file', () {
        final state = WorkingCopySelectionState(allPaths: testPaths);
        final newState = state.selectSinglePath('file2.txt');
        expect(newState.selected, equals({'file2.txt'}));
        expect(newState.lastClickedPath, equals('file2.txt'));
      });

      test('select different file replaces previous selection', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file1.txt');
        final newState = state.selectSinglePath('file3.txt');
        expect(newState.selected, equals({'file3.txt'}));
        expect(newState.lastClickedPath, equals('file3.txt'));
      });
    });

    group('Ctrl/Cmd+click (accumulate)', () {
      test('toggle add to selection', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file1.txt');
        final newState = state.togglePath('file2.txt');
        expect(newState.selected, equals({'file1.txt', 'file2.txt'}));
        expect(newState.lastClickedPath, equals('file2.txt'));
      });

      test('toggle remove from selection', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file1.txt').togglePath('file2.txt');
        final newState = state.togglePath('file2.txt');
        expect(newState.selected, equals({'file1.txt'}));
        expect(newState.lastClickedPath, equals('file2.txt'));
      });

      test('accumulate multiple files', () {
        var state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file1.txt');
        state = state.togglePath('file2.txt');
        state = state.togglePath('file4.txt');
        expect(state.selected, equals({'file1.txt', 'file2.txt', 'file4.txt'}));
      });
    });

    group('Shift+click (range selection)', () {
      test('range from anchor to clicked path forward', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file1.txt');
        final newState = state.shiftSelectPath('file3.txt');
        expect(
          newState.selected,
          equals({'file1.txt', 'file2.txt', 'file3.txt'}),
        );
        expect(
          newState.lastClickedPath,
          equals('file1.txt'),
        ); // anchor unchanged
      });

      test('range from anchor to clicked path backward', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file3.txt');
        final newState = state.shiftSelectPath('file1.txt');
        expect(
          newState.selected,
          equals({'file1.txt', 'file2.txt', 'file3.txt'}),
        );
        expect(newState.lastClickedPath, equals('file3.txt'));
      });

      test('range single file', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file2.txt');
        final newState = state.shiftSelectPath('file2.txt');
        expect(newState.selected, equals({'file2.txt'}));
      });

      test('shift without anchor acts as single select', () {
        final state = WorkingCopySelectionState(allPaths: testPaths);
        final newState = state.shiftSelectPath('file2.txt');
        expect(newState.selected, equals({'file2.txt'}));
        expect(newState.lastClickedPath, equals('file2.txt'));
      });
    });

    group('Shift+Ctrl/Cmd+click (range with accumulate)', () {
      test('union range into existing selection', () {
        var state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file1.txt');
        state = state.togglePath('file3.txt');
        // Now selected: {file1, file3}, anchor is file3
        final newState = state.shiftControlSelectPath('file5.txt');
        // Should add range file3->file5 to existing selection (file3, file4, file5)
        expect(
          newState.selected,
          equals({'file1.txt', 'file3.txt', 'file4.txt', 'file5.txt'}),
        );
      });

      test('range with accumulate backward', () {
        var state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file4.txt');
        final newState = state.shiftControlSelectPath('file2.txt');
        // Should add range file4->file2 to selection (file2, file3, file4)
        expect(
          newState.selected,
          equals({'file2.txt', 'file3.txt', 'file4.txt'}),
        );
      });
    });

    group('select/deselect all', () {
      test('selectAll selects all paths', () {
        final state = WorkingCopySelectionState(allPaths: testPaths);
        final newState = state.selectAll();
        expect(newState.selected, equals(testPaths.toSet()));
      });

      test('deselectAll clears selection', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectAll();
        final newState = state.deselectAll();
        expect(newState.selected, isEmpty);
      });

      test('toggleSelectAll with empty selection selects all', () {
        final state = WorkingCopySelectionState(allPaths: testPaths);
        final newState = state.toggleSelectAll();
        expect(newState.selected, equals(testPaths.toSet()));
      });

      test('toggleSelectAll with all selected deselects all', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectAll();
        final newState = state.toggleSelectAll();
        expect(newState.selected, isEmpty);
      });

      test('toggleSelectAll with partial selection selects all', () {
        var state = WorkingCopySelectionState(allPaths: testPaths);
        state = state.selectSinglePath('file1.txt').togglePath('file3.txt');
        final newState = state.toggleSelectAll();
        expect(newState.selected, equals(testPaths.toSet()));
      });
    });

    group('bulk operations', () {
      test('selectPaths adds multiple paths', () {
        final state = WorkingCopySelectionState(allPaths: testPaths);
        final newState = state.selectPaths({
          'file1.txt',
          'file3.txt',
          'file5.txt',
        });
        expect(
          newState.selected,
          equals({'file1.txt', 'file3.txt', 'file5.txt'}),
        );
      });

      test('deselectPaths removes multiple paths', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectAll();
        final newState = state.deselectPaths({'file1.txt', 'file3.txt'});
        expect(
          newState.selected,
          equals({'file2.txt', 'file4.txt', 'file5.txt'}),
        );
      });
    });

    group('syncWithPaths pruning', () {
      test('prunes selected paths that are no longer in list', () {
        final state = WorkingCopySelectionState(allPaths: testPaths)
            .selectSinglePath('file2.txt')
            .togglePath('file3.txt')
            .togglePath('file5.txt');
        // Now selected: {file2, file3, file5}
        final newPaths = <String>['file1.txt', 'file3.txt', 'file5.txt'];
        final newState = state.syncWithPaths(newPaths);
        expect(
          newState.selected,
          equals({'file3.txt', 'file5.txt'}),
        ); // file2 pruned
        expect(newState.allPaths, equals(newPaths));
      });

      test('keeps selection for paths that still exist', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file1.txt').togglePath('file3.txt');
        final newPaths = <String>['file1.txt', 'file2.txt', 'file3.txt'];
        final newState = state.syncWithPaths(newPaths);
        expect(newState.selected, equals({'file1.txt', 'file3.txt'}));
      });

      test('prunes anchor if removed', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file2.txt');
        final newPaths = <String>['file1.txt', 'file3.txt', 'file4.txt'];
        final newState = state.syncWithPaths(newPaths);
        expect(newState.lastClickedPath, isNull);
      });

      test('handles empty new paths', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectAll();
        final newState = state.syncWithPaths(<String>[]);
        expect(newState.selected, isEmpty);
        expect(newState.allPaths, isEmpty);
      });
    });

    group('tri-state checkbox logic', () {
      test('unchecked when nothing selected', () {
        final state = WorkingCopySelectionState(allPaths: testPaths);
        expect(state.getCheckState(), equals(CheckState.unchecked));
      });

      test('checked when all selected', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectAll();
        expect(state.getCheckState(), equals(CheckState.checked));
      });

      test('indeterminate when partial selection', () {
        final state = WorkingCopySelectionState(
          allPaths: testPaths,
        ).selectSinglePath('file1.txt').togglePath('file3.txt');
        expect(state.getCheckState(), equals(CheckState.indeterminate));
      });

      test('unchecked with empty paths', () {
        final state = WorkingCopySelectionState(allPaths: <String>[]);
        expect(state.getCheckState(), equals(CheckState.unchecked));
      });
    });

    group('edge cases', () {
      test('selecting nonexistent path does nothing', () {
        final state = WorkingCopySelectionState(allPaths: testPaths);
        final newState = state.selectSinglePath('nonexistent.txt');
        expect(newState.selected, isEmpty);
      });

      test('empty paths list', () {
        final state = WorkingCopySelectionState(allPaths: <String>[]);
        expect(state.selected, isEmpty);
        expect(state.getCheckState(), equals(CheckState.unchecked));
      });

      test('single path', () {
        final state = WorkingCopySelectionState(allPaths: const ['file.txt']);
        final newState = state.selectSinglePath('file.txt');
        expect(newState.selected, equals({'file.txt'}));
      });
    });

    group('withOrder (the board re-points it at the clicked column)', () {
      test('keeps the selection made in the other column', () {
        final WorkingCopySelectionState selection =
            const WorkingCopySelectionState(
              allPaths: <String>['a.dart', 'b.dart'],
            ).selectSinglePath('a.dart').withOrder(<String>[
              'x.dart',
              'y.dart',
            ]);

        expect(
          selection.selected,
          <String>{'a.dart'},
          reason:
              'withOrder is not syncWithPaths -- pruning here would clear the '
              'other column every time the user clicked in this one',
        );
        expect(selection.allPaths, <String>['x.dart', 'y.dart']);
        expect(selection.lastClickedPath, 'a.dart');
      });

      test('an anchor left in the other column degrades Shift+click to a '
          'plain click rather than to nothing', () {
        final WorkingCopySelectionState selection =
            const WorkingCopySelectionState(
              allPaths: <String>['a.dart', 'b.dart'],
            ).selectSinglePath('a.dart').withOrder(<String>[
              'x.dart',
              'y.dart',
            ]);

        expect(selection.shiftSelectPath('y.dart').selected, <String>{
          'y.dart',
        });
        expect(
          selection.shiftControlSelectPath('y.dart').selected,
          <String>{'a.dart', 'y.dart'},
          reason: 'Shift+Ctrl/Cmd still adds, it just has no range to add',
        );
      });
    });
  });
}
