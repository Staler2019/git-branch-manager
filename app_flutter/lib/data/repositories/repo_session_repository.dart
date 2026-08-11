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
import '../models/ref_snapshot.dart';
import '../models/repo_state.dart' as model;
import 'gbm_bindings_provider.dart';
import 'repo_identity.dart';

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
  });

  final bool isOpen;
  final model.RepoState? repoState;
  final RefSnapshot refs;
  final GraphSnapshotView graph;
  final bool isRefreshing;
  final GitError? lastError;

  RepoSessionState copyWith({
    bool? isOpen,
    model.RepoState? repoState,
    RefSnapshot? refs,
    GraphSnapshotView? graph,
    bool? isRefreshing,
    GitError? lastError,
    bool clearError = false,
  }) {
    return RepoSessionState(
      isOpen: isOpen ?? this.isOpen,
      repoState: repoState ?? this.repoState,
      refs: refs ?? this.refs,
      graph: graph ?? this.graph,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastError: clearError ? null : (lastError ?? this.lastError),
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
