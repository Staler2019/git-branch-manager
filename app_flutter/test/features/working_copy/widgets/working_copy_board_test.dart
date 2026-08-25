import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/file_list_view_mode_repository.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:gbm_flutter/widgets/file_tree_folder_row.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';

import '../../../support/pump_app.dart';

void main() {
  group('WorkingCopyBoard', () {
    final unstagedEntries = <WorkingCopyEntry>[
      const WorkingCopyEntry(
        path: 'lib/main.dart',
        oldPath: '',
        untracked: false,
        staged: false,
        indexStatus: FileChangeKind.modified,
        hasUnstagedChange: true,
        worktreeStatus: FileChangeKind.modified,
        unstagedAdded: 0,
        unstagedRemoved: 0,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      ),
      const WorkingCopyEntry(
        path: 'lib/utils.dart',
        oldPath: '',
        untracked: false,
        staged: false,
        indexStatus: FileChangeKind.added,
        hasUnstagedChange: true,
        worktreeStatus: FileChangeKind.added,
        unstagedAdded: 0,
        unstagedRemoved: 0,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      ),
    ];

    final stagedEntries = <WorkingCopyEntry>[
      const WorkingCopyEntry(
        path: 'pubspec.yaml',
        oldPath: '',
        untracked: false,
        staged: true,
        indexStatus: FileChangeKind.modified,
        hasUnstagedChange: false,
        worktreeStatus: FileChangeKind.modified,
        unstagedAdded: 0,
        unstagedRemoved: 0,
        stagedAdded: 0,
        stagedRemoved: 0,
        conflict: ConflictKind.none,
        ancestorBlob: '',
        oursBlob: '',
        theirsBlob: '',
        similarity: 0,
        isSubmodule: false,
        isConflicted: false,
      ),
    ];

    testWidgets('renders both columns with headers and entries', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      expect(find.text('UNSTAGED'), findsOneWidget);
      expect(find.text('STAGED'), findsOneWidget);
      expect(find.text('lib/main.dart'), findsOneWidget);
      expect(find.text('lib/utils.dart'), findsOneWidget);
      expect(find.text('pubspec.yaml'), findsOneWidget);
    });

    testWidgets('shows file count in headers', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      expect(find.text('2'), findsWidgets); // 2 unstaged + 1 staged
      expect(find.text('1'), findsWidgets);
    });

    testWidgets('empty column shows placeholder', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: const [],
            stagedEntries: stagedEntries,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      expect(find.text('No unstaged changes'), findsOneWidget);
      expect(find.text('pubspec.yaml'), findsOneWidget);
    });

    testWidgets(
      'no checkbox anywhere -- not on a row, a column header, or a folder row',
      (tester) async {
        for (final FileListViewMode mode in FileListViewMode.values) {
          await pumpGbmWidget(
            tester,
            child: SizedBox(
              width: 800,
              height: 600,
              child: WorkingCopyBoard(
                unstagedEntries: unstagedEntries,
                stagedEntries: stagedEntries,
                mode: mode,
                onStageRequested: (_) {},
                onUnstageRequested: (_) {},
              ),
            ),
          );

          expect(
            find.byType(Checkbox),
            findsNothing,
            reason:
                'files change column by dragging; a checkbox reintroduces a '
                'second way to say the same thing (mode: $mode)',
          );
          expect(find.byIcon(Icons.drag_handle), findsNothing);
        }
      },
    );

    testWidgets('rows are GbmRow, so hover and selected come from the design '
        'system rather than a hand-rolled InkWell', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      expect(find.byType(GbmRow), findsNWidgets(3));

      final Finder mainRow = find.ancestor(
        of: find.text('lib/main.dart'),
        matching: find.byType(GbmRow),
      );
      expect(tester.widget<GbmRow>(mainRow).selected, isFalse);

      await tester.tap(find.text('lib/main.dart'));
      await tester.pump();

      expect(
        tester.widget<GbmRow>(mainRow).selected,
        isTrue,
        reason:
            'a plain click selects the row it hit -- with the checkbox gone '
            'the selected background is the only thing that says so',
      );
    });

    testWidgets('tree mode makes the folder row itself draggable, carrying '
        'every file underneath it', (tester) async {
      await pumpGbmWidget(
        tester,
        child: SizedBox(
          width: 800,
          height: 600,
          child: WorkingCopyBoard(
            unstagedEntries: unstagedEntries,
            stagedEntries: stagedEntries,
            mode: FileListViewMode.tree,
            onStageRequested: (_) {},
            onUnstageRequested: (_) {},
          ),
        ),
      );

      // `byType` cannot name this one: the payload class is private to
      // working_copy_board.dart, and Draggable<_DraggedFiles> is a different
      // runtimeType from Draggable<Object>.
      final Finder folderRow = find.ancestor(
        of: find.byType(FileTreeFolderRow),
        matching: find.byWidgetPredicate((Widget w) => w is Draggable),
      );
      expect(
        folderRow,
        findsOneWidget,
        reason:
            'dragging a whole folder is what replaced the tri-state folder '
            'checkbox; without it the folder scope has no entry point at all',
      );
    });
  });
}
