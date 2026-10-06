// Both of the reducer's UTF-8 decoders are strict: `decodeEventPayload` for an
// event's own payload, `readLastResultJson` for the staging buffer a handler
// reads after a no-payload event such as WORKTREES_UPDATED. A
// FormatException from either used to escape `_onEvent` into the stream's
// zone, which dropped that one event and left nothing anywhere -- the git
// row, the worktree list, the working copy simply never arrived. Each such
// failure must leave an error row instead, and must not stop the next event.
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

/// Big5 「一」: a lead byte 0xA4 followed by 0x40, which is not UTF-8.
final Uint8List _notUtf8 = Uint8List.fromList(<int>[
  0x5B,
  0x22,
  0xA4,
  0x40,
  0x22,
  0x5D,
]);

/// Serves [_notUtf8] from the staging buffer after a successful
/// `worktreesJson`, the way a worktree list carrying a code-page path would.
class _UndecodableWorktreesBindings extends FakeGbmBindings {
  // Armed only by worktreesJson: `_open()` reads the staging buffer too, for
  // the failed open's own error, and that read must stay empty.
  bool _armed = false;

  @override
  WorktreesJsonDart get worktreesJson => (Pointer<Void> session) {
    _armed = true;
    return 0;
  };

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _armed ? _notUtf8.length : 0;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) {
        out.asTypedList(outLen).setAll(0, _notUtf8);
      };
}

GbmEvent _gitRecord(String argv0) => GbmEvent(
  GbmEventType.operationLogRecord,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'whenEpochMs': 1,
      'repoDir': '/test/repo',
      'argv': <String>[argv0, 'status'],
      'commandLine': '$argv0 status',
      'exitCode': 0,
      'durationMs': 1,
      'stderrText': '',
      'cancelled': false,
      'timedOut': false,
      'benignExit': false,
    }),
  ),
);

List<AppLogEntry> _errorRows(RepoSessionController c) => c.state.operationLog
    .whereType<AppLogEntry>()
    .where((AppLogEntry e) => e.level == OperationLogLevel.error)
    .toList(growable: false);

void main() {
  test('an event payload that is not UTF-8 leaves an error row', () {
    final FakeRepoSessionController c = FakeRepoSessionController(
      _identity,
      const RepoSessionState(),
    );
    addTearDown(c.dispose);

    c.debugHandleEvent(GbmEvent(GbmEventType.operationLogRecord, _notUtf8));

    expect(_errorRows(c), hasLength(1));
    expect(_errorRows(c).single.message, contains('could not be decoded'));
  });

  test('a staging buffer that is not UTF-8 leaves an error row', () {
    final RepoSessionController c = RepoSessionController(
      _UndecodableWorktreesBindings(),
      _identity,
      FakeRecentsRepository(),
    );
    addTearDown(c.dispose);

    c.debugHandleEvent(const GbmEvent(GbmEventType.worktreesUpdated, null));

    expect(_errorRows(c), hasLength(1));
  });

  test('the next event is still handled', () {
    final FakeRepoSessionController c = FakeRepoSessionController(
      _identity,
      const RepoSessionState(),
    );
    addTearDown(c.dispose);

    c.debugHandleEvent(GbmEvent(GbmEventType.operationLogRecord, _notUtf8));
    c.debugHandleEvent(_gitRecord('git'));

    expect(c.state.operationLog.whereType<OperationRecord>(), hasLength(1));
  });
}
