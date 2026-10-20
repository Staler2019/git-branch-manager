// CloneJobController: a clone as an ordinary background git operation
// (P15 B, TASKS, R10–R12). Its lines go to the Log of the window that
// started it; on success they move to the new repository's Log and the
// repository opens.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/clone_job_native.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/clone_job.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/git_version.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/clone_job_repository.dart';

class _Job implements CloneJobHandle {
  final List<String> calls = <String>[];
  @override
  void cancel() => calls.add('cancel');
  @override
  void provideCredential(String secret) => calls.add('provide:$secret');
  @override
  void cancelCredential() => calls.add('cancelCredential');
  @override
  void close() => calls.add('close');
}

class _Native implements CloneJobNative {
  final List<_Job> jobs = <_Job>[];
  final List<void Function(GbmEvent)> sinks = <void Function(GbmEvent)>[];
  final List<Map<String, Object>> starts = <Map<String, Object>>[];
  GitError? refuseWith;

  @override
  CloneJobStart start({
    required String url,
    required String destPath,
    required bool recurseSubmodules,
    required int depth,
    required void Function(GbmEvent event) onEvent,
  }) {
    starts.add(<String, Object>{
      'url': url,
      'dest': destPath,
      'recurse': recurseSubmodules,
      'depth': depth,
    });
    if (refuseWith case final GitError e) return CloneJobRefused(e);
    final _Job job = _Job();
    jobs.add(job);
    sinks.add(onEvent);
    return CloneJobStarted(job);
  }

  @override
  GitVersion? gitVersion() => const GitVersion(2, 50, 1);

  void emit(int job, int type, Object json) => sinks[job](
    GbmEvent(type, Uint8List.fromList(utf8.encode(jsonEncode(json)))),
  );

  void record(int job, int id, {bool running = false, int exitCode = 0}) =>
      emit(job, GbmEventType.operationLogRecord, <String, Object>{
        'id': id,
        'running': running,
        'whenEpochMs': id,
        'repoDir': '',
        'argv': <String>['clone', '--', 'https://alice:pw@h/r.git', '/d'],
        'commandLine': 'unused',
        'exitCode': exitCode,
        'durationMs': 0,
        'stderrText': '',
        'cancelled': false,
        'timedOut': false,
        'benignExit': false,
        'timeoutMs': 0,
        'idleTimeoutMs': 0,
      });
}

class _Log {
  final List<GbmLogEntry> entries = <GbmLogEntry>[];
  final List<Set<int>> retracted = <Set<int>>[];
  late final CloneLogTarget target = CloneLogTarget(
    record: (GbmLogEntry e) => entries.replaceRange(
      0,
      entries.length,
      appendLogEntry(entries, e, maxEntries: 100),
    ),
    retract: (Set<int> ids) {
      retracted.add(ids);
      entries.replaceRange(0, entries.length, retractLogEntries(entries, ids));
    },
  );
}

const Map<String, Object> _gitError = <String, Object>{
  'code': 7,
  'codeName': 'GitFailed',
  'message': 'Repository not found',
  'detail': '',
  'argv': <String>[],
  'exitCode': 128,
};

void main() {
  late _Native native;
  late _Log origin;
  late _Log repoLog;
  late List<String> opened;
  late CloneJobController controller;

  setUp(() {
    native = _Native();
    origin = _Log();
    repoLog = _Log();
    opened = <String>[];
    controller = CloneJobController(
      native: native,
      repositoryLog: (String dest) {
        expect(dest, '/src/design-tokens');
        return repoLog.target;
      },
      nowEpochMs: () => 42,
    );
    controller.opened.listen(opened.add);
  });
  tearDown(() => controller.dispose());

  int start({
    bool recurse = true,
    bool shallow = false,
    String destPath = '/src/design-tokens',
  }) => controller.start(
    url: 'https://h/design-tokens.git',
    destPath: destPath,
    recurseSubmodules: recurse,
    shallow: shallow,
    origin: origin.target,
  )!;

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('start hands the options across; shallow is depth 1', () {
    start(recurse: false, shallow: true);
    expect(native.starts.single, <String, Object>{
      'url': 'https://h/design-tokens.git',
      'dest': '/src/design-tokens',
      'recurse': false,
      'depth': 1,
    });
    start();
    expect(native.starts.last['depth'], 0);
    expect(native.starts.last['recurse'], isTrue);
  });

  test('a running job is in state, named after its destination', () {
    final int id = start();
    final CloneJob job = controller.state.single;
    expect(job.id, id);
    expect(job.name, 'design-tokens');
    expect(job.progress, isNull);
    expect(job.credentialPrompt, isNull);
  });

  test('a refusal is an error line in the origin Log and no job', () {
    native.refuseWith = GitError.fromJson(_gitError);
    expect(
      controller.start(
        url: 'x',
        destPath: '/src/design-tokens',
        recurseSubmodules: false,
        shallow: false,
        origin: origin.target,
      ),
      isNull,
    );
    expect(controller.state, isEmpty);
    expect(origin.entries.single.message, 'GitFailed: Repository not found');
    expect(origin.entries.single.level, OperationLogLevel.error);
    expect(origin.entries.single.whenEpochMs, 42);
  });

  test('git records go to the origin Log, masked, running row replaced', () {
    start();
    native.record(0, 5, running: true);
    expect(origin.entries.single.message, contains('alice:••••@'));
    native.record(0, 5);
    expect(origin.entries, hasLength(1));
    expect((origin.entries.single as OperationRecord).running, isFalse);
  });

  test('progress updates the job and the running row (W-D7)', () {
    start();
    native.record(0, 5, running: true);
    native.emit(0, GbmEventType.cloneProgress, <String, Object>{
      'phase': 'receiving',
      'current': 12480,
      'total': 31206,
    });
    expect(
      controller.state.single.progress!.label,
      'receiving objects 12,480 / 31,206',
    );
    expect(
      origin.entries.single.message,
      endsWith(' — receiving objects 12,480 / 31,206'),
    );
    // A later record of the same run keeps the progress already reached.
    native.record(0, 5, running: true);
    expect(origin.entries.single.message, endsWith('31,206'));
  });

  test('a credential prompt is the job\'s, answered through it', () {
    final int id = start();
    native.emit(0, GbmEventType.credentialRequested, <String, Object>{
      'prompt': "Password for 'https://h': ",
    });
    expect(
      controller.state.single.credentialPrompt,
      "Password for 'https://h': ",
    );
    controller.provideCredential(id, 's3cret');
    expect(native.jobs.single.calls, <String>['provide:s3cret']);
    expect(controller.state.single.credentialPrompt, isNull);

    native.emit(0, GbmEventType.credentialRequested, <String, Object>{
      'prompt': 'Username for x',
    });
    controller.cancelCredential(id);
    expect(native.jobs.single.calls.last, 'cancelCredential');
    expect(controller.state.single.credentialPrompt, isNull);
  });

  test('cancel forwards to the job', () {
    final int id = start();
    controller.cancel(id);
    expect(native.jobs.single.calls, <String>['cancel']);
  });

  // Verifier A2: the destination as typed (`/src/design-tokens/`) is not the
  // repository core cloned into; the finished event's path is.
  test('success opens the path core cloned into, not the spelling', () async {
    start(destPath: '/src/design-tokens/');
    native.emit(0, GbmEventType.cloneFinished, <String, Object>{
      'ok': true,
      'destPath': '/src/design-tokens',
    });
    await settle();

    expect(opened, <String>['/src/design-tokens']);
  });

  test(
    'success: rows move to the new repo, then it opens (R10, R12)',
    () async {
      start();
      controller.opened.listen((_) {
        // The rows are there before anything navigates to the repository.
        expect(repoLog.entries, hasLength(1));
      });
      native.record(0, 5, running: true);
      native.record(0, 5);
      native.emit(0, GbmEventType.cloneFinished, <String, Object>{'ok': true});
      await settle();

      expect(origin.retracted.single, <int>{5});
      expect(origin.entries, isEmpty);
      expect((repoLog.entries.single as OperationRecord).running, isFalse);
      expect(opened, <String>['/src/design-tokens']);
      expect(native.jobs.single.calls, <String>['close']);
      expect(controller.state, isEmpty);
    },
  );

  test('failure: rows stay in the origin, nothing opens', () async {
    start();
    native.record(0, 5, running: true);
    native.record(0, 5, exitCode: 128);
    native.emit(0, GbmEventType.cloneFinished, <String, Object>{
      'ok': false,
      'error': _gitError,
    });
    await settle();

    expect(origin.retracted, isEmpty);
    // git's own row already says it failed; no second line.
    expect(origin.entries, hasLength(1));
    expect(opened, isEmpty);
    expect(native.jobs.single.calls, <String>['close']);
    expect(controller.state, isEmpty);
  });

  test('failure before git ran is one error line', () async {
    start();
    native.emit(0, GbmEventType.cloneFinished, <String, Object>{
      'ok': false,
      'error': _gitError,
    });
    await settle();
    expect(origin.entries.single.message, 'GitFailed: Repository not found');
  });

  test('cancel that removed the folder says so (TASKS, W-D12)', () async {
    start();
    native.record(0, 5, running: true);
    native.emit(0, GbmEventType.cloneFinished, <String, Object>{
      'ok': false,
      'error': <String, Object>{..._gitError, 'codeName': 'Cancelled'},
      'removedPath': '/src/design-tokens',
    });
    await settle();
    expect(origin.entries.last.message, 'Removed /src/design-tokens');
    expect(origin.entries.last.level, OperationLogLevel.warning);
  });

  test('cancel whose cleanup failed says why', () async {
    start();
    native.emit(0, GbmEventType.cloneFinished, <String, Object>{
      'ok': false,
      'error': <String, Object>{..._gitError, 'codeName': 'Cancelled'},
      'removalError': 'Permission denied',
    });
    await settle();
    expect(
      origin.entries.single.message,
      'Could not remove /src/design-tokens: Permission denied',
    );
  });

  test('two jobs keep their own events apart', () {
    start();
    start();
    native.emit(1, GbmEventType.credentialRequested, <String, Object>{
      'prompt': 'p',
    });
    expect(controller.state.first.credentialPrompt, isNull);
    expect(controller.state.last.credentialPrompt, 'p');
  });

  test('gitVersion is the seam\'s, for the submodule default (W-D5)', () {
    expect(controller.gitVersion(), const GitVersion(2, 50, 1));
  });

  test('a trailing separator does not empty the name', () {
    expect(const CloneJob(id: 1, url: 'u', destPath: '/src/a/').name, 'a');
    expect(const CloneJob(id: 1, url: 'u', destPath: r'C:\src\b').name, 'b');
  });

  test('dispose closes every running job', () {
    final CloneJobController local = CloneJobController(
      native: native,
      repositoryLog: (_) => repoLog.target,
      nowEpochMs: () => 0,
    );
    local.start(
      url: 'u',
      destPath: '/a',
      recurseSubmodules: false,
      shallow: false,
      origin: origin.target,
    );
    local.dispose();
    expect(native.jobs.single.calls, <String>['close']);
  });
}
