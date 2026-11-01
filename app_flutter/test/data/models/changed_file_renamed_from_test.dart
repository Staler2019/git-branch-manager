import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';

ChangedFile _file(String path, String oldPath, FileChangeKind kind) =>
    ChangedFile(
      path: path,
      oldPath: oldPath,
      kind: kind,
      oldMode: '100644',
      newMode: '100644',
      oldBlob: 'aaa',
      newBlob: 'bbb',
      similarity: 0,
      addedLines: 0,
      removedLines: 0,
    );

void main() {
  test('a renamed file reports the name it had before the commit', () {
    expect(
      _file('b.dart', 'a.dart', FileChangeKind.renamed).renamedFrom,
      'a.dart',
    );
  });

  test('a copy reports nothing: its source still exists', () {
    expect(_file('b.dart', 'a.dart', FileChangeKind.copied).renamedFrom, '');
  });

  test('a modified file reports nothing, whatever oldPath holds', () {
    expect(_file('a.dart', 'a.dart', FileChangeKind.modified).renamedFrom, '');
    expect(_file('a.dart', '', FileChangeKind.modified).renamedFrom, '');
  });
}
