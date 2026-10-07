// Core records every git invocation twice: once at spawn with
// `running: true`, once with its outcome, under the same id. ~~Until the log
// drawer has a way to draw a row whose outcome is not known yet, the running
// half is dropped -- shown as-is it would read as INFO with a check mark, a
// still-hanging command reported as a success.~~ The drawer draws it as
// RUNNING now, so the running half is kept and the outcome replaces it in
// place: a slow read leaves a row from the moment it starts.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

GbmEvent _record({
  required int id,
  required bool running,
  String commandLine = 'git status',
  bool timedOut = false,
}) => GbmEvent(
  GbmEventType.operationLogRecord,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'id': id,
      'running': running,
      'whenEpochMs': 1,
      'repoDir': '/test/repo',
      'argv': <String>['git', 'status'],
      'commandLine': commandLine,
      'exitCode': 0,
      'durationMs': running ? 0 : 5,
      'stderrText': '',
      'cancelled': false,
      'timedOut': timedOut,
      'benignExit': false,
      'timeoutMs': 120000,
      'idleTimeoutMs': 0,
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

  List<OperationRecord> rows() =>
      c.state.operationLog.whereType<OperationRecord>().toList(growable: false);

  test('a running record is a row from the moment it starts', () {
    c.debugHandleEvent(_record(id: 7, running: true));

    expect(rows(), hasLength(1));
    expect(rows().single.running, isTrue);
  });

  test('the outcome replaces its running row where it stands', () {
    c.debugHandleEvent(_record(id: 7, running: true, commandLine: 'git diff'));
    c.debugHandleEvent(_record(id: 8, running: false));
    c.debugHandleEvent(
      _record(id: 7, running: false, commandLine: 'git diff', timedOut: true),
    );

    expect(rows().map((OperationRecord r) => r.id), <int>[7, 8]);
    expect(rows().first.running, isFalse);
    expect(rows().first.timedOut, isTrue);
  });

  // A replacement does not change the log's length, so length is not what
  // tells the status bar something new arrived: 執行中 → TIMEOUT with the
  // drawer shut would otherwise never light the badge.
  test('the revision moves on an append and on a replacement', () {
    final int before = c.state.operationLogRevision;
    c.debugHandleEvent(_record(id: 7, running: true));
    final int afterAppend = c.state.operationLogRevision;
    c.debugHandleEvent(_record(id: 7, running: false));

    expect(afterAppend, greaterThan(before));
    expect(c.state.operationLogRevision, greaterThan(afterAppend));
  });
}
