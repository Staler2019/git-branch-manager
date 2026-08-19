import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/file_list_view_mode_repository.dart';
import 'package:gbm_flutter/features/history_graph/widgets/changed_files_panel.dart';
import 'package:gbm_flutter/widgets/file_list_mode_toggle_button.dart';
import 'package:gbm_flutter/widgets/file_tree_folder_row.dart';

import '../../../support/pump_app.dart';

ChangedFile _file(String path) => ChangedFile(
  path: path,
  oldPath: path,
  kind: FileChangeKind.modified,
  oldMode: '100644',
  newMode: '100644',
  oldBlob: 'aaa',
  newBlob: 'bbb',
  similarity: 0,
);

void main() {
  testWidgets('shows "No files changed" when no commit is selected', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: const ChangedFilesPanelCore(
        hasSelectedCommit: false,
        files: <ChangedFile>[],
        selectedPath: null,
        onFileTap: null,
      ),
    );

    expect(find.text('No files changed'), findsOneWidget);
  });

  testWidgets('shows "No files changed" when commit has an empty file list', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: const ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[],
        selectedPath: null,
        onFileTap: null,
      ),
    );

    expect(find.text('No files changed'), findsOneWidget);
  });

  testWidgets('lists every changed file path', (tester) async {
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('a.dart'), _file('b/c.dart')],
        selectedPath: null,
        onFileTap: (_) {},
      ),
    );

    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('b/c.dart'), findsOneWidget);
  });

  testWidgets('tapping a file invokes onFileTap with its path', (tester) async {
    String? tapped;
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('a.dart')],
        selectedPath: null,
        onFileTap: (path) => tapped = path,
      ),
    );

    await tester.tap(find.text('a.dart'));
    await tester.pump();

    expect(tapped, 'a.dart');
  });

  testWidgets('right-click opens context menu with file actions', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('a.dart')],
        selectedPath: null,
        onFileTap: (_) {},
        onFileHistory: (_) {},
        onBlame: (_) {},
      ),
    );

    await tester.tap(find.text('a.dart'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('View diff in this commit'), findsOneWidget);
    expect(find.text('File history'), findsOneWidget);
    expect(find.text('Blame at this commit'), findsOneWidget);
    expect(find.text('Copy path'), findsOneWidget);
  });

  testWidgets('file history callback invoked on context menu tap', (
    tester,
  ) async {
    String? historyPath;
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('a.dart')],
        selectedPath: null,
        onFileTap: (_) {},
        onFileHistory: (path) => historyPath = path,
      ),
    );

    await tester.tap(find.text('a.dart'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('File history'));
    await tester.pumpAndSettle();

    expect(historyPath, 'a.dart');
  });

  testWidgets('blame callback invoked on context menu tap', (tester) async {
    String? blamePath;
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('src/main.dart')],
        selectedPath: null,
        onFileTap: (_) {},
        onBlame: (path) => blamePath = path,
      ),
    );

    await tester.tap(
      find.text('src/main.dart'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Blame at this commit'));
    await tester.pumpAndSettle();

    expect(blamePath, 'src/main.dart');
  });

  testWidgets('context menu omits unavailable actions', (tester) async {
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('a.dart')],
        selectedPath: null,
        onFileTap: (_) {},
        // No onFileHistory or onBlame
      ),
    );

    await tester.tap(find.text('a.dart'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    expect(find.text('File history'), findsNothing);
    expect(find.text('Blame at this commit'), findsNothing);
  });

  testWidgets('shows the shared list/tree mode toggle button', (tester) async {
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('a.dart')],
        selectedPath: null,
        onFileTap: (_) {},
      ),
    );

    expect(find.byType(FileListModeToggleButton), findsOneWidget);
  });

  testWidgets(
    'renders folders via FileTreeFolderRow when viewMode is tree -- spec '
    'page 03 item 10: the same List/Tree preference applies to History\'s '
    'Changed files panel',
    (tester) async {
      await pumpGbmWidget(
        tester,
        child: ChangedFilesPanelCore(
          hasSelectedCommit: true,
          files: <ChangedFile>[
            _file('a.dart'),
            _file('b/c.dart'),
            _file('b/d.dart'),
          ],
          selectedPath: null,
          onFileTap: (_) {},
          viewMode: FileListViewMode.tree,
        ),
      );

      // 'b' has two children (c.dart, d.dart) so it does not single-child
      // collapse -- unlike a lone-file folder, which FileTree.fromPaths
      // flattens away entirely (see file_tree.dart's _collapseIfSingleChild).
      expect(find.byType(FileTreeFolderRow), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('a.dart'), findsOneWidget);
    },
  );
}
