import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/event_dispatcher.dart';
import '../ffi/gbm_bindings.dart';
import '../ffi/json_codec.dart';
import '../models/git_error.dart';
import '../models/graph_snapshot.dart';
import '../models/parsed_diff.dart';
import '../models/ref_snapshot.dart';
import '../models/repo_state.dart' as model;
import '../models/working_copy_status.dart';
import 'gbm_bindings_provider.dart';
import 'repo_identity.dart';

/// Mirrors `gbm::ResetMode` (src/core/git/ops/ResetOps.h) -- ordinal order
/// matters, it is passed straight through to `gbm_reset_to`.
enum ResetMode { soft, mixed, hard }

/// Reply to [RepoSessionController.requestDiff]: the diff plus which
/// path/staged pair it answers, so a caller that fired several diff
/// requests can tell which one just arrived -- mirrors
/// GBM_EVENT_WORKING_COPY_DIFF_READY's payload shape.
class WorkingCopyDiffReply {
  const WorkingCopyDiffReply({required this.path, required this.staged, required this.diff});

  factory WorkingCopyDiffReply.fromJson(Map<String, dynamic> json) {
    return WorkingCopyDiffReply(
      path: json['path'] as String,
      staged: json['staged'] as bool,
      diff: ParsedDiff.fromJson(json['diff'] as Map<String, dynamic>),
    );
  }

  final String path;
  final bool staged;
  final ParsedDiff diff;
}

/// Everything the workspace shell (`features/workspace`), sidebar
/// (`features/sidebar`) and history graph (`features/history_graph`) read
/// for one open repository. Immutable; a new session event produces a new
/// `RepoSessionState` via [RepoSessionController.state] rather than mutating
/// this in place, matching gbm_capi's own "publish a new snapshot" discipline
/// (see docs/ARCHITECTURE.md's invariant 2).
class RepoSessionState {
  const RepoSessionState({
    this.isOpen = false,
    this.repoState,
    this.refs = RefSnapshot.empty,
    this.graph = GraphSnapshotView.empty,
    this.isRefreshing = false,
    this.lastError,
    this.workingCopyStatus = WorkingCopyStatus.empty,
    this.lastDiff,
  });

  final bool isOpen;
  final model.RepoState? repoState;
  final RefSnapshot refs;
  final GraphSnapshotView graph;
  final bool isRefreshing;
  final GitError? lastError;
  final WorkingCopyStatus workingCopyStatus;
  final WorkingCopyDiffReply? lastDiff;

  RepoSessionState copyWith({
    bool? isOpen,
    model.RepoState? repoState,
    RefSnapshot? refs,
    GraphSnapshotView? graph,
    bool? isRefreshing,
    GitError? lastError,
    bool clearError = false,
    WorkingCopyStatus? workingCopyStatus,
    WorkingCopyDiffReply? lastDiff,
  }) {
    return RepoSessionState(
      isOpen: isOpen ?? this.isOpen,
      repoState: repoState ?? this.repoState,
      refs: refs ?? this.refs,
      graph: graph ?? this.graph,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastError: clearError ? null : (lastError ?? this.lastError),
      workingCopyStatus: workingCopyStatus ?? this.workingCopyStatus,
      lastDiff: lastDiff ?? this.lastDiff,
    );
  }
}

/// Owns one `gbm_capi` session handle end to end: opens it, subscribes to
/// its events, and closes it on dispose. One instance per open repository
/// (`workspaceScreen`'s route scope owns the provider lifetime -- see the
/// routing table in the plan).
class RepoSessionController extends StateNotifier<RepoSessionState> {
  RepoSessionController(this._bindings, this._identity) : super(const RepoSessionState()) {
    _open();
  }

  final GbmBindings _bindings;
  final RepoIdentity _identity;
  Pointer<Void> _session = nullptr;
  GbmSessionEvents? _events;
  StreamSubscription<GbmEvent>? _subscription;

  void _open() {
    final Pointer<Utf8> workDir = _identity.workDir.toNativeUtf8();
    final Pointer<Utf8> gitDir = _identity.gitDir.toNativeUtf8();
    final Pointer<Utf8> commonDir = _identity.commonDir.toNativeUtf8();
    try {
      _session = _bindings.sessionOpen(workDir, gitDir, commonDir);
    } finally {
      malloc.free(workDir);
      malloc.free(gitDir);
      malloc.free(commonDir);
    }

    if (_session == nullptr) {
      state = state.copyWith(lastError: _decodeLastError());
      return;
    }

    final GbmSessionEvents events = GbmSessionEvents(_bindings, _session);
    _events = events;
    _subscription = events.events.listen(_onEvent);

    state = state.copyWith(isOpen: true);
    _readRepoState();
    refreshHistory();
    refreshWorkingCopy();
  }

  void _onEvent(GbmEvent event) {
    switch (event.type) {
      case GbmEventType.refsUpdated:
        _readRefs();
      case GbmEventType.graphUpdated:
        final Object? payload = decodeEventPayload(event.payload);
        final bool complete = payload is Map<String, dynamic> ? payload['complete'] as bool? ?? false : false;
        state = state.copyWith(graph: readGraphSnapshot(_bindings, _session), isRefreshing: !complete);
      case GbmEventType.errorOccurred:
        final Object? payload = decodeEventPayload(event.payload);
        state = state.copyWith(
          isRefreshing: false,
          lastError: payload is Map<String, dynamic> ? GitError.fromJson(payload) : null,
        );
      case GbmEventType.operationFinished:
        _readRepoState();
      case GbmEventType.workingCopyStatusUpdated:
        _readWorkingCopyStatus();
      case GbmEventType.workingCopyOperationFinished:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic> && payload['succeeded'] == false) {
          final Object? error = payload['error'];
          state = state.copyWith(lastError: error is Map<String, dynamic> ? GitError.fromJson(error) : null);
        }
      case GbmEventType.workingCopyDiffReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          state = state.copyWith(lastDiff: WorkingCopyDiffReply.fromJson(payload));
        }
    }
  }

  void _readRepoState() {
    if (_bindings.repoStateJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(repoState: model.RepoState.fromJson(jsonDecode(json) as Map<String, dynamic>));
      }
    }
  }

  void _readRefs() {
    if (_bindings.refsJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(refs: RefSnapshot.fromJson(jsonDecode(json) as Map<String, dynamic>));
      }
    }
  }

  void _readWorkingCopyStatus() {
    if (_bindings.workingCopyStatusJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(workingCopyStatus: WorkingCopyStatus.fromJson(jsonDecode(json) as Map<String, dynamic>));
      }
    }
  }

  GitError? _decodeLastError() {
    final String json = readLastResultJson(_bindings);
    return json.isEmpty ? null : GitError.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  /// Requests a refs + history refresh -- see gbm_history_refresh()'s doc
  /// comment in gbm_capi.h. Async: [state] updates as GBM_EVENT_* events
  /// arrive through [_onEvent].
  void refreshHistory() {
    if (_session == nullptr) return;
    state = state.copyWith(isRefreshing: true, clearError: true);
    _bindings.historyRefresh(_session);
  }

  /// `git switch`/`git checkout`. See gbm_branch_checkout()'s doc comment in
  /// gbm_capi.h for the target/createBranch/newBranchName relationship.
  void checkout({required String target, bool createBranch = false, String newBranchName = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> targetPtr = target.toNativeUtf8();
    final Pointer<Utf8> newBranchPtr = newBranchName.toNativeUtf8();
    try {
      _bindings.branchCheckout(_session, targetPtr, 0, createBranch ? 1 : 0, newBranchPtr, 0, 0, 0);
    } finally {
      malloc.free(targetPtr);
      malloc.free(newBranchPtr);
    }
  }

  /// `git reset --soft|--mixed|--hard <target>`. `target` empty means HEAD.
  /// See gbm_reset_to()'s doc comment in gbm_capi.h: on success also
  /// refreshes history and the working copy.
  void resetTo(String target, ResetMode mode) {
    if (_session == nullptr) return;
    final Pointer<Utf8> targetPtr = target.toNativeUtf8();
    try {
      _bindings.resetTo(_session, targetPtr, mode.index);
    } finally {
      malloc.free(targetPtr);
    }
  }

  /// Re-reads `git status`. See gbm_working_copy_refresh()'s doc comment in
  /// gbm_capi.h. Async: [state].workingCopyStatus updates when
  /// GBM_EVENT_WORKING_COPY_STATUS_UPDATED arrives.
  void refreshWorkingCopy() {
    if (_session == nullptr) return;
    _bindings.workingCopyRefresh(_session);
  }

  /// Diff of one path: work tree vs index (staged=false) or index vs HEAD
  /// (staged=true). Async: [state].lastDiff updates when
  /// GBM_EVENT_WORKING_COPY_DIFF_READY arrives.
  void requestDiff(String path, {bool staged = false}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    try {
      _bindings.workingCopyDiff(_session, pathPtr, staged ? 1 : 0);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// `git add -- <paths>`. Async: fires GBM_EVENT_WORKING_COPY_OPERATION_FINISHED
  /// and (on success) a working-copy refresh, both reflected in [state].
  void stageFiles(List<String> paths) {
    if (_session == nullptr) return;
    _withNativeStringArray(paths, (array, count) => _bindings.stageFiles(_session, array, count));
  }

  /// `git restore --staged -- <paths>`. Same event/refresh contract as
  /// [stageFiles].
  void unstageFiles(List<String> paths) {
    if (_session == nullptr) return;
    _withNativeStringArray(paths, (array, count) => _bindings.unstageFiles(_session, array, count));
  }

  /// `git commit` / `git commit --amend`. Async: fires
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and on success also
  /// refreshes both the working copy and the history graph (the new commit
  /// needs to appear there).
  void commit(String message, {bool amend = false, bool signOff = false}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      _bindings.commitChanges(_session, messagePtr, amend ? 1 : 0, signOff ? 1 : 0);
    } finally {
      malloc.free(messagePtr);
    }
  }

  /// Marshals `paths` into a native `const char* const*` for the lifetime of
  /// `body`, then frees every string and the array itself.
  void _withNativeStringArray(List<String> paths, void Function(Pointer<Pointer<Utf8>> array, int count) body) {
    final Pointer<Pointer<Utf8>> array = malloc<Pointer<Utf8>>(paths.length);
    try {
      for (int i = 0; i < paths.length; i++) {
        array[i] = paths[i].toNativeUtf8();
      }
      body(array, paths.length);
    } finally {
      for (int i = 0; i < paths.length; i++) {
        malloc.free(array[i]);
      }
      malloc.free(array);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _events?.dispose();
    if (_session != nullptr) {
      _bindings.sessionClose(_session);
      _session = nullptr;
    }
    super.dispose();
  }
}

final StateNotifierProviderFamily<RepoSessionController, RepoSessionState, RepoIdentity> repoSessionProvider =
    StateNotifierProvider.family<RepoSessionController, RepoSessionState, RepoIdentity>((ref, identity) {
      final GbmBindings bindings = ref.watch(gbmBindingsProvider);
      return RepoSessionController(bindings, identity);
    });
