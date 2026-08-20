// Verifies FileAtRevisionExport parses exactly the JSON shape
// src/capi/gbm_capi.h's GBM_EVENT_FILE_AT_REVISION_EXPORTED doc comment
// describes, mirroring repo_session_state_compare_test.dart's convention.
// No FFI involved.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

void main() {
  group('FileAtRevisionExport', () {
    test('fromJson decodes a successful export with no error object', () {
      final Map<String, dynamic> json = jsonDecode(
        '{"revision":"HEAD~1","path":"lib/main.dart",'
        '"destPath":"/tmp/main-abc1234.dart","succeeded":true}',
      );

      final FileAtRevisionExport export = FileAtRevisionExport.fromJson(json);

      expect(export.revision, 'HEAD~1');
      expect(export.path, 'lib/main.dart');
      expect(export.destPath, '/tmp/main-abc1234.dart');
      expect(export.succeeded, isTrue);
      expect(export.error, isNull);
    });

    test('fromJson decodes a failure and keeps git stderr in the error', () {
      final Map<String, dynamic> json = jsonDecode(
        '{"revision":"HEAD","path":"gone.txt","destPath":"/tmp/gone.txt",'
        '"succeeded":false,"error":{"code":1,"codeName":"NotFound",'
        '"message":"\'gone.txt\' is not a file at HEAD",'
        '"detail":"fatal: path \'gone.txt\' does not exist in \'HEAD\'",'
        '"argv":["git","cat-file","-s","HEAD:gone.txt"],"exitCode":128}}',
      );

      final FileAtRevisionExport export = FileAtRevisionExport.fromJson(json);

      expect(export.succeeded, isFalse);
      expect(export.error, isNotNull);
      expect(export.error!.codeName, 'NotFound');
      expect(export.error!.detail, contains('does not exist'));
      expect(export.error!.argv, contains('cat-file'));
    });

    test('copyWith carries the export through unrelated state updates', () {
      const FileAtRevisionExport export = FileAtRevisionExport(
        revision: 'abc',
        path: 'a.txt',
        destPath: '/tmp/a.txt',
        succeeded: true,
      );
      const RepoSessionState base = RepoSessionState();

      final RepoSessionState withExport = base.copyWith(
        lastFileAtRevisionExport: export,
      );
      final RepoSessionState later = withExport.copyWith(isRefreshing: true);

      expect(base.lastFileAtRevisionExport, isNull);
      expect(withExport.lastFileAtRevisionExport, same(export));
      expect(later.lastFileAtRevisionExport, same(export));
    });
  });
}
