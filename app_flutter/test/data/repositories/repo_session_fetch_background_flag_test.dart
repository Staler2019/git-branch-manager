// fetchRemote(background:) must reach gbm_remote_fetch's `background`
// argument: on the C side it is what refuses every credential prompt and
// leaves the session's askpass watch alone (RemoteApiTest's SshRemoteApiTest).
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

/// Opens a session and records each gbm_remote_fetch call's `background`.
class _FetchRecordingBindings extends FakeGbmBindings {
  final List<int> backgroundArgs = <int>[];
  Uint8List _staged = Uint8List(0);

  /// Answers the RepoState read every working-copy outcome triggers
  /// (repo_session_cancelled_outcome_test.dart's shape).
  @override
  RepoStateJsonDart get repoStateJson => (Pointer<Void> session) {
    _staged = utf8.encode(
      jsonEncode(<String, dynamic>{
        'flags': 0,
        'isClean': true,
        'isSequencerOperation': false,
        'rebaseStep': 0,
        'rebaseTotal': 0,
        'rebaseOntoLabel': '',
        'indexLocked': false,
        'indexLockAgeSeconds': null,
        'preparedMessagePending': false,
        'describe': '',
      }),
    );
    return 0;
  };

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _staged.length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) {
        out.asTypedList(outLen).setAll(0, _staged);
      };

  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          Pointer<Void>.fromAddress(1);

  @override
  SessionCloseDart get sessionClose => (Pointer<Void> session) {};

  @override
  RegisterCallbackDart get registerCallback => (
    Pointer<Void> session,
    Pointer<NativeFunction<GbmEventCallbackNative>> callback,
    Pointer<Void> userData,
  ) {};

  @override
  HistoryRefreshDart get historyRefresh =>
      (Pointer<Void> session) => 1;

  @override
  WorkingCopyRefreshDart get workingCopyRefresh => (Pointer<Void> session) {};

  @override
  LocalIdentityRefreshDart get localIdentityRefresh =>
      (Pointer<Void> session) {};

  @override
  EffectiveIdentityRefreshDart get effectiveIdentityRefresh =>
      (Pointer<Void> session) {};

  /// What gbm_cancel_operation answers: -1 is core refusing (NotCancellable).
  int cancelAnswer = 1;

  @override
  CancelOperationDart get cancelOperation =>
      (Pointer<Void> session, int id) => cancelAnswer;

  @override
  RemoteFetchDart get remoteFetch =>
      (
        Pointer<Void> session,
        Pointer<Utf8> remoteName,
        Pointer<Pointer<Utf8>> refs,
        int refCount,
        int prune,
        int tags,
        int background,
      ) {
        backgroundArgs.add(background);
      };
}

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

void main() {
  test('background: true reaches gbm_remote_fetch as 1, the default as 0', () {
    final _FetchRecordingBindings bindings = _FetchRecordingBindings();
    final RepoSessionController controller = RepoSessionController(
      bindings,
      RepoIdentity.forWorkDir('/test/repo'),
      _NoopRecents(),
    );
    addTearDown(controller.dispose);

    controller.fetchRemote(background: true);
    controller.fetchRemote();

    expect(bindings.backgroundArgs, <int>[1, 0]);
  });

  test('a fetchRemote(background: true) failure stays out of lastError; '
      "a manual fetch's does not", () {
    final RepoSessionController controller = RepoSessionController(
      _FetchRecordingBindings(),
      RepoIdentity.forWorkDir('/test/repo'),
      _NoopRecents(),
    );
    addTearDown(controller.dispose);
    GbmEvent authFailure() => GbmEvent(
      GbmEventType.workingCopyOperationFinished,
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'succeeded': false,
          'error': <String, dynamic>{
            'code': 5,
            'codeName': 'Auth',
            'message': 'Git needs credentials',
            'detail': '',
            'argv': <String>[],
            'exitCode': 128,
          },
          'choices': <dynamic>[],
          'summary': 'Git needs credentials',
          'kind': 'fetch',
        }),
      ),
    );

    controller.fetchRemote(background: true);
    controller.debugHandleEvent(authFailure());
    expect(controller.state.lastError, isNull);

    controller.fetchRemote();
    controller.debugHandleEvent(authFailure());
    expect(controller.state.lastError?.codeName, 'Auth');
  });

  test('fetchFinished reports each fetch with its background flag, outcome '
      'and error code -- what the auto fetch scheduler pauses on', () {
    final RepoSessionController controller = RepoSessionController(
      _FetchRecordingBindings(),
      RepoIdentity.forWorkDir('/test/repo'),
      _NoopRecents(),
    );
    addTearDown(controller.dispose);
    final List<FetchFinished> seen = <FetchFinished>[];
    controller.fetchFinished.listen(seen.add);
    GbmEvent finished({Map<String, dynamic>? error}) => GbmEvent(
      GbmEventType.workingCopyOperationFinished,
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'succeeded': error == null,
          'error': ?error,
          'choices': <dynamic>[],
          'summary': '',
          'kind': 'fetch',
        }),
      ),
    );

    controller.fetchRemote(background: true);
    controller.debugHandleEvent(
      finished(
        error: <String, dynamic>{
          'code': 6,
          'codeName': 'HostKey',
          'message': 'Unknown SSH host key',
          'detail': '',
          'argv': <String>[],
          'exitCode': 128,
        },
      ),
    );
    controller.fetchRemote();
    controller.debugHandleEvent(finished());

    expect(seen, <FetchFinished>[
      (background: true, succeeded: false, errorCodeName: 'HostKey'),
      (background: false, succeeded: true, errorCodeName: null),
    ]);
  });

  // 使用者裁定 2026-10-24: a refused Cancel of a running auto fetch 「拒絕訊息
  // 只進 log」 -- 背景作業失敗不彈窗. A manual operation's refusal still
  // raises the banner: it is how the user hears it kept running.
  group('a refused Cancel', () {
    GbmEvent record({required bool auto, required int queuedId}) => GbmEvent(
      GbmEventType.operationLogRecord,
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'id': queuedId,
          'running': true,
          'whenEpochMs': 0,
          'repoDir': '/test/repo',
          'argv': <String>[
            'git',
            'fetch',
            if (auto) ...<String>[
              '--no-auto-maintenance',
              '--no-write-fetch-head',
            ],
            '--all',
          ],
          'commandLine': '',
          'exitCode': 0,
          'durationMs': 0,
          'stderrText': '',
          'cancelled': false,
          'timedOut': false,
          'benignExit': false,
          'timeoutMs': 0,
          'idleTimeoutMs': 0,
          'queuedOperationId': queuedId,
        }),
      ),
    );
    final GbmEvent refused = GbmEvent(
      GbmEventType.errorOccurred,
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'code': 0,
          'codeName': 'NotCancellable',
          'message': '"git fetch" can\'t be cancelled once it has started',
          'detail': '',
          'argv': <String>[],
          'exitCode': 0,
        }),
      ),
    );

    test('an auto fetch refusal is used up: the next manual refusal still '
        'sets lastError', () {
      final _FetchRecordingBindings bindings = _FetchRecordingBindings()
        ..cancelAnswer = -1;
      final RepoSessionController controller = RepoSessionController(
        bindings,
        RepoIdentity.forWorkDir('/test/repo'),
        _NoopRecents(),
      );
      addTearDown(controller.dispose);

      controller.debugHandleEvent(record(auto: true, queuedId: 9));
      controller.cancelOperation(9);
      controller.debugHandleEvent(refused);
      controller.debugHandleEvent(record(auto: false, queuedId: 10));
      controller.cancelOperation(10);
      controller.debugHandleEvent(refused);

      expect(controller.state.lastError?.codeName, 'NotCancellable');
    });

    for (final bool auto in <bool>[true, false]) {
      test(
        auto
            ? 'of an auto fetch goes to the log only'
            : 'of a manual fetch still sets lastError',
        () {
          final _FetchRecordingBindings bindings = _FetchRecordingBindings()
            ..cancelAnswer = -1;
          final RepoSessionController controller = RepoSessionController(
            bindings,
            RepoIdentity.forWorkDir('/test/repo'),
            _NoopRecents(),
          );
          addTearDown(controller.dispose);

          controller.debugHandleEvent(record(auto: auto, queuedId: 9));
          expect(controller.cancelOperation(9), -1);
          controller.debugHandleEvent(refused);

          expect(
            controller.state.lastError?.codeName,
            auto ? isNull : 'NotCancellable',
          );
          final List<AppLogEntry> lines = controller.state.operationLog
              .whereType<AppLogEntry>()
              .where((AppLogEntry e) => e.message.contains('NotCancellable'))
              .toList();
          expect(lines.length, 1);
          // A warning stays out of the status bar's red summary, which
          // shows only an unread error (P10 item 3).
          expect(
            lines.single.level,
            auto ? OperationLogLevel.warning : OperationLogLevel.error,
          );
        },
      );
    }
  });
}
