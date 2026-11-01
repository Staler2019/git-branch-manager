import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/history_graph/widgets/changed_files_panel.dart';
import 'package:gbm_flutter/widgets/file_change_glyph.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';

import '../../../support/pump_app.dart';

ChangedFile _file(String path, FileChangeKind kind, {String oldPath = ''}) =>
    ChangedFile(
      path: path,
      oldPath: oldPath.isEmpty ? path : oldPath,
      kind: kind,
      oldMode: '100644',
      newMode: '100644',
      oldBlob: 'aaa',
      newBlob: 'bbb',
      similarity: kind == FileChangeKind.renamed ? 100 : 0,
      addedLines: 0,
      removedLines: 0,
    );

String? _glyphIn(WidgetTester tester, String name) {
  final Finder row = find.ancestor(
    of: find.text(name),
    matching: find.byType(GbmRow),
  );
  final Finder glyph = find.descendant(
    of: row,
    matching: find.byType(FileChangeGlyph),
  );
  expect(glyph, findsOneWidget, reason: name);
  final Finder icon = find.descendant(
    of: glyph,
    matching: find.byType(LucideIcon),
  );
  return icon.evaluate().isEmpty ? null : tester.widget<LucideIcon>(icon).name;
}

void main() {
  testWidgets('each changed file row draws its kind in front of the name', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: ChangedFilesPanelCore(
        hasSelectedCommit: true,
        files: <ChangedFile>[
          _file('added.dart', FileChangeKind.added),
          _file('gone.dart', FileChangeKind.deleted),
          _file('moved.dart', FileChangeKind.renamed, oldPath: 'origin.dart'),
          _file('edited.dart', FileChangeKind.modified),
        ],
        selectedPath: null,
        onFileTap: null,
      ),
    );

    expect(_glyphIn(tester, 'added.dart'), 'plus');
    expect(_glyphIn(tester, 'gone.dart'), 'minus');
    expect(_glyphIn(tester, 'moved.dart'), 'arrow-right');
    expect(_glyphIn(tester, 'edited.dart'), isNull);
  });
}
