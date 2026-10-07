// Core now records every git invocation twice: once at spawn with
// `running: true`, once with its outcome. Until the log drawer has a way to
// draw a row whose outcome is not known yet, the running half is dropped --
// shown as-is it would read as INFO with a check mark, a still-hanging
// command reported as a success.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

GbmEvent _record({required int id, required bool running}) => GbmEvent(
  GbmEventType.operationLogRecord,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'id': id,
      'running': running,
      'whenEpochMs': 1,
      'repoDir': '/test/repo',
      'argv': <String>['git', 'status'],
      'commandLine': 'git status',
      'exitCode': 0,
      'durationMs': running ? 0 : 5,
      'stderrText': '',
      'cancelled': false,
      'timedOut': false,
      'benignExit': false,
    }),
  ),
);

void main() {
  late FakeRepoSessionController c;

  setUp(() {
    c = FakeRepoSessionController(
      RepoIdentity.forWorkDir('/test/repo'),
      const RepoSessionState(),
    );
    addTearDown(c.dispose);
  });

  test('a running record does not reach the operation log', () {
    c.debugHandleEvent(_record(id: 7, running: true));

    expect(c.state.operationLog, isEmpty);
  });

  test('the finished record of the same invocation does', () {
    c.debugHandleEvent(_record(id: 7, running: true));
    c.debugHandleEvent(_record(id: 7, running: false));

    final List<OperationRecord> rows = c.state.operationLog
        .whereType<OperationRecord>()
        .toList(growable: false);
    expect(rows, hasLength(1));
    expect(rows.single.id, 7);
    expect(rows.single.running, isFalse);
  });
}
