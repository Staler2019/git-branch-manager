import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/clone_job_native.dart';
import '../ffi/event_dispatcher.dart';
import '../ffi/gbm_bindings.dart';
import '../ffi/json_codec.dart';
import '../models/app_log_events.dart';
import '../models/clone_events.dart';
import '../models/clone_job.dart';
import '../models/git_error.dart';
import '../models/git_version.dart';
import '../models/operation_record.dart';
import 'gbm_bindings_provider.dart';
import 'repo_identity.dart';
import 'repo_session_repository.dart';
import 'window_log_repository.dart';

/// A Log a clone job writes into: the window that started it (a session's,
/// or the no-repository window's, R13), or the new repository's (R12).
class CloneLogTarget {
  const CloneLogTarget({required this.record, required this.retract});

  /// A session's Log.
  factory CloneLogTarget.session(RepoSessionController session) =>
      CloneLogTarget(
        record: session.recordLogEntry,
        retract: session.retractLogEntries,
      );

  /// The no-repository window's Log.
  factory CloneLogTarget.window(WindowLogController log) => CloneLogTarget(
    record: log.recordLogEntry,
    retract: log.retractLogEntries,
  );

  final void Function(GbmLogEntry entry) record;
  final void Function(Set<int> ids) retract;
}

/// What the controller keeps per job beyond the public [CloneJob].
class _Running {
  _Running(this.handle, this.origin);

  final CloneJobHandle handle;
  final CloneLogTarget origin;

  /// This job's git rows, newest form of each, in order: what moves to the
  /// new repository's Log on success.
  List<GbmLogEntry> rows = const <GbmLogEntry>[];
}

/// Runs clones as background jobs, outside any repository session (P15 B,
/// TASKS, DLGS 「進行中不卡 dialog」).
///
/// - git rows and progress go to the starting window's Log; the running row
///   carries the progress (W-D7).
/// - Success: the rows leave the origin, land in the new repository's Log,
///   then [opened] names the destination for the app to navigate to (R10,
///   R12). Navigation is not done here: data/ never imports routing.
/// - Failure or cancel: the rows stay where they are; a cancel adds what
///   happened to the folder it made (TASKS, W-D12). No popup (R11).
class CloneJobController extends StateNotifier<List<CloneJob>> {
  CloneJobController({
    required this._native,
    required this._repositoryLog,
    required this._nowEpochMs,
  }) : super(const <CloneJob>[]);

  final CloneJobNative _native;
  final CloneLogTarget Function(String destPath) _repositoryLog;
  final int Function() _nowEpochMs;
  final Map<int, _Running> _running = <int, _Running>{};
  final StreamController<String> _opened = StreamController<String>.broadcast();
  int _nextId = 1;

  /// The destination of each clone that succeeded, after its rows are in
  /// that repository's Log.
  Stream<String> get opened => _opened.stream;

  /// The git every clone runs, for the dialog's submodule default (W-D5).
  GitVersion? gitVersion() => _native.gitVersion();

  /// Starts a clone; its id, or null when it was refused before git ran
  /// (the refusal is an error line in [origin]).
  int? start({
    required String url,
    required String destPath,
    required bool recurseSubmodules,
    required bool shallow,
    required CloneLogTarget origin,
  }) {
    final int id = _nextId++;
    final CloneJobStart result = _native.start(
      url: url,
      destPath: destPath,
      recurseSubmodules: recurseSubmodules,
      depth: shallow ? 1 : 0,
      onEvent: (GbmEvent event) => _onEvent(id, event),
    );
    switch (result) {
      case CloneJobRefused(:final GitError error):
        origin.record(_errorLine(error));
        return null;
      case CloneJobStarted(:final CloneJobHandle job):
        _running[id] = _Running(job, origin);
        state = <CloneJob>[
          ...state,
          CloneJob(id: id, url: url, destPath: destPath),
        ];
        return id;
    }
  }

  void cancel(int id) => _running[id]?.handle.cancel();

  void provideCredential(int id, String secret) {
    _running[id]?.handle.provideCredential(secret);
    _update(id, (CloneJob j) => j.withCredentialPrompt(null));
  }

  void cancelCredential(int id) {
    _running[id]?.handle.cancelCredential();
    _update(id, (CloneJob j) => j.withCredentialPrompt(null));
  }

  void _onEvent(int id, GbmEvent event) {
    final _Running? run = _running[id];
    if (run == null || !mounted) return;
    final Object? payload = decodeEventPayload(event.payload);
    if (payload is! Map<String, dynamic>) return;
    switch (event.type) {
      case GbmEventType.operationLogRecord:
        final OperationRecord record = OperationRecord.fromJson(payload);
        final CloneProgress? progress = _job(id)?.progress;
        _record(
          run,
          record.running && progress != null
              ? record.withProgress(progress.label)
              : record,
        );
      case GbmEventType.credentialRequested:
        _update(
          id,
          (CloneJob j) =>
              j.withCredentialPrompt(payload['prompt'] as String? ?? ''),
        );
      case GbmEventType.cloneProgress:
        final CloneProgress progress = CloneProgress.fromJson(payload);
        _update(id, (CloneJob j) => j.withProgress(progress));
        final GbmLogEntry? last = run.rows.isEmpty ? null : run.rows.last;
        if (last is OperationRecord && last.running) {
          _record(run, last.withProgress(progress.label));
        }
      case GbmEventType.cloneFinished:
        _finish(id, run, CloneFinished.fromJson(payload));
    }
  }

  void _record(_Running run, OperationRecord record) {
    run.rows = appendLogEntry(run.rows, record, maxEntries: 1 << 30);
    run.origin.record(record);
  }

  void _finish(int id, _Running run, CloneFinished finished) {
    final CloneJob? job = _job(id);
    run.handle.close();
    _running.remove(id);
    state = <CloneJob>[
      for (final CloneJob j in state)
        if (j.id != id) j,
    ];
    if (job == null) return;
    final Set<int> ids = <int>{
      for (final GbmLogEntry e in run.rows)
        if (e is OperationRecord && e.id != 0) e.id,
    };
    if (finished.ok) {
      run.origin.retract(ids);
      // Core's normalised path, so `/src/r/` opens the same repository as
      // `/src/r` (verifier A2); the typed one only if core named none.
      final String dest = finished.destPath ?? job.destPath;
      final CloneLogTarget target = _repositoryLog(dest);
      for (final GbmLogEntry row in run.rows) {
        target.record(row);
      }
      _opened.add(dest);
      return;
    }
    final GitError? error = finished.error;
    if (finished.removedPath case final String path) {
      run.origin.record(
        AppLogEvents.cloneDestinationRemoved(path, atEpochMs: _nowEpochMs()),
      );
    }
    if (finished.removalError case final String reason) {
      run.origin.record(
        AppLogEvents.cloneDestinationNotRemoved(
          job.destPath,
          reason: reason,
          atEpochMs: _nowEpochMs(),
        ),
      );
    }
    if (error != null && ids.isEmpty && error.codeName != 'Cancelled') {
      run.origin.record(_errorLine(error));
    }
  }

  AppLogEntry _errorLine(GitError error) => AppLogEvents.errorOccurred(
    codeName: error.codeName,
    message: error.message,
    atEpochMs: _nowEpochMs(),
  );

  CloneJob? _job(int id) {
    for (final CloneJob j in state) {
      if (j.id == id) return j;
    }
    return null;
  }

  void _update(int id, CloneJob Function(CloneJob) change) {
    state = <CloneJob>[
      for (final CloneJob j in state) j.id == id ? change(j) : j,
    ];
  }

  /// Abandons every running job: once closed, none of them reaches this
  /// controller again ([FLU-close-session-before-callable]).
  @override
  void dispose() {
    for (final _Running run in _running.values) {
      run.handle.close();
    }
    _running.clear();
    unawaited(_opened.close());
    super.dispose();
  }
}

/// The native clone seam; overridden in tests.
final Provider<CloneJobNative> cloneJobNativeProvider =
    Provider<CloneJobNative>(
      (ref) => GbmCloneJobNative(ref.watch(gbmBindingsProvider)),
    );

/// The Log a successful clone's rows move to (R12): the new repository's
/// session, created here if nothing has opened it yet -- the same instance
/// the workspace then watches. A provider so a test can stand in for it.
final Provider<CloneLogTarget Function(String destPath)>
cloneRepositoryLogProvider = Provider<CloneLogTarget Function(String)>(
  (ref) =>
      (String dest) => CloneLogTarget.session(
        ref.read(repoSessionProvider(RepoIdentity.forWorkDir(dest)).notifier),
      ),
);

/// App-wide: a clone outlives the window and route that started it.
final StateNotifierProvider<CloneJobController, List<CloneJob>>
cloneJobsProvider = StateNotifierProvider<CloneJobController, List<CloneJob>>(
  (ref) => CloneJobController(
    native: ref.read(cloneJobNativeProvider),
    repositoryLog: ref.read(cloneRepositoryLogProvider),
    nowEpochMs: () => DateTime.now().millisecondsSinceEpoch,
  ),
);
