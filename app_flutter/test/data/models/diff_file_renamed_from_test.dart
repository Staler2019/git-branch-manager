import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';

DiffFile _file(String path, String oldPath, FileChangeKind kind) => DiffFile(
  oldPath: oldPath,
  newPath: path,
  kind: kind,
  oldMode: '100644',
  newMode: '100644',
  oldBlob: 'aaa',
  newBlob: 'bbb',
  binary: false,
  similarity: 0,
  addedLines: 0,
  removedLines: 0,
  displayPath: path,
  hunks: const <DiffHunk>[],
);

void main() {
  test('a renamed file reports the name it had before the range', () {
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
  });
}
