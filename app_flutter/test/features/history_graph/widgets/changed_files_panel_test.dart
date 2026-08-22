import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';
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

  testWidgets('a file row is as tall as a commit row, not a dense ListTile', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('lib/a.dart')],
        selectedPath: null,
        onFileTap: null,
      ),
    );

    // This list used to be `ListTile(dense: true)`, which keeps Material's
    // own list metrics (~40px dense, 48 otherwise) and so read visibly
    // looser than the 26px commit rows immediately above it. Pinned here
    // because the swap to `GbmRow` broke no existing assertion at all --
    // only the parity test noticed, and only because it happened to name
    // `ListTile` as its finder.
    expect(tester.getSize(find.byType(GbmRow).first).height, kCommitRowHeight);
    expect(kCommitRowHeight, GbmSpacing.rowHeightCompact);
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

  testWidgets('Compare with working copy and Open terminal here render in '
      'spec 05-K order', (tester) async {
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('a.dart')],
        selectedPath: null,
        onFileTap: (_) {},
        onCompareWithWorkingCopy: (_) {},
        onFileHistory: (_) {},
        onBlame: (_) {},
        onOpenTerminal: (_) {},
      ),
    );

    await tester.tap(find.text('a.dart'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();

    // Spec 05-K's top-level order, minus the two (ii) items that need a
    // blob-read capi entry point (Open file at this revision / Save this
    // revision as…) and the "More actions" trigger, which only appears when
    // onRestoreToThisState is wired.
    final List<String> rendered = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(Overlay),
            matching: find.byType(Text),
          ),
        )
        .map((Text t) => t.data)
        .whereType<String>()
        // The Overlay also carries the panel itself (its header and rows);
        // the menu starts at its first item.
        .skipWhile((String s) => s != 'View diff in this commit')
        .toList();
    expect(rendered, <String>[
      'View diff in this commit',
      'Compare with working copy',
      'File history',
      'Blame at this commit',
      'Open terminal here',
      'Copy path',
    ]);
  });

  testWidgets('compare-with-working-copy callback invoked with the path', (
    tester,
  ) async {
    String? comparedPath;
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('a.dart')],
        selectedPath: null,
        onFileTap: (_) {},
        onCompareWithWorkingCopy: (path) => comparedPath = path,
      ),
    );

    await tester.tap(find.text('a.dart'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compare with working copy'));
    await tester.pumpAndSettle();

    expect(comparedPath, 'a.dart');
  });

  testWidgets('open-terminal callback invoked on context menu tap', (
    tester,
  ) async {
    String? terminalPath;
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('a.dart')],
        selectedPath: null,
        onFileTap: (_) {},
        onOpenTerminal: (path) => terminalPath = path,
      ),
    );

    await tester.tap(find.text('a.dart'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open terminal here'));
    await tester.pumpAndSettle();

    expect(terminalPath, 'a.dart');
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
    expect(find.text('Compare with working copy'), findsNothing);
    expect(find.text('Open terminal here'), findsNothing);
  });

  testWidgets('context menu offers "Open file at this revision"', (
    tester,
  ) async {
    String? opened;
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[_file('src/main.dart')],
        selectedPath: null,
        onFileTap: (_) {},
        onOpenAtRevision: (path) => opened = path,
      ),
    );

    await tester.tap(
      find.text('src/main.dart'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open file at this revision'));
    await tester.pumpAndSettle();

    expect(opened, 'src/main.dart');
  });

  testWidgets(
    'the "More actions" submenu lists all four of spec 05-K\'s second-level '
    'items',
    (tester) async {
      await pumpGbmWidget(
        tester,
        child: ChangedFilesPanelCore(
          hasSelectedCommit: true,
          files: <ChangedFile>[_file('a.dart')],
          selectedPath: null,
          onFileTap: (_) {},
          onRestoreToThisState: (_) {},
          onRestoreAndStage: (_) {},
          onSaveRevisionAs: (_) {},
          onExportAsPatch: (_) {},
        ),
      );

      await tester.tap(find.text('a.dart'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();

      expect(find.text('Restore file to this state'), findsOneWidget);
      expect(find.text('Restore and stage'), findsOneWidget);
      expect(find.text('Save this revision as…'), findsOneWidget);
      expect(find.text('Export as patch…'), findsOneWidget);
    },
  );

  for (final (String label, String field) in <(String, String)>[
    ('Restore file to this state', 'onRestoreToThisState'),
    ('Restore and stage', 'onRestoreAndStage'),
    ('Save this revision as…', 'onSaveRevisionAs'),
    ('Export as patch…', 'onExportAsPatch'),
  ]) {
    testWidgets('submenu item "$label" fires $field with the path', (
      tester,
    ) async {
      final Map<String, String> fired = <String, String>{};
      await pumpGbmWidget(
        tester,
        child: ChangedFilesPanelCore(
          hasSelectedCommit: true,
          files: <ChangedFile>[_file('src/main.dart')],
          selectedPath: null,
          onFileTap: (_) {},
          onRestoreToThisState: (p) => fired['onRestoreToThisState'] = p,
          onRestoreAndStage: (p) => fired['onRestoreAndStage'] = p,
          onSaveRevisionAs: (p) => fired['onSaveRevisionAs'] = p,
          onExportAsPatch: (p) => fired['onExportAsPatch'] = p,
        ),
      );

      await tester.tap(
        find.text('src/main.dart'),
        buttons: kSecondaryMouseButton,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      expect(fired, <String, String>{field: 'src/main.dart'});
    });
  }

  testWidgets(
    'the submenu disappears entirely when no second-level action is available',
    (tester) async {
      await pumpGbmWidget(
        tester,
        child: ChangedFilesPanelCore(
          hasSelectedCommit: true,
          files: <ChangedFile>[_file('a.dart')],
          selectedPath: null,
          onFileTap: (_) {},
        ),
      );

      await tester.tap(find.text('a.dart'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('More actions'), findsNothing);
      expect(find.text('Open file at this revision'), findsNothing);
    },
  );

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
