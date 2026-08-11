import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/event_dispatcher.dart';
import '../ffi/gbm_bindings.dart';
import '../ffi/json_codec.dart';
import '../models/blame_result.dart';
import '../models/file_history_entry.dart';
import '../models/git_error.dart';
import '../models/graph_snapshot.dart';
import '../models/line_history_chunk.dart';
import '../models/operation_record.dart';
import '../models/parsed_diff.dart';
import '../models/ref_snapshot.dart';
import '../models/reflog_entry.dart';
import '../models/remote_info.dart';
import '../models/repo_state.dart' as model;
import '../models/stash_entry.dart';
import '../models/undo_entry.dart';
import '../models/working_copy_status.dart';
import '../models/worktree_info.dart';
import 'gbm_bindings_provider.dart';
import 'repo_identity.dart';

/// Mirrors `gbm::ResetMode` (src/core/git/ops/ResetOps.h) -- ordinal order
/// matters, it is passed straight through to `gbm_reset_to`.
enum ResetMode { soft, mixed, hard }

/// Mirrors `gbm::MergeMode` (src/core/git/ops/MergeOps.h) -- ordinal order
/// matters, it is passed straight through to `gbm_merge_branch`.
enum MergeMode { fastForwardOnly, noFastForward, squash }

/// Mirrors `gbm::ConflictResolution` (src/core/git/ops/ConflictOps.h) --
/// ordinal order matters, it is passed straight through to
/// `gbm_resolve_conflict`.
enum ConflictResolution { takeOurs, takeTheirs, markResolved, writeResolved }

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

/// Reply to [RepoSessionController.requestStashDiff]: mirrors
/// GBM_EVENT_STASH_DIFF_READY's payload shape.
class StashDiffReply {
  const StashDiffReply({required this.index, required this.diff});

  factory StashDiffReply.fromJson(Map<String, dynamic> json) {
    return StashDiffReply(index: json['index'] as int, diff: ParsedDiff.fromJson(json['diff'] as Map<String, dynamic>));
  }

  final int index;
  final ParsedDiff diff;
}

/// Caps how many [OperationRecord]s [RepoSessionState.operationLog] keeps,
/// mirroring OperationRunner's own undo-journal cap (`kMaxUndoEntries` in
/// OperationRunner.cpp) -- a live panel fed one record per `git` invocation
/// needs a bound too, or a long session slowly grows an unbounded list.
const int _kMaxOperationLogEntries = 500;

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
    this.stashes = const <StashEntry>[],
    this.lastStashDiff,
    this.worktrees = const <WorktreeInfo>[],
    this.remotes = const <RemoteInfo>[],
    this.credentialPrompt,
    this.operationLog = const <OperationRecord>[],
    this.lastBlame,
    this.lastFileHistory = const <FileHistoryEntry>[],
    this.lastLineHistory = const <LineHistoryChunk>[],
    this.lastReflog = const <ReflogEntry>[],
    this.undoJournal = const <UndoEntry>[],
  });

  final bool isOpen;
  final model.RepoState? repoState;
  final RefSnapshot refs;
  final GraphSnapshotView graph;
  final bool isRefreshing;
  final GitError? lastError;
  final WorkingCopyStatus workingCopyStatus;
  final WorkingCopyDiffReply? lastDiff;
  final List<StashEntry> stashes;
  final StashDiffReply? lastStashDiff;
  final List<WorktreeInfo> worktrees;
  final List<RemoteInfo> remotes;
  /// The prompt text of a credential request currently awaiting
  /// [RepoSessionController.provideCredential]/[RepoSessionController.cancelCredential],
  /// or null if none is outstanding. Cleared by either of those calls, not
  /// by an event -- gbm_capi has no "prompt answered" event, since the
  /// answer is this side's own action.
  final String? credentialPrompt;
  /// Newest-last, capped at [_kMaxOperationLogEntries].
  final List<OperationRecord> operationLog;
  final BlameResult? lastBlame;
  final List<FileHistoryEntry> lastFileHistory;
  final List<LineHistoryChunk> lastLineHistory;
  /// Newest-first -- see gbm_request_reflog()'s doc comment in gbm_capi.h.
  final List<ReflogEntry> lastReflog;
  /// Oldest-first, refreshed after every operation that can be undone --
  /// see Session::refreshUndoJournalCache()'s doc comment in Session.cpp for
  /// why this only ever changes right after GBM_EVENT_OPERATION_FINISHED /
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED.
  final List<UndoEntry> undoJournal;

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
    List<StashEntry>? stashes,
    StashDiffReply? lastStashDiff,
    List<WorktreeInfo>? worktrees,
    List<RemoteInfo>? remotes,
    String? credentialPrompt,
    bool clearCredentialPrompt = false,
    List<OperationRecord>? operationLog,
    BlameResult? lastBlame,
    List<FileHistoryEntry>? lastFileHistory,
    List<LineHistoryChunk>? lastLineHistory,
    List<ReflogEntry>? lastReflog,
    List<UndoEntry>? undoJournal,
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
      stashes: stashes ?? this.stashes,
      lastStashDiff: lastStashDiff ?? this.lastStashDiff,
      worktrees: worktrees ?? this.worktrees,
      remotes: remotes ?? this.remotes,
      credentialPrompt: clearCredentialPrompt ? null : (credentialPrompt ?? this.credentialPrompt),
      operationLog: operationLog ?? this.operationLog,
      lastBlame: lastBlame ?? this.lastBlame,
      lastFileHistory: lastFileHistory ?? this.lastFileHistory,
      lastLineHistory: lastLineHistory ?? this.lastLineHistory,
      lastReflog: lastReflog ?? this.lastReflog,
      undoJournal: undoJournal ?? this.undoJournal,
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
        _readUndoJournal();
      case GbmEventType.workingCopyStatusUpdated:
        _readWorkingCopyStatus();
      case GbmEventType.workingCopyOperationFinished:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic> && payload['succeeded'] == false) {
          final Object? error = payload['error'];
          state = state.copyWith(lastError: error is Map<String, dynamic> ? GitError.fromJson(error) : null);
        }
        _readUndoJournal();
      case GbmEventType.workingCopyDiffReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          state = state.copyWith(lastDiff: WorkingCopyDiffReply.fromJson(payload));
        }
      case GbmEventType.stashesUpdated:
        _readStashes();
      case GbmEventType.stashDiffReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          state = state.copyWith(lastStashDiff: StashDiffReply.fromJson(payload));
        }
      case GbmEventType.worktreesUpdated:
        _readWorktrees();
      case GbmEventType.remotesUpdated:
        _readRemotes();
      case GbmEventType.credentialRequested:
        final Object? payload = decodeEventPayload(event.payload);
        state = state.copyWith(
          credentialPrompt: payload is Map<String, dynamic> ? payload['prompt'] as String? ?? '' : '',
        );
      case GbmEventType.operationLogRecord:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          final List<OperationRecord> updated = <OperationRecord>[...state.operationLog, OperationRecord.fromJson(payload)];
          state = state.copyWith(
            operationLog: updated.length > _kMaxOperationLogEntries
                ? updated.sublist(updated.length - _kMaxOperationLogEntries)
                : updated,
          );
        }
      case GbmEventType.blameReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          state = state.copyWith(lastBlame: BlameResult.fromJson(payload));
        }
      case GbmEventType.fileHistoryReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is List<dynamic>) {
          state = state.copyWith(lastFileHistory: FileHistoryEntry.listFromJson(payload));
        }
      case GbmEventType.lineHistoryReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is List<dynamic>) {
          state = state.copyWith(lastLineHistory: LineHistoryChunk.listFromJson(payload));
        }
      case GbmEventType.reflogReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is List<dynamic>) {
          state = state.copyWith(lastReflog: ReflogEntry.listFromJson(payload));
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

  void _readStashes() {
    if (_bindings.stashesJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(stashes: StashEntry.listFromJson(jsonDecode(json) as List<dynamic>));
      }
    }
  }

  void _readWorktrees() {
    if (_bindings.worktreesJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(worktrees: WorktreeInfo.listFromJson(jsonDecode(json) as List<dynamic>));
      }
    }
  }

  void _readRemotes() {
    if (_bindings.remotesJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(remotes: RemoteInfo.listFromJson(jsonDecode(json) as List<dynamic>));
      }
    }
  }

  /// Synchronously re-reads the undo journal cache -- unlike the other
  /// `_read*` helpers this has no dedicated event; Session refreshes its
  /// cache as part of every operation's completion callback (see
  /// Session::refreshUndoJournalCache()'s doc comment), so this is called
  /// right after GBM_EVENT_OPERATION_FINISHED / GBM_EVENT_WORKING_COPY_OPERATION_FINISHED.
  void _readUndoJournal() {
    if (_bindings.undoJournalJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(undoJournal: UndoEntry.listFromJson(jsonDecode(json) as List<dynamic>));
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

  /// `git merge`. See gbm_merge_branch()'s doc comment in gbm_capi.h: a
  /// conflicting merge is reported through [state].lastError like any other
  /// outcome (error.code == conflict), not thrown -- the working copy is
  /// always refreshed so conflicted paths show up, history only on success.
  void mergeBranch(String target, MergeMode mode, {String message = '', bool stashFirst = false}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> targetPtr = target.toNativeUtf8();
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      _bindings.mergeBranch(_session, targetPtr, mode.index, messagePtr, stashFirst ? 1 : 0);
    } finally {
      malloc.free(targetPtr);
      malloc.free(messagePtr);
    }
  }

  /// `git merge --abort`.
  void mergeAbort() {
    if (_session == nullptr) return;
    _bindings.mergeAbort(_session);
  }

  /// `git cherry-pick`. `commitHexes` is oldest-first, the order commits are
  /// applied in. See gbm_cherry_pick()'s doc comment in gbm_capi.h: stops at
  /// the first conflict, leaving the rest queued for [cherryPickContinue]/
  /// [cherryPickSkip]/[cherryPickAbort].
  void cherryPick(List<String> commitHexes, {int mainline = 0, bool noCommit = false, bool stashFirst = false}) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      commitHexes,
      (array, count) => _bindings.cherryPick(_session, array, count, mainline, noCommit ? 1 : 0, stashFirst ? 1 : 0),
    );
  }

  void cherryPickContinue() {
    if (_session == nullptr) return;
    _bindings.cherryPickContinue(_session);
  }

  void cherryPickSkip() {
    if (_session == nullptr) return;
    _bindings.cherryPickSkip(_session);
  }

  void cherryPickAbort() {
    if (_session == nullptr) return;
    _bindings.cherryPickAbort(_session);
  }

  /// `git revert`. Same `commitHexes` convention as [cherryPick]. No
  /// continue/skip/abort entry point -- see gbm_revert()'s doc comment.
  void revert(List<String> commitHexes, {bool noCommit = false, bool stashFirst = false}) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      commitHexes,
      (array, count) => _bindings.revert(_session, array, count, noCommit ? 1 : 0, stashFirst ? 1 : 0),
    );
  }

  /// Resolves one conflicted path. See gbm_resolve_conflict()'s doc comment
  /// in gbm_capi.h for how `resolvedContent`/the blob-missing flags apply
  /// per [ConflictResolution] value. Async: fires
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED and refreshes the working
  /// copy on success.
  void resolveConflict(
    String path,
    ConflictResolution resolution, {
    bool oursBlobMissing = false,
    bool theirsBlobMissing = false,
    String resolvedContent = '',
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Utf8> resolvedContentPtr = resolvedContent.toNativeUtf8();
    try {
      _bindings.resolveConflict(
        _session,
        pathPtr,
        resolution.index,
        oursBlobMissing ? 1 : 0,
        theirsBlobMissing ? 1 : 0,
        resolvedContentPtr,
      );
    } finally {
      malloc.free(pathPtr);
      malloc.free(resolvedContentPtr);
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

  /// Async: see gbm_stash_refresh()'s doc comment in gbm_capi.h.
  void refreshStashes() {
    if (_session == nullptr) return;
    _bindings.stashRefresh(_session);
  }

  /// `git stash push`. `paths` restricts the stash to those paths, like
  /// [stageFiles]; empty stashes every changed path. Async: fires
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and on success refreshes
  /// both the working copy and the stash list.
  void saveStash(String message, {bool includeUntracked = false, bool keepIndex = false, List<String> paths = const <String>[]}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      _withNativeStringArray(
        paths,
        (array, count) =>
            _bindings.stashSave(_session, messagePtr, includeUntracked ? 1 : 0, keepIndex ? 1 : 0, array, count),
      );
    } finally {
      malloc.free(messagePtr);
    }
  }

  /// `git stash apply` (pop=false) or `git stash pop` (pop=true). See
  /// gbm_stash_apply()'s doc comment: the working copy is always refreshed,
  /// the stash list only on success.
  void applyStash(int index, {bool pop = false}) {
    if (_session == nullptr) return;
    _bindings.stashApply(_session, index, pop ? 1 : 0);
  }

  /// `git stash drop stash@{index}`.
  void dropStash(int index) {
    if (_session == nullptr) return;
    _bindings.stashDrop(_session, index);
  }

  /// `git stash branch`. See gbm_stash_branch()'s doc comment: on success
  /// refreshes the working copy, the stash list, and history.
  void branchFromStash(int index, String branchName) {
    if (_session == nullptr) return;
    final Pointer<Utf8> branchPtr = branchName.toNativeUtf8();
    try {
      _bindings.stashBranch(_session, index, branchPtr);
    } finally {
      malloc.free(branchPtr);
    }
  }

  /// `git stash show -p --include-untracked stash@{index}`. Async: fires
  /// GBM_EVENT_STASH_DIFF_READY.
  void requestStashDiff(int index) {
    if (_session == nullptr) return;
    _bindings.stashRequestDiff(_session, index);
  }

  /// `git tag`. `target` empty means HEAD; `message` non-empty makes it
  /// annotated. Async: fires GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and
  /// on success refreshes history (refs).
  void createTag(String name, {String target = '', String message = '', bool force = false}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> targetPtr = target.toNativeUtf8();
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      _bindings.tagCreate(_session, namePtr, targetPtr, messagePtr, force ? 1 : 0);
    } finally {
      malloc.free(namePtr);
      malloc.free(targetPtr);
      malloc.free(messagePtr);
    }
  }

  /// `git tag -d`, optionally followed by a remote delete when
  /// `alsoRemote` is set (routed through the same credential prompt as
  /// [fetchRemote] -- see [RepoSessionState.credentialPrompt]).
  void deleteTag(String name, {bool alsoRemote = false, String remoteName = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    try {
      _bindings.tagDelete(_session, namePtr, alsoRemote ? 1 : 0, remotePtr);
    } finally {
      malloc.free(namePtr);
      malloc.free(remotePtr);
    }
  }

  /// `git push <remoteName> <name>`, or every tag when `name` is empty.
  void pushTag(String remoteName, {String name = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    try {
      _bindings.tagPush(_session, remotePtr, namePtr);
    } finally {
      malloc.free(remotePtr);
      malloc.free(namePtr);
    }
  }

  /// Async: see gbm_worktree_refresh()'s doc comment in gbm_capi.h.
  void refreshWorktrees() {
    if (_session == nullptr) return;
    _bindings.worktreeRefresh(_session);
  }

  /// `git worktree add`. See gbm_worktree_add()'s doc comment: on success
  /// refreshes the worktree list.
  void addWorktree(
    String path, {
    String branch = '',
    bool createBranch = false,
    String newBranchName = '',
    bool detach = false,
    bool force = false,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Utf8> branchPtr = branch.toNativeUtf8();
    final Pointer<Utf8> newBranchPtr = newBranchName.toNativeUtf8();
    try {
      _bindings.worktreeAdd(
        _session,
        pathPtr,
        branchPtr,
        createBranch ? 1 : 0,
        newBranchPtr,
        detach ? 1 : 0,
        force ? 1 : 0,
      );
    } finally {
      malloc.free(pathPtr);
      malloc.free(branchPtr);
      malloc.free(newBranchPtr);
    }
  }

  void removeWorktree(String path, {bool force = false}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    try {
      _bindings.worktreeRemove(_session, pathPtr, force ? 1 : 0);
    } finally {
      malloc.free(pathPtr);
    }
  }

  void pruneWorktrees() {
    if (_session == nullptr) return;
    _bindings.worktreePrune(_session);
  }

  void lockWorktree(String path, {String reason = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Utf8> reasonPtr = reason.toNativeUtf8();
    try {
      _bindings.worktreeLock(_session, pathPtr, reasonPtr);
    } finally {
      malloc.free(pathPtr);
      malloc.free(reasonPtr);
    }
  }

  void unlockWorktree(String path) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    try {
      _bindings.worktreeUnlock(_session, pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Async: see gbm_remote_refresh()'s doc comment in gbm_capi.h.
  void refreshRemotes() {
    if (_session == nullptr) return;
    _bindings.remoteRefresh(_session);
  }

  /// `git fetch`. `remoteName` empty fetches every remote. Routes
  /// credential prompts through [RepoSessionState.credentialPrompt] -- see
  /// gbm_remote_fetch()'s doc comment in gbm_capi.h. Async: fires
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and on success also
  /// refreshes history.
  void fetchRemote({String remoteName = '', bool prune = false, bool tags = false}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    try {
      _bindings.remoteFetch(_session, remotePtr, prune ? 1 : 0, tags ? 1 : 0);
    } finally {
      malloc.free(remotePtr);
    }
  }

  /// `git pull` (merge, or `--rebase` when `rebase` is set). `remoteName`
  /// empty uses the branch's configured upstream. See gbm_pull()'s doc
  /// comment: the working copy is always refreshed, history only on
  /// success.
  void pullChanges({String remoteName = '', String branch = '', bool rebase = false, bool stashFirst = false}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    final Pointer<Utf8> branchPtr = branch.toNativeUtf8();
    try {
      _bindings.pull(_session, remotePtr, branchPtr, rebase ? 1 : 0, stashFirst ? 1 : 0);
    } finally {
      malloc.free(remotePtr);
      malloc.free(branchPtr);
    }
  }

  /// `git push`, with `--force-with-lease` when `forceWithLease` is set --
  /// there is no plain `--force` (see gbm_push()'s doc comment). `branch`
  /// empty pushes the current branch.
  void pushChanges({
    String remoteName = '',
    String branch = '',
    bool setUpstream = false,
    bool pushTags = false,
    bool forceWithLease = false,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    final Pointer<Utf8> branchPtr = branch.toNativeUtf8();
    try {
      _bindings.push(_session, remotePtr, branchPtr, setUpstream ? 1 : 0, pushTags ? 1 : 0, forceWithLease ? 1 : 0);
    } finally {
      malloc.free(remotePtr);
      malloc.free(branchPtr);
    }
  }

  /// Answers the credential prompt in [RepoSessionState.credentialPrompt],
  /// if any, and clears it. A `git` subprocess can ask more than once per
  /// invocation (e.g. a password after a username), in which case
  /// [RepoSessionState.credentialPrompt] is set again for the follow-up.
  void provideCredential(String secret) {
    if (_session == nullptr) return;
    final Pointer<Utf8> secretPtr = secret.toNativeUtf8();
    try {
      _bindings.provideCredential(_session, secretPtr);
    } finally {
      malloc.free(secretPtr);
    }
    state = state.copyWith(clearCredentialPrompt: true);
  }

  /// Dismisses the outstanding credential prompt, if any, and clears it;
  /// the blocked `git` subprocess fails cleanly.
  void cancelCredential() {
    if (_session == nullptr) return;
    _bindings.cancelCredential(_session);
    state = state.copyWith(clearCredentialPrompt: true);
  }

  /// Empties [RepoSessionState.operationLog] -- the operation-log panel's
  /// "Clear" action (mirrors `OperationLogView::clearLog()`). Local to this
  /// session's in-memory list only; does not affect gbm::Log itself, which
  /// keeps no history of its own (see core/base/Logging.h).
  void clearOperationLog() {
    state = state.copyWith(operationLog: const <OperationRecord>[]);
  }

  /// `git blame`. `revision` empty blames from the working copy; `startLine`/
  /// `endLine` both 0 blames the whole file. Async: fires
  /// GBM_EVENT_BLAME_READY into [RepoSessionState.lastBlame]. A newer call
  /// supersedes an older still-queued one (see gbm_request_blame()'s doc
  /// comment in gbm_capi.h).
  void requestBlame(String path, {String revision = '', int startLine = 0, int endLine = 0}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Utf8> revisionPtr = revision.toNativeUtf8();
    try {
      _bindings.requestBlame(_session, pathPtr, revisionPtr, startLine, endLine);
    } finally {
      malloc.free(pathPtr);
      malloc.free(revisionPtr);
    }
  }

  /// `git log --follow` for one file. `startRevision` empty starts from
  /// HEAD. Async: fires GBM_EVENT_FILE_HISTORY_READY into
  /// [RepoSessionState.lastFileHistory].
  void requestFileHistory(String path, {String startRevision = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Utf8> startRevisionPtr = startRevision.toNativeUtf8();
    try {
      _bindings.requestFileHistory(_session, pathPtr, startRevisionPtr);
    } finally {
      malloc.free(pathPtr);
      malloc.free(startRevisionPtr);
    }
  }

  /// `git log -L startLine,endLine:path`. `startRevision` empty starts from
  /// HEAD. Async: fires GBM_EVENT_LINE_HISTORY_READY into
  /// [RepoSessionState.lastLineHistory].
  void requestLineHistory(String path, int startLine, int endLine, {String startRevision = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Utf8> startRevisionPtr = startRevision.toNativeUtf8();
    try {
      _bindings.requestLineHistory(_session, pathPtr, startLine, endLine, startRevisionPtr);
    } finally {
      malloc.free(pathPtr);
      malloc.free(startRevisionPtr);
    }
  }

  /// `git reflog show <ref>`. `ref` empty means HEAD. Async: fires
  /// GBM_EVENT_REFLOG_READY into [RepoSessionState.lastReflog], newest-first.
  void requestReflog({String ref = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> refPtr = ref.toNativeUtf8();
    try {
      _bindings.requestReflog(_session, refPtr);
    } finally {
      malloc.free(refPtr);
    }
  }

  /// Reverts the most recent entry in [RepoSessionState.undoJournal] (a
  /// no-op if it is empty). See gbm_undo_last()'s doc comment in
  /// gbm_capi.h: fires GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and on
  /// success refreshes both the working copy and history.
  void undoLast() {
    if (_session == nullptr) return;
    _bindings.undoLast(_session);
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
