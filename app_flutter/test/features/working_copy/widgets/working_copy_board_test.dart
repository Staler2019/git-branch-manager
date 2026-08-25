import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';

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

    testWidgets('render test with Checkbox widget', (tester) async {
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

      // Check that checkboxes are present
      expect(find.byType(Checkbox), findsWidgets);
    });

    testWidgets(
      'header checkbox shows indeterminate (not unchecked) when only some '
      'files in the column are selected -- regression test: tristate:true '
      'is useless if value collapses indeterminate into false',
      (tester) async {
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

        final headerCheckbox = find.byKey(
          const Key('wc-header-checkbox-unstaged'),
        );
        expect(
          tester.widget<Checkbox>(headerCheckbox).value,
          false,
          reason: 'nothing selected yet -> unchecked',
        );

        // Select exactly one of the two unstaged files, leaving the column
        // partially (not fully) selected.
        await tester.tap(find.text('lib/main.dart'));
        await tester.pump();

        expect(
          tester.widget<Checkbox>(headerCheckbox).value,
          null,
          reason:
              'one of two files selected must render the indeterminate dash, '
              'not silently look identical to the empty-selection state',
        );
      },
    );

    testWidgets('drag handle icon visible on file rows', (tester) async {
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

      // Drag handle icon should be present
      expect(find.byIcon(Icons.drag_handle), findsWidgets);
    });
  });
}
