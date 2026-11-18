// The reads a surface waits on answer under the request's key, on success and
// on failure (read-failure-states-spec.html). Controller tier: a real
// RepoSessionController over ReadBindings, replies as wire bytes, so the
// request-time reset, the key check, the failure branch and the export-0
// branch are the production code itself.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/keyed_read_reply.dart';
import 'package:gbm_flutter/data/models/blame_result.dart';
import 'package:gbm_flutter/data/models/file_history_entry.dart';
import 'package:gbm_flutter/data/models/line_history_chunk.dart';
import 'package:gbm_flutter/data/models/rebase_todo_entry.dart';
import 'package:gbm_flutter/data/models/reflog_entry.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
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

GbmEvent _reflogOk(String ref, {String s = 'x'}) =>
    readyEvent(GbmEventType.reflogReady, <String, dynamic>{
      'ref': ref,
      'entries': <dynamic>[
        <String, dynamic>{
          'index': 0,
          'oid': 'a1b2c3',
          'message': s,
          'who': <String, dynamic>{
            'name': 'Ada',
            'email': 'ada@example.invalid',
            'when': 1,
            'tzOffsetMinutes': 0,
          },
        },
      ],
      'error': null,
    });

GbmEvent _reflogFailed(String ref, String message) =>
    readyEvent(GbmEventType.reflogReady, <String, dynamic>{
      'ref': ref,
      'entries': null,
      'error': gitErrorJson(message),
    });

GbmEvent _planOk(String upstream, {String s = 'x'}) =>
    readyEvent(GbmEventType.rebasePlanReady, <String, dynamic>{
      'upstream': upstream,
      'entries': <dynamic>[
        <String, dynamic>{
          'action': 0,
          'oid': 'a1b2c3d4',
          'shortOid': 'a1b2c3d',
          'subject': s,
        },
      ],
      'error': null,
    });

GbmEvent _planFailed(String upstream, String message) =>
    readyEvent(GbmEventType.rebasePlanReady, <String, dynamic>{
      'upstream': upstream,
      'entries': null,
      'error': gitErrorJson(message),
    });

Map<String, dynamic> _stash(int index, String message) => <String, dynamic>{
  'index': index,
  'message': message,
  'oid': 'abc$index',
  'timestamp': 1,
};

Map<String, dynamic> _worktree(String path) => <String, dynamic>{
  'path': path,
  'headOid': 'a1b2c3d',
  'branch': 'main',
  'isMain': true,
  'isBare': false,
  'isDetached': false,
  'isLocked': false,
  'lockReason': '',
  'isPrunable': false,
  'prunableReason': '',
  'isPrimary': true,
  'pendingChanges': 0,
  'pendingCountState': 'unmeasured',
  'createdAtUnix': 0,
};

GbmEvent _updated(int type) => GbmEvent(type, Uint8List(0));

GbmEvent _refreshFailed(int type, String message) =>
    readyEvent(type, <String, dynamic>{'error': gitErrorJson(message)});

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

  group('rebase plan', () {
    KeyedReadReply<RebasePlanKey, List<RebaseTodoEntry>>? reply() =>
        c.state.lastRebasePlan;

    // (e)
    test('a request resets the reply to pending for its own key', () {
      c.requestRebasePlan('main');
      c.debugHandleEvent(_planOk('main'));
      expect(reply()?.value, isNotNull);

      c.requestRebasePlan('develop');

      expect(reply()?.key, const RebasePlanKey('develop'));
      expect(reply()?.value, isNull);
      expect(reply()?.error, isNull);
      expect(
        bindings.rebasePlanRequests.where((r) => r == 'develop').length,
        1,
      );
    });

    test('a reply for the current key is kept', () {
      c.requestRebasePlan('main');
      c.debugHandleEvent(_planOk('main', s: 'one'));
      expect(reply()?.value?.single.subject, 'one');
    });

    // (b) A plan for main is never kept while the panel waits on develop:
    // Start would replay main's commits onto develop.
    test('a reply for an older upstream is dropped', () {
      c.requestRebasePlan('main');
      c.requestRebasePlan('develop');
      c.debugHandleEvent(_planOk('main'));

      expect(reply()?.key, const RebasePlanKey('develop'));
      expect(reply()?.value, isNull);
    });

    // (a)
    test('a failure reply clears the value and carries the error', () {
      c.requestRebasePlan('main');
      c.debugHandleEvent(_planOk('main'));
      c.requestRebasePlan('main');
      c.debugHandleEvent(_planFailed('main', 'fatal: invalid upstream'));

      expect(reply()?.value, isNull);
      expect(reply()?.error?.message, 'fatal: invalid upstream');
    });

    // (f)
    test('a failure reply logs one error line and leaves lastError alone', () {
      c.requestRebasePlan('nope');
      final int before = _errorLines(c);
      c.debugHandleEvent(_planFailed('nope', "fatal: invalid upstream 'nope'"));

      expect(_errorLines(c), before + 1);
      expect(c.state.operationLog.last.message, contains('invalid upstream'));
      expect(c.state.lastError, isNull);
    });

    // (c) + (h)
    test('an export that queued nothing fails the read without a log line', () {
      bindings.answer = 0;
      final int before = _errorLines(c);

      c.requestRebasePlan('main');

      expect(bindings.rebasePlanRequests, <String>['main']);
      expect(reply()?.key, const RebasePlanKey('main'));
      expect(
        reply()?.error?.message,
        'Native error in gbm_request_rebase_plan',
      );
      expect(_errorLines(c), before);
      expect(c.state.lastError, isNull);
    });
  });

  group('reflog', () {
    KeyedReadReply<ReflogKey, List<ReflogEntry>>? reply() => c.state.lastReflog;

    // (e)
    test('a request resets the reply to pending for its own key', () {
      c.requestReflog();
      c.debugHandleEvent(_reflogOk(''));
      expect(reply()?.value, isNotNull);

      c.requestReflog(ref: 'main');

      expect(reply()?.key, const ReflogKey('main'));
      expect(reply()?.value, isNull);
      expect(reply()?.error, isNull);
      expect(bindings.reflogRequests.where((r) => r == 'main').length, 1);
    });

    // The key is the ref as sent: '' is not 'HEAD', though git reads both
    // the same.
    test('a reply for the current key is kept, under the ref as sent', () {
      c.requestReflog();
      c.debugHandleEvent(_reflogOk('', s: 'one'));
      expect(reply()?.value?.single.message, 'one');
    });

    // (b)
    test('a reply for an older ref is dropped', () {
      c.requestReflog();
      c.requestReflog(ref: 'main');
      c.debugHandleEvent(_reflogOk(''));

      expect(reply()?.key, const ReflogKey('main'));
      expect(reply()?.value, isNull);
    });

    // (a)
    test('a failure reply clears the value and carries the error', () {
      c.requestReflog(ref: 'main');
      c.debugHandleEvent(_reflogOk('main'));
      c.requestReflog(ref: 'main');
      c.debugHandleEvent(_reflogFailed('main', 'fatal: bad ref'));

      expect(reply()?.value, isNull);
      expect(reply()?.error?.message, 'fatal: bad ref');
    });

    // (f)
    test('a failure reply logs one error line and leaves lastError alone', () {
      c.requestReflog(ref: 'nope');
      final int before = _errorLines(c);
      c.debugHandleEvent(_reflogFailed('nope', 'fatal: bad ref nope'));

      expect(_errorLines(c), before + 1);
      expect(c.state.operationLog.last.message, contains('bad ref nope'));
      expect(c.state.lastError, isNull);
    });

    // (c) + (h)
    test('an export that queued nothing fails the read without a log line', () {
      bindings.answer = 0;
      final int before = _errorLines(c);

      c.requestReflog(ref: 'main');

      expect(bindings.reflogRequests, <String>['main']);
      expect(reply()?.key, const ReflogKey('main'));
      expect(reply()?.error?.message, 'Native error in gbm_request_reflog');
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

  group('stash list', () {
    void seed() {
      bindings.stashesList = <Map<String, dynamic>>[_stash(0, 'wip on main')];
      c.debugHandleEvent(_updated(GbmEventType.stashesUpdated));
      expect(c.state.stashes.single.message, 'wip on main');
    }

    // (r1)
    test('a failed refresh keeps the list, re-reads nothing and logs once', () {
      seed();
      final int reads = bindings.stashesReads;
      final int before = _errorLines(c);

      c.debugHandleEvent(
        _refreshFailed(GbmEventType.stashesUpdated, 'fatal: not a git repo'),
      );

      expect(c.state.stashes.single.message, 'wip on main');
      expect(bindings.stashesReads - reads, 0);
      expect(c.state.stashesError?.message, 'fatal: not a git repo');
      expect(_errorLines(c), before + 1);
      expect(c.state.lastError, isNull);
    });

    // (r2)
    test('the next successful refresh re-reads and clears the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.stashesUpdated, 'fatal: boom'),
      );
      final int reads = bindings.stashesReads;

      c.debugHandleEvent(_updated(GbmEventType.stashesUpdated));

      expect(bindings.stashesReads - reads, 1);
      expect(c.state.stashesError, isNull);
    });

    // (r3)
    test(
      'an export that queued nothing fails the refresh without a log line',
      () {
        bindings.answer = 0;
        final int before = _errorLines(c);

        c.refreshStashes();

        expect(bindings.stashRefreshes, 1);
        expect(
          c.state.stashesError?.message,
          'Native error in gbm_stash_refresh',
        );
        expect(_errorLines(c), before);
        expect(c.state.lastError, isNull);
      },
    );

    // (r4) I2: the banner stays through a sweep until a refresh succeeds.
    test('sending a refresh does not clear the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.stashesUpdated, 'fatal: boom'),
      );

      c.refreshStashes();

      expect(bindings.stashRefreshes, 1);
      expect(c.state.stashesError?.message, 'fatal: boom');
    });
  });

  group('worktree list', () {
    void seed() {
      bindings.worktreesList = <Map<String, dynamic>>[_worktree('/src/a')];
      c.debugHandleEvent(_updated(GbmEventType.worktreesUpdated));
      expect(c.state.worktrees.single.path, '/src/a');
    }

    // (r1)
    test('a failed refresh keeps the list, re-reads nothing and logs once', () {
      seed();
      final int reads = bindings.worktreesReads;
      final int before = _errorLines(c);

      c.debugHandleEvent(
        _refreshFailed(GbmEventType.worktreesUpdated, 'fatal: not a git repo'),
      );

      expect(c.state.worktrees.single.path, '/src/a');
      expect(bindings.worktreesReads - reads, 0);
      expect(c.state.worktreesError?.message, 'fatal: not a git repo');
      expect(_errorLines(c), before + 1);
      expect(c.state.lastError, isNull);
    });

    // (r2)
    test('the next successful refresh re-reads and clears the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.worktreesUpdated, 'fatal: boom'),
      );
      final int reads = bindings.worktreesReads;

      c.debugHandleEvent(_updated(GbmEventType.worktreesUpdated));

      expect(bindings.worktreesReads - reads, 1);
      expect(c.state.worktreesError, isNull);
    });

    // (r3), once per export.
    test('a refresh export that queued nothing fails without a log line', () {
      bindings.answer = 0;
      final int before = _errorLines(c);

      c.refreshWorktrees();

      expect(bindings.worktreeRefreshes, 1);
      expect(
        c.state.worktreesError?.message,
        'Native error in gbm_worktree_refresh',
      );
      expect(_errorLines(c), before);
      expect(c.state.lastError, isNull);
    });

    test(
      'a pending-count export that queued nothing fails without a log line',
      () {
        bindings.answer = 0;
        final int before = _errorLines(c);

        c.requestWorktreePendingCounts();

        expect(bindings.worktreePendingCountRequests, 1);
        expect(
          c.state.worktreesError?.message,
          'Native error in gbm_worktree_request_pending_counts',
        );
        expect(_errorLines(c), before);
        expect(c.state.lastError, isNull);
      },
    );

    // (r4) I2: neither send clears the banner; only a success does.
    test('sending either request does not clear the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.worktreesUpdated, 'fatal: boom'),
      );

      c.refreshWorktrees();
      c.requestWorktreePendingCounts();

      expect(bindings.worktreeRefreshes, 1);
      expect(bindings.worktreePendingCountRequests, 1);
      expect(c.state.worktreesError?.message, 'fatal: boom');
    });
  });

  group('remote list', () {
    void seed() {
      bindings.remotesList = <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'origin',
          'fetchUrl': 'https://example.com/repo.git',
          'pushUrl': 'https://example.com/repo.git',
        },
      ];
      c.debugHandleEvent(_updated(GbmEventType.remotesUpdated));
      expect(c.state.remotes.single.name, 'origin');
    }

    // (r1)
    test('a failed refresh keeps the list, re-reads nothing and logs once', () {
      seed();
      final int reads = bindings.remotesReads;
      final int before = _errorLines(c);

      c.debugHandleEvent(
        _refreshFailed(GbmEventType.remotesUpdated, 'fatal: not a git repo'),
      );

      expect(c.state.remotes.single.name, 'origin');
      expect(bindings.remotesReads - reads, 0);
      expect(c.state.remotesError?.message, 'fatal: not a git repo');
      expect(_errorLines(c), before + 1);
      expect(c.state.lastError, isNull);
    });

    // (r2)
    test('the next successful refresh re-reads and clears the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.remotesUpdated, 'fatal: boom'),
      );
      final int reads = bindings.remotesReads;

      c.debugHandleEvent(_updated(GbmEventType.remotesUpdated));

      expect(bindings.remotesReads - reads, 1);
      expect(c.state.remotesError, isNull);
    });

    // (r3)
    test(
      'an export that queued nothing fails the refresh without a log line',
      () {
        bindings.answer = 0;
        final int before = _errorLines(c);

        c.refreshRemotes();

        expect(bindings.remoteRefreshes, 1);
        expect(
          c.state.remotesError?.message,
          'Native error in gbm_remote_refresh',
        );
        expect(_errorLines(c), before);
        expect(c.state.lastError, isNull);
      },
    );

    // (r4) I2
    test('sending a refresh does not clear the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.remotesUpdated, 'fatal: boom'),
      );

      c.refreshRemotes();

      expect(bindings.remoteRefreshes, 1);
      expect(c.state.remotesError?.message, 'fatal: boom');
    });
  });

  group('bisect status', () {
    void seed() {
      bindings.bisectStatusMap = <String, dynamic>{
        'active': true,
        'currentOid': 'ccc',
        'badOid': 'bbb',
        'goodOids': <String>['aaa'],
        'skippedOids': <String>[],
        'logText': '# bad: [bbb]',
      };
      c.debugHandleEvent(_updated(GbmEventType.bisectStatusUpdated));
      expect(c.state.bisectStatus.badOid, 'bbb');
    }

    // (r1)
    test(
      'a failed refresh keeps the status, re-reads nothing and logs once',
      () {
        seed();
        final int reads = bindings.bisectStatusReads;
        final int before = _errorLines(c);

        c.debugHandleEvent(
          _refreshFailed(
            GbmEventType.bisectStatusUpdated,
            'fatal: not a git repo',
          ),
        );

        expect(c.state.bisectStatus.badOid, 'bbb');
        expect(bindings.bisectStatusReads - reads, 0);
        expect(c.state.bisectError?.message, 'fatal: not a git repo');
        expect(_errorLines(c), before + 1);
        expect(c.state.lastError, isNull);
      },
    );

    // (r2)
    test('the next successful refresh re-reads and clears the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.bisectStatusUpdated, 'fatal: boom'),
      );
      final int reads = bindings.bisectStatusReads;

      c.debugHandleEvent(_updated(GbmEventType.bisectStatusUpdated));

      expect(bindings.bisectStatusReads - reads, 1);
      expect(c.state.bisectError, isNull);
    });

    // (r3)
    test(
      'an export that queued nothing fails the refresh without a log line',
      () {
        bindings.answer = 0;
        final int before = _errorLines(c);

        c.refreshBisectStatus();

        expect(bindings.bisectRefreshes, 1);
        expect(
          c.state.bisectError?.message,
          'Native error in gbm_bisect_refresh',
        );
        expect(_errorLines(c), before);
        expect(c.state.lastError, isNull);
      },
    );

    // (r4) I2
    test('sending a refresh does not clear the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.bisectStatusUpdated, 'fatal: boom'),
      );

      c.refreshBisectStatus();

      expect(bindings.bisectRefreshes, 1);
      expect(c.state.bisectError?.message, 'fatal: boom');
    });
  });

  group('submodule list', () {
    void seed() {
      bindings.submodulesList = <Map<String, dynamic>>[
        <String, dynamic>{
          'name': 'vendor/libgit',
          'path': 'vendor/libgit',
          'url': 'https://example.com/libgit.git',
          'branch': 'main',
          'headOid': 'a1b2c3d',
          'state': 1,
        },
      ];
      c.debugHandleEvent(_updated(GbmEventType.submodulesUpdated));
      expect(c.state.submodules.single.path, 'vendor/libgit');
    }

    // (r1)
    test('a failed refresh keeps the list, re-reads nothing and logs once', () {
      seed();
      final int reads = bindings.submodulesReads;
      final int before = _errorLines(c);

      c.debugHandleEvent(
        _refreshFailed(GbmEventType.submodulesUpdated, 'fatal: not a git repo'),
      );

      expect(c.state.submodules.single.path, 'vendor/libgit');
      expect(bindings.submodulesReads - reads, 0);
      expect(c.state.submodulesError?.message, 'fatal: not a git repo');
      expect(_errorLines(c), before + 1);
      expect(c.state.lastError, isNull);
    });

    // (r2)
    test('the next successful refresh re-reads and clears the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.submodulesUpdated, 'fatal: boom'),
      );
      final int reads = bindings.submodulesReads;

      c.debugHandleEvent(_updated(GbmEventType.submodulesUpdated));

      expect(bindings.submodulesReads - reads, 1);
      expect(c.state.submodulesError, isNull);
    });

    // (r3)
    test(
      'an export that queued nothing fails the refresh without a log line',
      () {
        bindings.answer = 0;
        final int before = _errorLines(c);

        c.refreshSubmodules();

        expect(bindings.submoduleRefreshes, 1);
        expect(
          c.state.submodulesError?.message,
          'Native error in gbm_submodule_refresh',
        );
        expect(_errorLines(c), before);
        expect(c.state.lastError, isNull);
      },
    );

    // (r4) I2
    test('sending a refresh does not clear the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.submodulesUpdated, 'fatal: boom'),
      );

      c.refreshSubmodules();

      expect(bindings.submoduleRefreshes, 1);
      expect(c.state.submodulesError?.message, 'fatal: boom');
    });
  });

  group('lfs', () {
    void seed() {
      bindings.lfsInstallationMap = <String, dynamic>{
        'available': true,
        'version': '3.4.0',
      };
      bindings.lfsPatternsList = <String>['*.psd'];
      bindings.lfsFilesList = <Map<String, dynamic>>[
        <String, dynamic>{
          'path': 'art/logo.psd',
          'oid': 'aaa',
          'downloadedLocally': true,
        },
      ];
      c.debugHandleEvent(_updated(GbmEventType.lfsUpdated));
      expect(c.state.lfsInstallation?.available, isTrue);
      expect(c.state.lfsPatterns, <String>['*.psd']);
      expect(c.state.lfsFiles.single.path, 'art/logo.psd');
    }

    // (r1) All three parts stay as they were, and none is re-read.
    test(
      'a failed refresh keeps all three parts, re-reads nothing, logs once',
      () {
        seed();
        final int reads = bindings.lfsReads;
        final int before = _errorLines(c);

        c.debugHandleEvent(
          _refreshFailed(GbmEventType.lfsUpdated, 'fatal: not a git repo'),
        );

        expect(c.state.lfsInstallation?.available, isTrue);
        expect(c.state.lfsPatterns, <String>['*.psd']);
        expect(c.state.lfsFiles.single.path, 'art/logo.psd');
        expect(bindings.lfsReads - reads, 0);
        expect(c.state.lfsError?.message, 'fatal: not a git repo');
        expect(_errorLines(c), before + 1);
        expect(c.state.lastError, isNull);
      },
    );

    // (r2)
    test('the next successful refresh re-reads and clears the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.lfsUpdated, 'fatal: boom'),
      );
      final int reads = bindings.lfsReads;

      c.debugHandleEvent(_updated(GbmEventType.lfsUpdated));

      expect(bindings.lfsReads - reads, 3);
      expect(c.state.lfsError, isNull);
    });

    // (r3)
    test(
      'an export that queued nothing fails the refresh without a log line',
      () {
        bindings.answer = 0;
        final int before = _errorLines(c);

        c.refreshLfs();

        expect(bindings.lfsRefreshes, 1);
        expect(c.state.lfsError?.message, 'Native error in gbm_lfs_refresh');
        expect(_errorLines(c), before);
        expect(c.state.lastError, isNull);
      },
    );

    // (r4) I2
    test('sending a refresh does not clear the error', () {
      c.debugHandleEvent(
        _refreshFailed(GbmEventType.lfsUpdated, 'fatal: boom'),
      );

      c.refreshLfs();

      expect(bindings.lfsRefreshes, 1);
      expect(c.state.lfsError?.message, 'fatal: boom');
    });
  });

  group('stash diff', () {
    KeyedReadReply<StashDiffKey, ParsedDiff>? reply() => c.state.lastStashDiff;

    GbmEvent diffOk(int index) =>
        readyEvent(GbmEventType.stashDiffReady, <String, dynamic>{
          'index': index,
          'diff': <String, dynamic>{
            'files': <dynamic>[],
            'truncated': false,
            'inputBytes': 0,
          },
          'error': null,
        });

    GbmEvent diffFailed(int index, String message) =>
        readyEvent(GbmEventType.stashDiffReady, <String, dynamic>{
          'index': index,
          'diff': null,
          'error': gitErrorJson(message),
        });

    // (e)
    test('a request resets the reply to pending for its own index', () {
      c.requestStashDiff(0);
      c.debugHandleEvent(diffOk(0));
      expect(reply()?.value, isNotNull);

      c.requestStashDiff(1);

      expect(reply()?.key, const StashDiffKey(1));
      expect(reply()?.value, isNull);
      expect(reply()?.error, isNull);
      expect(bindings.stashDiffRequests.where((i) => i == 1).length, 1);
    });

    // (b)
    test('a reply for an older index is dropped', () {
      c.requestStashDiff(0);
      c.requestStashDiff(1);
      c.debugHandleEvent(diffOk(0));

      expect(reply()?.key, const StashDiffKey(1));
      expect(reply()?.value, isNull);
    });

    // (a) + (f)
    test('a failure reply carries the error, logs once, leaves lastError', () {
      c.requestStashDiff(1);
      final int before = _errorLines(c);

      c.debugHandleEvent(diffFailed(1, 'fatal: bad stash'));

      expect(reply()?.value, isNull);
      expect(reply()?.error?.message, 'fatal: bad stash');
      expect(_errorLines(c), before + 1);
      expect(c.state.lastError, isNull);
    });

    // (c) + (h)
    test('an export that queued nothing fails the read without a log line', () {
      bindings.answer = 0;
      final int before = _errorLines(c);

      c.requestStashDiff(1);

      expect(bindings.stashDiffRequests, <int>[1]);
      expect(reply()?.key, const StashDiffKey(1));
      expect(reply()?.error?.message, 'Native error in gbm_stash_request_diff');
      expect(_errorLines(c), before);
    });
  });
}
