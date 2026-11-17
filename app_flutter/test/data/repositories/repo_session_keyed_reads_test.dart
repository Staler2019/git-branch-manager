// The reads a surface waits on answer under the request's key, on success and
// on failure (read-failure-states-spec.html). Controller tier: a real
// RepoSessionController over ReadBindings, replies as wire bytes, so the
// request-time reset, the key check, the failure branch and the export-0
// branch are the production code itself.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/keyed_read_reply.dart';
import 'package:gbm_flutter/data/models/blame_result.dart';
import 'package:gbm_flutter/data/models/file_history_entry.dart';
import 'package:gbm_flutter/data/models/line_history_chunk.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/models/read_keys.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';
import '../../support/read_bindings.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

Map<String, dynamic> _blameLine(String content) => <String, dynamic>{
  'commitOid': 'a1b2c3',
  'authorName': 'Ada',
  'authorEmail': 'ada@example.invalid',
  'authorTime': 1,
  'summary': 'First line',
  'finalLine': 1,
  'originalLine': 1,
  'content': content,
  'boundary': false,
};

GbmEvent _blameOk(String path, {String revision = '', String line = 'x'}) =>
    readyEvent(GbmEventType.blameReady, <String, dynamic>{
      'path': path,
      'revision': revision,
      'startLine': 0,
      'endLine': 0,
      'result': <String, dynamic>{
        'lines': <dynamic>[_blameLine(line)],
        'truncated': false,
      },
      'error': null,
    });

GbmEvent _blameFailed(String path, String message) =>
    readyEvent(GbmEventType.blameReady, <String, dynamic>{
      'path': path,
      'revision': '',
      'startLine': 0,
      'endLine': 0,
      'result': null,
      'error': gitErrorJson(message),
    });

Map<String, dynamic> _historyEntry(String subject) => <String, dynamic>{
  'oid': 'a1b2c3',
  'author': <String, dynamic>{
    'name': 'Ada',
    'email': 'ada@example.invalid',
    'when': 1,
    'tzOffsetMinutes': 0,
  },
  'subject': subject,
  'status': 'M',
  'renamedFrom': '',
  'path': '',
};

GbmEvent _historyOk(String path, {String startRevision = '', String s = 'x'}) =>
    readyEvent(GbmEventType.fileHistoryReady, <String, dynamic>{
      'path': path,
      'startRevision': startRevision,
      'entries': <dynamic>[_historyEntry(s)],
      'error': null,
    });

GbmEvent _historyFailed(String path, String message) =>
    readyEvent(GbmEventType.fileHistoryReady, <String, dynamic>{
      'path': path,
      'startRevision': '',
      'entries': null,
      'error': gitErrorJson(message),
    });

Map<String, dynamic> _chunk(String subject) => <String, dynamic>{
  'oid': 'a1b2c3',
  'author': <String, dynamic>{
    'name': 'Ada',
    'email': 'ada@example.invalid',
    'when': 1,
    'tzOffsetMinutes': 0,
  },
  'subject': subject,
  'diffText': '@@ -1 +1 @@',
};

GbmEvent _linesOk(String path, int start, int end, {String s = 'x'}) =>
    readyEvent(GbmEventType.lineHistoryReady, <String, dynamic>{
      'path': path,
      'startLine': start,
      'endLine': end,
      'startRevision': '',
      'entries': <dynamic>[_chunk(s)],
      'error': null,
    });

GbmEvent _linesFailed(String path, int start, int end, String message) =>
    readyEvent(GbmEventType.lineHistoryReady, <String, dynamic>{
      'path': path,
      'startLine': start,
      'endLine': end,
      'startRevision': '',
      'entries': null,
      'error': gitErrorJson(message),
    });

int _errorLines(RepoSessionController c) => c.state.operationLog
    .where((GbmLogEntry e) => e.level == OperationLogLevel.error)
    .length;

void main() {
  late ReadBindings bindings;
  late RepoSessionController c;

  setUp(() {
    bindings = ReadBindings();
    c = RepoSessionController(bindings, _identity, _NoopRecents());
    addTearDown(c.dispose);
  });

  group('blame', () {
    KeyedReadReply<BlameKey, BlameResult>? reply() => c.state.lastBlame;

    // (e) The previous subject's content is gone the moment the next one is
    // requested, before any reply (ruling 4).
    test('a request resets the reply to pending for its own key', () {
      c.requestBlame('a.txt');
      c.debugHandleEvent(_blameOk('a.txt'));
      expect(reply()?.value, isNotNull);

      c.requestBlame('b.txt');

      expect(reply()?.key, const BlameKey(path: 'b.txt'));
      expect(reply()?.value, isNull);
      expect(reply()?.error, isNull);
      expect(
        bindings.blameRequests.where((r) => r['path'] == 'b.txt').length,
        1,
      );
    });

    test('a reply for the current key is kept', () {
      c.requestBlame('a.txt', revision: 'HEAD~1');
      c.debugHandleEvent(_blameOk('a.txt', revision: 'HEAD~1', line: 'one'));
      expect(reply()?.value?.lines.single.content, 'one');
    });

    // (b)
    test('a reply for an older key is dropped', () {
      c.requestBlame('a.txt');
      c.requestBlame('b.txt');
      c.debugHandleEvent(_blameOk('a.txt'));

      expect(reply()?.key, const BlameKey(path: 'b.txt'));
      expect(reply()?.value, isNull);
    });

    // (a)
    test('a failure reply clears the value and carries the error', () {
      c.requestBlame('a.txt');
      c.debugHandleEvent(_blameOk('a.txt'));
      c.requestBlame('a.txt');
      c.debugHandleEvent(_blameFailed('a.txt', 'fatal: no such path'));

      expect(reply()?.value, isNull);
      expect(reply()?.error?.message, 'fatal: no such path');
    });

    // (f) Today's log line, without the session-wide banner.
    test('a failure reply logs one error line and leaves lastError alone', () {
      c.requestBlame('a.txt');
      final int before = _errorLines(c);
      c.debugHandleEvent(_blameFailed('a.txt', 'fatal: no such path'));

      expect(_errorLines(c), before + 1);
      expect(c.state.operationLog.last.message, contains('no such path'));
      expect(c.state.lastError, isNull);
    });

    // (c) + (h) The export queued nothing: no reply will come, so the
    // controller fails the read itself. The native error channel has already
    // logged the throw, so Dart adds no second line.
    test('an export that queued nothing fails the read without a log line', () {
      bindings.answer = 0;
      final int before = _errorLines(c);

      c.requestBlame('a.txt');

      expect(bindings.blameRequests, hasLength(1));
      expect(reply()?.key, const BlameKey(path: 'a.txt'));
      expect(reply()?.error?.message, 'Native error in gbm_request_blame');
      expect(_errorLines(c), before);
      expect(c.state.lastError, isNull);
    });
  });

  group('line history', () {
    KeyedReadReply<LineHistoryKey, List<LineHistoryChunk>>? reply() =>
        c.state.lastLineHistory;

    // (e)
    test('a request resets the reply to pending for its own key', () {
      c.requestLineHistory('a.txt', 1, 2);
      c.debugHandleEvent(_linesOk('a.txt', 1, 2));
      expect(reply()?.value, isNotNull);

      c.requestLineHistory('a.txt', 1, 12);

      expect(
        reply()?.key,
        const LineHistoryKey(path: 'a.txt', startLine: 1, endLine: 12),
      );
      expect(reply()?.value, isNull);
      expect(reply()?.error, isNull);
      expect(
        bindings.lineHistoryRequests.where((r) => r['endLine'] == 12).length,
        1,
      );
    });

    test('a reply for the current key is kept', () {
      c.requestLineHistory('a.txt', 3, 4);
      c.debugHandleEvent(_linesOk('a.txt', 3, 4, s: 'one'));
      expect(reply()?.value?.single.subject, 'one');
    });

    // (b) Same path, older range: the range is part of the key.
    test('a reply for an older range is dropped', () {
      c.requestLineHistory('a.txt', 1, 2);
      c.requestLineHistory('a.txt', 1, 12);
      c.debugHandleEvent(_linesOk('a.txt', 1, 2));

      expect(reply()?.key.endLine, 12);
      expect(reply()?.value, isNull);
    });

    // (a)
    test('a failure reply clears the value and carries the error', () {
      c.requestLineHistory('a.txt', 1, 2);
      c.debugHandleEvent(_linesOk('a.txt', 1, 2));
      c.requestLineHistory('a.txt', 1, 2);
      c.debugHandleEvent(
        _linesFailed('a.txt', 1, 2, 'fatal: file a.txt has only 1 lines'),
      );

      expect(reply()?.value, isNull);
      expect(reply()?.error?.message, 'fatal: file a.txt has only 1 lines');
    });

    // (f)
    test('a failure reply logs one error line and leaves lastError alone', () {
      c.requestLineHistory('a.txt', 1, 2);
      final int before = _errorLines(c);
      c.debugHandleEvent(_linesFailed('a.txt', 1, 2, 'fatal: bad range'));

      expect(_errorLines(c), before + 1);
      expect(c.state.operationLog.last.message, contains('bad range'));
      expect(c.state.lastError, isNull);
    });

    // (c) + (h)
    test('an export that queued nothing fails the read without a log line', () {
      bindings.answer = 0;
      final int before = _errorLines(c);

      c.requestLineHistory('a.txt', 1, 2);

      expect(bindings.lineHistoryRequests, hasLength(1));
      expect(
        reply()?.key,
        const LineHistoryKey(path: 'a.txt', startLine: 1, endLine: 2),
      );
      expect(
        reply()?.error?.message,
        'Native error in gbm_request_line_history',
      );
      expect(_errorLines(c), before);
      expect(c.state.lastError, isNull);
    });
  });

  group('file history', () {
    KeyedReadReply<FileHistoryKey, List<FileHistoryEntry>>? reply() =>
        c.state.lastFileHistory;

    // (e)
    test('a request resets the reply to pending for its own key', () {
      c.requestFileHistory('a.txt');
      c.debugHandleEvent(_historyOk('a.txt'));
      expect(reply()?.value, isNotNull);

      c.requestFileHistory('b.txt');

      expect(reply()?.key, const FileHistoryKey(path: 'b.txt'));
      expect(reply()?.value, isNull);
      expect(reply()?.error, isNull);
      expect(
        bindings.fileHistoryRequests.where((r) => r['path'] == 'b.txt').length,
        1,
      );
    });

    test('a reply for the current key is kept', () {
      c.requestFileHistory('a.txt', startRevision: 'HEAD~1');
      c.debugHandleEvent(
        _historyOk('a.txt', startRevision: 'HEAD~1', s: 'one'),
      );
      expect(reply()?.value?.single.subject, 'one');
    });

    // (b)
    test('a reply for an older key is dropped', () {
      c.requestFileHistory('a.txt');
      c.requestFileHistory('b.txt');
      c.debugHandleEvent(_historyOk('a.txt'));

      expect(reply()?.key, const FileHistoryKey(path: 'b.txt'));
      expect(reply()?.value, isNull);
    });

    // (a)
    test('a failure reply clears the value and carries the error', () {
      c.requestFileHistory('a.txt');
      c.debugHandleEvent(_historyOk('a.txt'));
      c.requestFileHistory('a.txt');
      c.debugHandleEvent(_historyFailed('a.txt', 'fatal: bad revision'));

      expect(reply()?.value, isNull);
      expect(reply()?.error?.message, 'fatal: bad revision');
    });

    // (f)
    test('a failure reply logs one error line and leaves lastError alone', () {
      c.requestFileHistory('a.txt');
      final int before = _errorLines(c);
      c.debugHandleEvent(_historyFailed('a.txt', 'fatal: bad revision'));

      expect(_errorLines(c), before + 1);
      expect(c.state.operationLog.last.message, contains('bad revision'));
      expect(c.state.lastError, isNull);
    });

    // (c) + (h)
    test('an export that queued nothing fails the read without a log line', () {
      bindings.answer = 0;
      final int before = _errorLines(c);

      c.requestFileHistory('a.txt');

      expect(bindings.fileHistoryRequests, hasLength(1));
      expect(reply()?.key, const FileHistoryKey(path: 'a.txt'));
      expect(
        reply()?.error?.message,
        'Native error in gbm_request_file_history',
      );
      expect(_errorLines(c), before);
      expect(c.state.lastError, isNull);
    });
  });
}
