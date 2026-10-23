import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/target_directory_probe.dart';

void main() {
  late Directory base;

  setUp(() => base = Directory.systemTemp.createTempSync('gbm_probe_'));
  tearDown(() => base.deleteSync(recursive: true));

  test('an empty path is missing', () {
    expect(probeTargetDirectory(''), TargetDirectoryState.missing);
  });

  test('a path that does not exist is missing', () {
    expect(
      probeTargetDirectory('${base.path}/nope'),
      TargetDirectoryState.missing,
    );
  });

  test('an existing directory with nothing in it is empty', () {
    expect(probeTargetDirectory(base.path), TargetDirectoryState.empty);
  });

  test('a directory holding files is nonEmpty', () {
    File('${base.path}/README.md').writeAsStringSync('x');
    expect(probeTargetDirectory(base.path), TargetDirectoryState.nonEmpty);
  });

  test('a directory with a .git directory is a gitRepository', () {
    Directory('${base.path}/.git').createSync();
    expect(probeTargetDirectory(base.path), TargetDirectoryState.gitRepository);
  });

  // A linked worktree's `.git` is a file pointing at the main repository's
  // gitdir; it is still a repository for init's purposes.
  test('a directory with a .git file is a gitRepository', () {
    File('${base.path}/.git').writeAsStringSync('gitdir: /elsewhere\n');
    expect(probeTargetDirectory(base.path), TargetDirectoryState.gitRepository);
  });
}
