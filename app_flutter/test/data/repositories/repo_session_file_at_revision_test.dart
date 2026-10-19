// Verifies FileAtRevisionExport parses exactly the JSON shape
// src/capi/gbm_capi.h's GBM_EVENT_FILE_AT_REVISION_EXPORTED doc comment
// describes, mirroring repo_session_state_compare_test.dart's convention.
// No FFI involved.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

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

  // The capi answers an export with an event, not a return value; an action
  // that has to log the outcome needs it as a Future, matched by destPath.
  group('exportFileAtRevisionAwaiting', () {
    test('completes with the reply for its own destination only', () async {
      final _SilentExport controller = _SilentExport();
      addTearDown(controller.dispose);
      FileAtRevisionExport? reply;
      unawaited(
        controller
            .exportFileAtRevisionAwaiting(
              revision: 'abc',
              path: 'a.txt',
              destPath: '/tmp/mine.txt',
            )
            .then((FileAtRevisionExport e) => reply = e),
      );
      expect(controller.requested, <String>['/tmp/mine.txt']);

      controller.publish('/tmp/other.txt');
      await Future<void>.delayed(Duration.zero);
      expect(reply, isNull, reason: 'another export\'s reply');

      controller.publish('/tmp/mine.txt');
      await Future<void>.delayed(Duration.zero);
      expect(reply?.destPath, '/tmp/mine.txt');
    });

    test('a reply that arrives during the request is not missed', () async {
      final FakeRepoSessionController controller = FakeRepoSessionController(
        RepoIdentity.forWorkDir('/test/repo'),
        const RepoSessionState(isOpen: true),
      );
      addTearDown(controller.dispose);
      final FileAtRevisionExport reply = await controller
          .exportFileAtRevisionAwaiting(
            revision: 'abc',
            path: 'a.txt',
            destPath: '/tmp/sync.txt',
          );
      expect(reply.succeeded, isTrue);
    });
  });
}

/// Requests nothing; the test publishes replies by hand.
class _SilentExport extends FakeRepoSessionController {
  _SilentExport()
    : super(
        RepoIdentity.forWorkDir('/test/repo'),
        const RepoSessionState(isOpen: true),
      );

  final List<String> requested = <String>[];

  @override
  void exportFileAtRevision({
    required String revision,
    required String path,
    required String destPath,
  }) => requested.add(destPath);

  void publish(String destPath) {
    state = state.copyWith(
      lastFileAtRevisionExport: FileAtRevisionExport(
        revision: 'abc',
        path: 'a.txt',
        destPath: destPath,
        succeeded: true,
      ),
    );
  }
}
