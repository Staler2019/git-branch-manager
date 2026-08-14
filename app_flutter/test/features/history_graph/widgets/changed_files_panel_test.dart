import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/history_graph/widgets/changed_files_panel.dart';

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
}
