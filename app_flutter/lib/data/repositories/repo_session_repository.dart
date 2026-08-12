import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/event_dispatcher.dart';
import '../ffi/gbm_bindings.dart';
import '../ffi/json_codec.dart';
import '../models/bisect_status.dart';
import '../models/blame_result.dart';
import '../models/clean_entry.dart';
import '../models/commit_meta.dart';
import '../models/file_history_entry.dart';
import '../models/git_error.dart';
import '../models/git_identity.dart';
import '../models/graph_snapshot.dart';
import '../models/lfs_state.dart';
import '../models/line_history_chunk.dart';
import '../models/operation_choice.dart';
import '../models/operation_record.dart';
import '../models/parsed_conflict_file.dart';
import '../models/parsed_diff.dart';
import '../models/rebase_todo_entry.dart';
import '../models/ref_snapshot.dart';
import '../models/reflog_entry.dart';
import '../models/remote_info.dart';
import '../models/repo_state.dart' as model;
import '../models/stash_entry.dart';
import '../models/submodule_info.dart';
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
  const WorkingCopyDiffReply({
    required this.path,
    required this.staged,
    required this.diff,
  });

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

/// Reply to [RepoSessionController.requestWorkingTreeContent]: mirrors
/// GBM_EVENT_WORKING_TREE_CONTENT_READY's payload shape.
class WorkingTreeContentReply {
  const WorkingTreeContentReply({
    required this.path,
    required this.content,
    required this.editable,
  });

  factory WorkingTreeContentReply.fromJson(Map<String, dynamic> json) {
    return WorkingTreeContentReply(
      path: json['path'] as String,
      content: json['content'] as String,
      editable: json['editable'] as bool,
    );
  }

  final String path;
  final String content;
  final bool editable;
}

/// Reply to [RepoSessionController.requestStashDiff]: mirrors
/// GBM_EVENT_STASH_DIFF_READY's payload shape.
class StashDiffReply {
  const StashDiffReply({required this.index, required this.diff});

  factory StashDiffReply.fromJson(Map<String, dynamic> json) {
    return StashDiffReply(
      index: json['index'] as int,
      diff: ParsedDiff.fromJson(json['diff'] as Map<String, dynamic>),
    );
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
    this.lastWorkingTreeContent,
    this.stashes = const <StashEntry>[],
    this.lastStashDiff,
    this.worktrees = const <WorktreeInfo>[],
    this.remotes = const <RemoteInfo>[],
    this.credentialPrompt,
    this.operationLog = const <OperationRecord>[],
    this.lastBlame,
    this.commitMetaCache = const <String, CommitMeta>{},
    this.lastFileHistory = const <FileHistoryEntry>[],
    this.lastLineHistory = const <LineHistoryChunk>[],
    this.lastReflog = const <ReflogEntry>[],
    this.undoJournal = const <UndoEntry>[],
    this.lastCleanPreview = const <CleanEntry>[],
    this.lastRebasePlan = const <RebaseTodoEntry>[],
    this.submodules = const <SubmoduleInfo>[],
    this.bisectStatus = BisectStatus.empty,
    this.lfsInstallation,
    this.lfsPatterns = const <String>[],
    this.lfsFiles = const <LfsFileInfo>[],
    this.localIdentity = LocalIdentity.empty,
    this.effectiveIdentity = EffectiveIdentity.empty,
    this.hasCommitGraph = false,
    this.lastCommitGraphWriteSucceeded,
    this.checkoutChoices = const <OperationChoice>[],
    this.deleteBranchChoices = const <OperationChoice>[],
  });

  final bool isOpen;
  final model.RepoState? repoState;
  final RefSnapshot refs;
  final GraphSnapshotView graph;
  final bool isRefreshing;
  final GitError? lastError;
  final WorkingCopyStatus workingCopyStatus;
  final WorkingCopyDiffReply? lastDiff;
  final WorkingTreeContentReply? lastWorkingTreeContent;
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

  /// Batch-fetched commit metadata (author/subject/body), keyed by oid and
  /// accumulated across every GBM_EVENT_COMMIT_META_READY reply rather than
  /// replaced -- unlike [lastBlame]/[lastFileHistory], a viewport scroll
  /// only ever asks for the newly-visible rows, so a later reply must add
  /// to this cache, not overwrite the rows fetched by an earlier one. See
  /// history_repository.dart's `commitMetaProvider`/`requestCommitMeta`.
  final Map<String, CommitMeta> commitMetaCache;
  final List<FileHistoryEntry> lastFileHistory;
  final List<LineHistoryChunk> lastLineHistory;

  /// Newest-first -- see gbm_request_reflog()'s doc comment in gbm_capi.h.
  final List<ReflogEntry> lastReflog;

  /// Oldest-first, refreshed after every operation that can be undone --
  /// see Session::refreshUndoJournalCache()'s doc comment in Session.cpp for
  /// why this only ever changes right after GBM_EVENT_OPERATION_FINISHED /
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED.
  final List<UndoEntry> undoJournal;
  final List<CleanEntry> lastCleanPreview;

  /// Oldest-first -- the order gbm_rebase_interactive_start()'s `todo`
  /// array is applied in, see RebasePlanner::plan()'s doc comment.
  final List<RebaseTodoEntry> lastRebasePlan;
  final List<SubmoduleInfo> submodules;
  final BisectStatus bisectStatus;

  /// Null until [RepoSessionController.refreshLfs] has run once -- see
  /// gbm_lfs_installation_json()'s doc comment in gbm_capi.h.
  final LfsInstallation? lfsInstallation;
  final List<String> lfsPatterns;
  final List<LfsFileInfo> lfsFiles;
  final LocalIdentity localIdentity;
  final EffectiveIdentity effectiveIdentity;

  /// Filesystem check, refreshed by [RepoSessionController.refreshHasCommitGraph]
  /// and again after [RepoSessionController.writeCommitGraph] succeeds.
  final bool hasCommitGraph;

  /// Null until the first gbm_write_commit_graph() reply arrives this
  /// session.
  final bool? lastCommitGraphWriteSucceeded;

  /// Recovery choices (e.g. "Stash changes and checkout") from the most
  /// recently attempted [RepoSessionController.checkout] call, if it failed
  /// with any -- empty otherwise. See RepoSessionController.checkout()'s
  /// doc comment for how these map back to a retried checkout.
  final List<OperationChoice> checkoutChoices;

  /// Recovery choices (e.g. "Force delete") from the most recently
  /// attempted [RepoSessionController.deleteBranch] call, if it failed with
  /// any -- empty otherwise. Mirrors [checkoutChoices]; see
  /// RepoSessionController.deleteBranch()'s doc comment for how these map
  /// back to a retried delete.
  final List<OperationChoice> deleteBranchChoices;

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
    WorkingTreeContentReply? lastWorkingTreeContent,
    List<StashEntry>? stashes,
    StashDiffReply? lastStashDiff,
    List<WorktreeInfo>? worktrees,
    List<RemoteInfo>? remotes,
    String? credentialPrompt,
    bool clearCredentialPrompt = false,
    List<OperationRecord>? operationLog,
    BlameResult? lastBlame,
    Map<String, CommitMeta>? commitMetaCache,
    List<FileHistoryEntry>? lastFileHistory,
    List<LineHistoryChunk>? lastLineHistory,
    List<ReflogEntry>? lastReflog,
    List<UndoEntry>? undoJournal,
    List<CleanEntry>? lastCleanPreview,
    List<RebaseTodoEntry>? lastRebasePlan,
    List<SubmoduleInfo>? submodules,
    BisectStatus? bisectStatus,
    LfsInstallation? lfsInstallation,
    List<String>? lfsPatterns,
    List<LfsFileInfo>? lfsFiles,
    LocalIdentity? localIdentity,
    EffectiveIdentity? effectiveIdentity,
    bool? hasCommitGraph,
    bool? lastCommitGraphWriteSucceeded,
    List<OperationChoice>? checkoutChoices,
    List<OperationChoice>? deleteBranchChoices,
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
      lastWorkingTreeContent:
          lastWorkingTreeContent ?? this.lastWorkingTreeContent,
      stashes: stashes ?? this.stashes,
      lastStashDiff: lastStashDiff ?? this.lastStashDiff,
      worktrees: worktrees ?? this.worktrees,
      remotes: remotes ?? this.remotes,
      credentialPrompt: clearCredentialPrompt
          ? null
          : (credentialPrompt ?? this.credentialPrompt),
      operationLog: operationLog ?? this.operationLog,
      lastBlame: lastBlame ?? this.lastBlame,
      commitMetaCache: commitMetaCache ?? this.commitMetaCache,
      lastFileHistory: lastFileHistory ?? this.lastFileHistory,
      lastLineHistory: lastLineHistory ?? this.lastLineHistory,
      lastReflog: lastReflog ?? this.lastReflog,
      undoJournal: undoJournal ?? this.undoJournal,
      lastCleanPreview: lastCleanPreview ?? this.lastCleanPreview,
      lastRebasePlan: lastRebasePlan ?? this.lastRebasePlan,
      submodules: submodules ?? this.submodules,
      bisectStatus: bisectStatus ?? this.bisectStatus,
      lfsInstallation: lfsInstallation ?? this.lfsInstallation,
      lfsPatterns: lfsPatterns ?? this.lfsPatterns,
      lfsFiles: lfsFiles ?? this.lfsFiles,
      localIdentity: localIdentity ?? this.localIdentity,
      effectiveIdentity: effectiveIdentity ?? this.effectiveIdentity,
      hasCommitGraph: hasCommitGraph ?? this.hasCommitGraph,
      lastCommitGraphWriteSucceeded:
          lastCommitGraphWriteSucceeded ?? this.lastCommitGraphWriteSucceeded,
      checkoutChoices: checkoutChoices ?? this.checkoutChoices,
      deleteBranchChoices: deleteBranchChoices ?? this.deleteBranchChoices,
    );
  }
}

/// Owns one `gbm_capi` session handle end to end: opens it, subscribes to
/// its events, and closes it on dispose. One instance per open repository
/// (`workspaceScreen`'s route scope owns the provider lifetime -- see the
/// routing table in the plan).
class RepoSessionController extends StateNotifier<RepoSessionState> {
  RepoSessionController(this._bindings, this._identity)
    : super(const RepoSessionState()) {
    _open();
  }

  final GbmBindings _bindings;
  final RepoIdentity _identity;
  Pointer<Void> _session = nullptr;
  GbmSessionEvents? _events;
  StreamSubscription<GbmEvent>? _subscription;

  /// Remembers the most recently attempted [checkout] call, so a recovery
  /// choice picked from [RepoSessionState.checkoutChoices] can resubmit the
  /// same request with `stashFirst`/`force` set -- mirrors
  /// `MainWindow::checkoutBranch()`'s own `[this, request]` retry closure in
  /// the Qt app, just as a handful of remembered fields instead of a
  /// captured request struct. `operations_` on the C++ side is a single
  /// serial worker, so only one operation is ever actually in flight at a
  /// time -- these do not need to be tagged with a request id to stay
  /// correctly paired with the outcome that answers them.
  bool _awaitingCheckoutOutcome = false;
  String? _lastCheckoutTarget;
  bool _lastCheckoutDetach = false;
  bool _lastCheckoutCreateBranch = false;
  String _lastCheckoutNewBranchName = '';

  /// Same remembered-request idea as the checkout fields above, for the
  /// [deleteBranch] "not fully merged" -> "Force delete" recovery flow.
  bool _awaitingDeleteBranchOutcome = false;
  List<String> _lastDeleteBranchNames = const <String>[];
  bool _lastDeleteBranchIsRemote = false;
  String _lastDeleteBranchRemoteName = '';

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
        final bool complete = payload is Map<String, dynamic>
            ? payload['complete'] as bool? ?? false
            : false;
        state = state.copyWith(
          graph: readGraphSnapshot(_bindings, _session),
          isRefreshing: !complete,
        );
      case GbmEventType.errorOccurred:
        final Object? payload = decodeEventPayload(event.payload);
        state = state.copyWith(
          isRefreshing: false,
          lastError: payload is Map<String, dynamic>
              ? GitError.fromJson(payload)
              : null,
        );
      case GbmEventType.operationFinished:
        _readRepoState();
        _readUndoJournal();
        final Object? decoded = decodeEventPayload(event.payload);
        final Map<String, dynamic>? payload = decoded is Map<String, dynamic>
            ? decoded
            : null;
        bool succeeded = true;
        List<OperationChoice> choices = const <OperationChoice>[];
        if (payload != null) {
          succeeded = payload['succeeded'] as bool? ?? true;
          if (!succeeded) {
            final Object? choicesJson = payload['choices'];
            if (choicesJson is List<dynamic>) {
              choices = OperationChoice.listFromJson(choicesJson);
            }
            // Not every failure carries a formal GitError -- BranchOps'
            // "not fully merged" path (see refineSummaryFromRemoteRefs in
            // core/git/ops/BranchOps.cpp) only sets `summary` + `choices`,
            // deliberately preferring a friendlier message over a raw Git
            // error. Falling back to `summary` here is the only way that
            // message (or any other choices-only failure) reaches the UI.
            final GitError? error = _errorFromOutcomePayload(payload);
            if (error != null) {
              state = state.copyWith(lastError: error);
            }
          }
        }
        final bool wasCheckout = _awaitingCheckoutOutcome;
        _awaitingCheckoutOutcome = false;
        if (wasCheckout) {
          state = state.copyWith(
            checkoutChoices: succeeded ? const <OperationChoice>[] : choices,
          );
        }
        final bool wasDeleteBranch = _awaitingDeleteBranchOutcome;
        _awaitingDeleteBranchOutcome = false;
        if (wasDeleteBranch) {
          state = state.copyWith(
            deleteBranchChoices: succeeded
                ? const <OperationChoice>[]
                : choices,
          );
        }
      case GbmEventType.workingCopyStatusUpdated:
        _readWorkingCopyStatus();
      case GbmEventType.workingCopyOperationFinished:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic> && payload['succeeded'] == false) {
          final Object? error = payload['error'];
          state = state.copyWith(
            lastError: error is Map<String, dynamic>
                ? GitError.fromJson(error)
                : null,
          );
        }
        _readUndoJournal();
      case GbmEventType.workingCopyDiffReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          state = state.copyWith(
            lastDiff: WorkingCopyDiffReply.fromJson(payload),
          );
        }
      case GbmEventType.workingTreeContentReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          state = state.copyWith(
            lastWorkingTreeContent: WorkingTreeContentReply.fromJson(payload),
          );
        }
      case GbmEventType.stashesUpdated:
        _readStashes();
      case GbmEventType.stashDiffReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          state = state.copyWith(
            lastStashDiff: StashDiffReply.fromJson(payload),
          );
        }
      case GbmEventType.worktreesUpdated:
        _readWorktrees();
      case GbmEventType.remotesUpdated:
        _readRemotes();
      case GbmEventType.credentialRequested:
        final Object? payload = decodeEventPayload(event.payload);
        state = state.copyWith(
          credentialPrompt: payload is Map<String, dynamic>
              ? payload['prompt'] as String? ?? ''
              : '',
        );
      case GbmEventType.operationLogRecord:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          final List<OperationRecord> updated = <OperationRecord>[
            ...state.operationLog,
            OperationRecord.fromJson(payload),
          ];
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
      case GbmEventType.commitMetaReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is List<dynamic>) {
          final List<CommitMeta> metas = CommitMeta.listFromJson(payload);
          if (metas.isNotEmpty) {
            state = state.copyWith(
              commitMetaCache: <String, CommitMeta>{
                ...state.commitMetaCache,
                for (final CommitMeta meta in metas) meta.oid: meta,
              },
            );
          }
        }
      case GbmEventType.fileHistoryReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is List<dynamic>) {
          state = state.copyWith(
            lastFileHistory: FileHistoryEntry.listFromJson(payload),
          );
        }
      case GbmEventType.lineHistoryReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is List<dynamic>) {
          state = state.copyWith(
            lastLineHistory: LineHistoryChunk.listFromJson(payload),
          );
        }
      case GbmEventType.reflogReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is List<dynamic>) {
          state = state.copyWith(lastReflog: ReflogEntry.listFromJson(payload));
        }
      case GbmEventType.rebasePlanReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is List<dynamic>) {
          state = state.copyWith(
            lastRebasePlan: RebaseTodoEntry.listFromJson(payload),
          );
        }
      case GbmEventType.submodulesUpdated:
        _readSubmodules();
      case GbmEventType.bisectStatusUpdated:
        _readBisectStatus();
      case GbmEventType.lfsUpdated:
        _readLfsState();
      case GbmEventType.cleanPreviewReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is List<dynamic>) {
          state = state.copyWith(
            lastCleanPreview: CleanEntry.listFromJson(payload),
          );
        }
      case GbmEventType.localIdentityUpdated:
        _readLocalIdentity();
      case GbmEventType.effectiveIdentityUpdated:
        _readEffectiveIdentity();
      case GbmEventType.commitGraphWriteFinished:
        final Object? payload = decodeEventPayload(event.payload);
        final bool succeeded = payload is Map<String, dynamic>
            ? payload['succeeded'] as bool? ?? false
            : false;
        state = state.copyWith(
          lastCommitGraphWriteSucceeded: succeeded,
          hasCommitGraph: succeeded ? true : state.hasCommitGraph,
        );
    }
  }

  void _readRepoState() {
    if (_bindings.repoStateJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          repoState: model.RepoState.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          ),
        );
      }
    }
  }

  void _readRefs() {
    if (_bindings.refsJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          refs: RefSnapshot.fromJson(jsonDecode(json) as Map<String, dynamic>),
        );
      }
    }
  }

  void _readWorkingCopyStatus() {
    if (_bindings.workingCopyStatusJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          workingCopyStatus: WorkingCopyStatus.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          ),
        );
      }
    }
  }

  void _readStashes() {
    if (_bindings.stashesJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          stashes: StashEntry.listFromJson(jsonDecode(json) as List<dynamic>),
        );
      }
    }
  }

  void _readWorktrees() {
    if (_bindings.worktreesJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          worktrees: WorktreeInfo.listFromJson(
            jsonDecode(json) as List<dynamic>,
          ),
        );
      }
    }
  }

  void _readRemotes() {
    if (_bindings.remotesJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          remotes: RemoteInfo.listFromJson(jsonDecode(json) as List<dynamic>),
        );
      }
    }
  }

  void _readSubmodules() {
    if (_bindings.submodulesJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          submodules: SubmoduleInfo.listFromJson(
            jsonDecode(json) as List<dynamic>,
          ),
        );
      }
    }
  }

  void _readBisectStatus() {
    if (_bindings.bisectStatusJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          bisectStatus: BisectStatus.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          ),
        );
      }
    }
  }

  /// Reads whichever of installation/patterns/files gbm_lfs_refresh() ended
  /// up publishing -- patterns/files stay as they were (or unset) when
  /// `available` is false, see Session::refreshLfs()'s doc comment in
  /// Session.cpp, so each of the three is read independently rather than
  /// failing this whole helper when one of them has nothing published yet.
  void _readLfsState() {
    if (_bindings.lfsInstallationJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          lfsInstallation: LfsInstallation.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          ),
        );
      }
    }
    if (_bindings.lfsPatternsJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          lfsPatterns: (jsonDecode(json) as List<dynamic>).cast<String>(),
        );
      }
    }
    if (_bindings.lfsFilesJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          lfsFiles: LfsFileInfo.listFromJson(jsonDecode(json) as List<dynamic>),
        );
      }
    }
  }

  void _readLocalIdentity() {
    if (_bindings.localIdentityJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          localIdentity: LocalIdentity.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          ),
        );
      }
    }
  }

  void _readEffectiveIdentity() {
    if (_bindings.effectiveIdentityJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          effectiveIdentity: EffectiveIdentity.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          ),
        );
      }
    }
  }

  /// Builds a [GitError] to surface for a failed [OperationOutcome] payload,
  /// falling back to `summary` (a synthetic `code`/`codeName`/`exitCode`)
  /// when the outcome carries no formal `error` -- see the doc comment
  /// where this is called from [_onEvent]'s `operationFinished` case.
  GitError? _errorFromOutcomePayload(Map<String, dynamic> payload) {
    final Object? error = payload['error'];
    if (error is Map<String, dynamic>) {
      return GitError.fromJson(error);
    }
    final String summary = payload['summary'] as String? ?? '';
    if (summary.isEmpty) return null;
    return GitError(
      code: -1,
      codeName: 'OperationFailed',
      message: summary,
      detail: '',
      argv: const <String>[],
      exitCode: -1,
    );
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
        state = state.copyWith(
          undoJournal: UndoEntry.listFromJson(
            jsonDecode(json) as List<dynamic>,
          ),
        );
      }
    }
  }

  GitError? _decodeLastError() {
    final String json = readLastResultJson(_bindings);
    return json.isEmpty
        ? null
        : GitError.fromJson(jsonDecode(json) as Map<String, dynamic>);
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
  /// gbm_capi.h for the target/createBranch/newBranchName relationship. A
  /// checkout refused because the work tree is dirty is not itself an
  /// error: it reports `succeeded: false` with recovery
  /// [OperationChoice]s (e.g. stash-and-retry) in
  /// [RepoSessionState.checkoutChoices] instead -- see
  /// [retryCheckoutWithChoice] for how a chosen one resubmits this same
  /// call with `stashFirst`/`force` set.
  void checkout({
    required String target,
    bool detach = false,
    bool createBranch = false,
    String newBranchName = '',
    bool force = false,
    bool stashFirst = false,
    bool recurseSubmodules = false,
  }) {
    if (_session == nullptr) return;
    _awaitingCheckoutOutcome = true;
    _lastCheckoutTarget = target;
    _lastCheckoutDetach = detach;
    _lastCheckoutCreateBranch = createBranch;
    _lastCheckoutNewBranchName = newBranchName;
    final Pointer<Utf8> targetPtr = target.toNativeUtf8();
    final Pointer<Utf8> newBranchPtr = newBranchName.toNativeUtf8();
    try {
      _bindings.branchCheckout(
        _session,
        targetPtr,
        detach ? 1 : 0,
        createBranch ? 1 : 0,
        newBranchPtr,
        force ? 1 : 0,
        stashFirst ? 1 : 0,
        recurseSubmodules ? 1 : 0,
      );
    } finally {
      malloc.free(targetPtr);
      malloc.free(newBranchPtr);
    }
  }

  /// Resubmits the most recently attempted [checkout] with the flag
  /// [kind] implies (stash-and-retry -> `stashFirst`, force-discard ->
  /// `force`); any other kind (Abort/Cancel) just dismisses
  /// [RepoSessionState.checkoutChoices]. A no-op if no checkout has been
  /// attempted yet this session.
  void retryCheckoutWithChoice(OperationChoiceKind kind) {
    final String? target = _lastCheckoutTarget;
    state = state.copyWith(checkoutChoices: const <OperationChoice>[]);
    if (target == null) return;
    switch (kind) {
      case OperationChoiceKind.stashAndRetry:
        checkout(
          target: target,
          detach: _lastCheckoutDetach,
          createBranch: _lastCheckoutCreateBranch,
          newBranchName: _lastCheckoutNewBranchName,
          stashFirst: true,
        );
      case OperationChoiceKind.forceDiscard:
        checkout(
          target: target,
          detach: _lastCheckoutDetach,
          createBranch: _lastCheckoutCreateBranch,
          newBranchName: _lastCheckoutNewBranchName,
          force: true,
        );
      case OperationChoiceKind.abort:
      case OperationChoiceKind.retry:
      case OperationChoiceKind.removeLock:
        break;
    }
  }

  /// Dismisses [RepoSessionState.checkoutChoices] without retrying --
  /// the explicit Cancel action.
  void dismissCheckoutChoices() {
    state = state.copyWith(checkoutChoices: const <OperationChoice>[]);
  }

  /// `git branch <name> [<startPoint>]`, optionally checking it out and/or
  /// setting an upstream. `startPoint` empty means HEAD. Async: a failure
  /// surfaces through [RepoSessionState.lastError], and on success this
  /// refreshes refs (and history, if [checkoutAfter] moved HEAD).
  void createBranch({
    required String name,
    String startPoint = '',
    bool checkoutAfter = false,
    bool setUpstream = false,
    String upstream = '',
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> startPointPtr = startPoint.toNativeUtf8();
    final Pointer<Utf8> upstreamPtr = upstream.toNativeUtf8();
    try {
      _bindings.branchCreate(
        _session,
        namePtr,
        startPointPtr,
        checkoutAfter ? 1 : 0,
        setUpstream ? 1 : 0,
        upstreamPtr,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(startPointPtr);
      malloc.free(upstreamPtr);
    }
  }

  /// `git branch -m <from> <to>` (`-M` when [force]). Async, refreshes refs
  /// on success.
  void renameBranch({
    required String from,
    required String to,
    bool force = false,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> fromPtr = from.toNativeUtf8();
    final Pointer<Utf8> toPtr = to.toNativeUtf8();
    try {
      _bindings.branchRename(_session, fromPtr, toPtr, force ? 1 : 0);
    } finally {
      malloc.free(fromPtr);
      malloc.free(toPtr);
    }
  }

  /// `git branch -d`/`-D` with the given names (multiple names in one call
  /// -- a multi-select delete is one operation, not N), or `git push
  /// --delete` against `remoteName` when [isRemote]. [force] deletes even
  /// when not fully merged. Async, refreshes refs on success; when Git
  /// refuses because a branch is not fully merged, the friendly summary
  /// core already computes (see BranchOps.cpp's `refineSummaryFromRemoteRefs`)
  /// lands in [RepoSessionState.lastError] and a "Force delete" choice
  /// lands in [RepoSessionState.deleteBranchChoices] -- see
  /// [retryDeleteBranchWithChoice] for how a chosen one resubmits this same
  /// call with `force` set.
  void deleteBranch({
    required List<String> names,
    bool force = false,
    bool isRemote = false,
    String remoteName = '',
  }) {
    if (_session == nullptr || names.isEmpty) return;
    _awaitingDeleteBranchOutcome = true;
    _lastDeleteBranchNames = names;
    _lastDeleteBranchIsRemote = isRemote;
    _lastDeleteBranchRemoteName = remoteName;
    final Pointer<Utf8> remoteNamePtr = remoteName.toNativeUtf8();
    try {
      _withNativeStringArray(
        names,
        (array, count) => _bindings.branchDelete(
          _session,
          array,
          count,
          force ? 1 : 0,
          isRemote ? 1 : 0,
          remoteNamePtr,
        ),
      );
    } finally {
      malloc.free(remoteNamePtr);
    }
  }

  /// Resubmits the most recently attempted [deleteBranch] with `force` set
  /// when [kind] is [OperationChoiceKind.forceDiscard]; any other kind just
  /// dismisses [RepoSessionState.deleteBranchChoices]. A no-op if no delete
  /// has been attempted yet this session.
  void retryDeleteBranchWithChoice(OperationChoiceKind kind) {
    final List<String> names = _lastDeleteBranchNames;
    state = state.copyWith(deleteBranchChoices: const <OperationChoice>[]);
    if (names.isEmpty) return;
    switch (kind) {
      case OperationChoiceKind.forceDiscard:
        deleteBranch(
          names: names,
          force: true,
          isRemote: _lastDeleteBranchIsRemote,
          remoteName: _lastDeleteBranchRemoteName,
        );
      case OperationChoiceKind.stashAndRetry:
      case OperationChoiceKind.abort:
      case OperationChoiceKind.retry:
      case OperationChoiceKind.removeLock:
        break;
    }
  }

  /// Dismisses [RepoSessionState.deleteBranchChoices] without retrying --
  /// the explicit Cancel action.
  void dismissDeleteBranchChoices() {
    state = state.copyWith(deleteBranchChoices: const <OperationChoice>[]);
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
  void mergeBranch(
    String target,
    MergeMode mode, {
    String message = '',
    bool stashFirst = false,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> targetPtr = target.toNativeUtf8();
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      _bindings.mergeBranch(
        _session,
        targetPtr,
        mode.index,
        messagePtr,
        stashFirst ? 1 : 0,
      );
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
  void cherryPick(
    List<String> commitHexes, {
    int mainline = 0,
    bool noCommit = false,
    bool stashFirst = false,
  }) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      commitHexes,
      (array, count) => _bindings.cherryPick(
        _session,
        array,
        count,
        mainline,
        noCommit ? 1 : 0,
        stashFirst ? 1 : 0,
      ),
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
  void revert(
    List<String> commitHexes, {
    bool noCommit = false,
    bool stashFirst = false,
  }) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      commitHexes,
      (array, count) => _bindings.revert(
        _session,
        array,
        count,
        noCommit ? 1 : 0,
        stashFirst ? 1 : 0,
      ),
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

  /// Reads a conflicted path's raw on-disk content (conflict markers and
  /// all) for the resolve editor. Async: see
  /// gbm_request_working_tree_content()'s doc comment in gbm_capi.h --
  /// [RepoSessionState.lastWorkingTreeContent] updates on reply.
  void requestWorkingTreeContent(String path) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    try {
      _bindings.requestWorkingTreeContent(_session, pathPtr);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Splits `content` (typically a [requestWorkingTreeContent] reply) into
  /// plain-text and per-region conflict segments. Synchronous and
  /// session-independent -- see gbm_parse_conflict_markers()'s doc comment
  /// in gbm_capi.h -- so this returns its result directly rather than going
  /// through [state].
  ParsedConflictFile parseConflictMarkers(String content) {
    final Pointer<Utf8> contentPtr = content.toNativeUtf8();
    try {
      _bindings.parseConflictMarkers(contentPtr);
    } finally {
      malloc.free(contentPtr);
    }
    final String json = readLastResultJson(_bindings);
    return json.isEmpty
        ? ParsedConflictFile.empty
        : ParsedConflictFile.fromJson(jsonDecode(json) as Map<String, dynamic>);
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
    _withNativeStringArray(
      paths,
      (array, count) => _bindings.stageFiles(_session, array, count),
    );
  }

  /// `git restore --staged -- <paths>`. Same event/refresh contract as
  /// [stageFiles].
  void unstageFiles(List<String> paths) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      paths,
      (array, count) => _bindings.unstageFiles(_session, array, count),
    );
  }

  /// Stages a single hunk (0-based `hunkIndex`, in the order the most recent
  /// unstaged diff for `path` listed them) via `git apply --cached` against
  /// a freshly-recomputed diff -- see gbm_stage_hunk()'s doc comment in
  /// gbm_capi.h. Same event/refresh contract as [stageFiles]; a `hunkIndex`
  /// that no longer exists (the file changed since it was last diffed)
  /// surfaces as a failed outcome through [RepoSessionState.lastError].
  void stageHunk(String path, int hunkIndex) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    try {
      _bindings.stageHunk(_session, pathPtr, hunkIndex);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// The reverse of [stageHunk]: `hunkIndex` indexes into `path`'s *staged*
  /// diff instead. Same event/refresh contract as [stageFiles].
  void unstageHunk(String path, int hunkIndex) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    try {
      _bindings.unstageHunk(_session, pathPtr, hunkIndex);
    } finally {
      malloc.free(pathPtr);
    }
  }

  /// Like [stageHunk], but stages only a subset of that hunk's added/
  /// removed lines -- `lineIndices` index into the hunk's `lines` array
  /// (context and no-newline-marker lines always pass through regardless).
  /// Same event/refresh contract as [stageFiles].
  void stageLines(String path, int hunkIndex, List<int> lineIndices) {
    if (_session == nullptr || lineIndices.isEmpty) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Int32> indices = malloc<Int32>(lineIndices.length);
    try {
      for (int i = 0; i < lineIndices.length; i++) {
        indices[i] = lineIndices[i];
      }
      _bindings.stageLines(
        _session,
        pathPtr,
        hunkIndex,
        indices,
        lineIndices.length,
      );
    } finally {
      malloc.free(pathPtr);
      malloc.free(indices);
    }
  }

  /// The reverse of [stageLines]: `hunkIndex`/`lineIndices` index into
  /// `path`'s *staged* diff instead. Same event/refresh contract as
  /// [stageFiles].
  void unstageLines(String path, int hunkIndex, List<int> lineIndices) {
    if (_session == nullptr || lineIndices.isEmpty) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Int32> indices = malloc<Int32>(lineIndices.length);
    try {
      for (int i = 0; i < lineIndices.length; i++) {
        indices[i] = lineIndices[i];
      }
      _bindings.unstageLines(
        _session,
        pathPtr,
        hunkIndex,
        indices,
        lineIndices.length,
      );
    } finally {
      malloc.free(pathPtr);
      malloc.free(indices);
    }
  }

  /// `git commit` / `git commit --amend`. Async: fires
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and on success also
  /// refreshes both the working copy and the history graph (the new commit
  /// needs to appear there).
  void commit(String message, {bool amend = false, bool signOff = false}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      _bindings.commitChanges(
        _session,
        messagePtr,
        amend ? 1 : 0,
        signOff ? 1 : 0,
      );
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
  void saveStash(
    String message, {
    bool includeUntracked = false,
    bool keepIndex = false,
    List<String> paths = const <String>[],
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      _withNativeStringArray(
        paths,
        (array, count) => _bindings.stashSave(
          _session,
          messagePtr,
          includeUntracked ? 1 : 0,
          keepIndex ? 1 : 0,
          array,
          count,
        ),
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
  void createTag(
    String name, {
    String target = '',
    String message = '',
    bool force = false,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> targetPtr = target.toNativeUtf8();
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      _bindings.tagCreate(
        _session,
        namePtr,
        targetPtr,
        messagePtr,
        force ? 1 : 0,
      );
    } finally {
      malloc.free(namePtr);
      malloc.free(targetPtr);
      malloc.free(messagePtr);
    }
  }

  /// `git tag -d`, optionally followed by a remote delete when
  /// `alsoRemote` is set (routed through the same credential prompt as
  /// [fetchRemote] -- see [RepoSessionState.credentialPrompt]).
  void deleteTag(
    String name, {
    bool alsoRemote = false,
    String remoteName = '',
  }) {
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
  void fetchRemote({
    String remoteName = '',
    bool prune = false,
    bool tags = false,
  }) {
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
  void pullChanges({
    String remoteName = '',
    String branch = '',
    bool rebase = false,
    bool stashFirst = false,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    final Pointer<Utf8> branchPtr = branch.toNativeUtf8();
    try {
      _bindings.pull(
        _session,
        remotePtr,
        branchPtr,
        rebase ? 1 : 0,
        stashFirst ? 1 : 0,
      );
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
      _bindings.push(
        _session,
        remotePtr,
        branchPtr,
        setUpstream ? 1 : 0,
        pushTags ? 1 : 0,
        forceWithLease ? 1 : 0,
      );
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
  void requestBlame(
    String path, {
    String revision = '',
    int startLine = 0,
    int endLine = 0,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Utf8> revisionPtr = revision.toNativeUtf8();
    try {
      _bindings.requestBlame(
        _session,
        pathPtr,
        revisionPtr,
        startLine,
        endLine,
      );
    } finally {
      malloc.free(pathPtr);
      malloc.free(revisionPtr);
    }
  }

  /// Batch commit metadata for `oids` (e.g. a commit list's visible range).
  /// Async: fires GBM_EVENT_COMMIT_META_READY, merged into
  /// [RepoSessionState.commitMetaCache] rather than replacing it -- see that
  /// field's doc comment. Prefer history_repository.dart's
  /// `requestCommitMeta`, which dedupes against oids already cached before
  /// calling this.
  void requestCommitMeta(List<String> oids) {
    if (_session == nullptr || oids.isEmpty) return;
    _withNativeStringArray(
      oids,
      (array, count) => _bindings.requestCommitMeta(_session, array, count),
    );
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
  void requestLineHistory(
    String path,
    int startLine,
    int endLine, {
    String startRevision = '',
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Utf8> startRevisionPtr = startRevision.toNativeUtf8();
    try {
      _bindings.requestLineHistory(
        _session,
        pathPtr,
        startLine,
        endLine,
        startRevisionPtr,
      );
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

  /// `git restore`. `staged` (--staged): resets the index from `source`
  /// (default HEAD) without touching the work tree -- "unstage". Not
  /// staged: overwrites the work tree from `source` (default the index) --
  /// "discard changes", destructive exactly like [resetTo]'s hard mode
  /// restricted to these paths. Async: fires
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and on success refreshes
  /// the working copy.
  void restorePaths(
    List<String> paths, {
    bool staged = false,
    String source = '',
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> sourcePtr = source.toNativeUtf8();
    try {
      _withNativeStringArray(
        paths,
        (array, count) => _bindings.restorePaths(
          _session,
          array,
          count,
          staged ? 1 : 0,
          sourcePtr,
        ),
      );
    } finally {
      malloc.free(sourcePtr);
    }
  }

  /// Read-only `git clean -n[x]`. Async: fires
  /// GBM_EVENT_CLEAN_PREVIEW_READY into [RepoSessionState.lastCleanPreview].
  void requestCleanPreview({bool includeIgnored = false}) {
    if (_session == nullptr) return;
    _bindings.cleanPreview(_session, includeIgnored ? 1 : 0);
  }

  /// `git clean -fd[x]`. `paths` empty means the whole work tree. Async:
  /// fires GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and on success
  /// refreshes the working copy.
  void cleanUntracked({
    List<String> paths = const <String>[],
    bool includeIgnored = false,
  }) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      paths,
      (array, count) => _bindings.cleanUntracked(
        _session,
        array,
        count,
        includeIgnored ? 1 : 0,
      ),
    );
  }

  /// Builds the todo list a plain `git rebase -i <upstream>` would start
  /// from -- read-only, for the caller to show and let the user edit before
  /// calling [startInteractiveRebase]. Async: fires
  /// GBM_EVENT_REBASE_PLAN_READY into [RepoSessionState.lastRebasePlan].
  void requestRebasePlan(String upstream) {
    if (_session == nullptr) return;
    final Pointer<Utf8> upstreamPtr = upstream.toNativeUtf8();
    try {
      _bindings.requestRebasePlan(_session, upstreamPtr);
    } finally {
      malloc.free(upstreamPtr);
    }
  }

  /// `git rebase -i`, with `todo` supplied by the caller (typically
  /// [RepoSessionState.lastRebasePlan], reordered/edited/dropped) instead of
  /// through an interactive editor. `onto` empty means onto `upstream`
  /// itself. Async: fires GBM_EVENT_OPERATION_FINISHED; stops at the first
  /// conflict or `edit` line exactly like `git rebase -i`, leaving the rest
  /// queued for [continueRebase]/[skipRebase]/[abortRebase] -- the working
  /// copy is always refreshed, history only on success.
  void startInteractiveRebase(
    String upstream,
    List<RebaseTodoEntry> todo, {
    String onto = '',
    bool stashFirst = false,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> upstreamPtr = upstream.toNativeUtf8();
    final Pointer<Utf8> ontoPtr = onto.toNativeUtf8();
    final Pointer<Int32> actions = malloc<Int32>(todo.length);
    final Pointer<Pointer<Utf8>> oids = malloc<Pointer<Utf8>>(todo.length);
    final Pointer<Pointer<Utf8>> subjects = malloc<Pointer<Utf8>>(todo.length);
    try {
      for (int i = 0; i < todo.length; i++) {
        actions[i] = todo[i].action.index;
        oids[i] = todo[i].oid.toNativeUtf8();
        subjects[i] = todo[i].subject.toNativeUtf8();
      }
      _bindings.rebaseInteractiveStart(
        _session,
        upstreamPtr,
        ontoPtr,
        actions,
        oids,
        subjects,
        todo.length,
        stashFirst ? 1 : 0,
      );
    } finally {
      for (int i = 0; i < todo.length; i++) {
        malloc.free(oids[i]);
        malloc.free(subjects[i]);
      }
      malloc.free(actions);
      malloc.free(oids);
      malloc.free(subjects);
      malloc.free(upstreamPtr);
      malloc.free(ontoPtr);
    }
  }

  /// Plain, non-interactive `git rebase`: replays every commit unchanged.
  /// Same event/refresh contract as [startInteractiveRebase].
  void startRebase(
    String upstream, {
    String onto = '',
    bool stashFirst = false,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> upstreamPtr = upstream.toNativeUtf8();
    final Pointer<Utf8> ontoPtr = onto.toNativeUtf8();
    try {
      _bindings.rebaseStart(_session, upstreamPtr, ontoPtr, stashFirst ? 1 : 0);
    } finally {
      malloc.free(upstreamPtr);
      malloc.free(ontoPtr);
    }
  }

  void continueRebase() {
    if (_session == nullptr) return;
    _bindings.rebaseContinue(_session);
  }

  void skipRebase() {
    if (_session == nullptr) return;
    _bindings.rebaseSkip(_session);
  }

  void abortRebase() {
    if (_session == nullptr) return;
    _bindings.rebaseAbort(_session);
  }

  /// Async: see gbm_submodule_refresh()'s doc comment in gbm_capi.h.
  void refreshSubmodules() {
    if (_session == nullptr) return;
    _bindings.submoduleRefresh(_session);
  }

  /// `git submodule add [-b <branch>] <url> [<path>]`. `path` empty lets
  /// git derive it from the URL. Async: fires
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and on success refreshes
  /// both the working copy and the submodule list. Routes credential
  /// prompts through [RepoSessionState.credentialPrompt] like
  /// [fetchRemote], since this can clone over the network.
  void addSubmodule(String url, {String path = '', String branch = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> urlPtr = url.toNativeUtf8();
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Utf8> branchPtr = branch.toNativeUtf8();
    try {
      _bindings.submoduleAdd(_session, urlPtr, pathPtr, branchPtr);
    } finally {
      malloc.free(urlPtr);
      malloc.free(pathPtr);
      malloc.free(branchPtr);
    }
  }

  /// `git submodule init [--] <paths...>`. `paths` empty means every
  /// submodule.
  void initSubmodules({
    List<String> paths = const <String>[],
    bool recursive = false,
  }) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      paths,
      (array, count) =>
          _bindings.submoduleInit(_session, array, count, recursive ? 1 : 0),
    );
  }

  /// `git submodule update [--init] [--recursive] [--remote] [--] <paths...>`.
  /// Same credential-prompt routing as [addSubmodule].
  void updateSubmodules({
    List<String> paths = const <String>[],
    bool recursive = false,
    bool init = false,
    bool remote = false,
  }) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      paths,
      (array, count) => _bindings.submoduleUpdate(
        _session,
        array,
        count,
        recursive ? 1 : 0,
        init ? 1 : 0,
        remote ? 1 : 0,
      ),
    );
  }

  /// `git submodule sync [--recursive] [--] <paths...>`.
  void syncSubmodules({
    List<String> paths = const <String>[],
    bool recursive = false,
  }) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      paths,
      (array, count) =>
          _bindings.submoduleSync(_session, array, count, recursive ? 1 : 0),
    );
  }

  /// `git submodule deinit [-f] [--] <paths...>`.
  void deinitSubmodules({
    List<String> paths = const <String>[],
    bool force = false,
  }) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      paths,
      (array, count) =>
          _bindings.submoduleDeinit(_session, array, count, force ? 1 : 0),
    );
  }

  /// Async: see gbm_bisect_refresh()'s doc comment in gbm_capi.h.
  void refreshBisectStatus() {
    if (_session == nullptr) return;
    _bindings.bisectRefresh(_session);
  }

  /// `git bisect start [<bad> [<good>...]] [--] [<paths>...]`. `badRef`
  /// empty together with an empty `goodRefs` is valid (waits for
  /// [markBisect] afterward). Async: fires GBM_EVENT_OPERATION_FINISHED,
  /// and on success also refreshes both history (a bisect start checks out
  /// a commit) and [RepoSessionState.bisectStatus].
  void startBisect({
    String badRef = '',
    List<String> goodRefs = const <String>[],
    List<String> paths = const <String>[],
    bool noCheckout = false,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> badRefPtr = badRef.toNativeUtf8();
    try {
      _withNativeStringArray(
        goodRefs,
        (goodArray, goodCount) => _withNativeStringArray(
          paths,
          (pathArray, pathCount) => _bindings.bisectStart(
            _session,
            badRefPtr,
            goodArray,
            goodCount,
            pathArray,
            pathCount,
            noCheckout ? 1 : 0,
          ),
        ),
      );
    } finally {
      malloc.free(badRefPtr);
    }
  }

  /// `git bisect good|bad [<ref>]`. `ref` empty means HEAD. May conclude
  /// the bisect, in which case the outcome's summary carries git's own
  /// "is the first bad commit" message verbatim -- see
  /// [RepoSessionState.operationLog]/`workingCopyOperationFinished`'s
  /// payload for that summary.
  void markBisect({required bool good, String ref = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> refPtr = ref.toNativeUtf8();
    try {
      _bindings.bisectMark(_session, good ? 1 : 0, refPtr);
    } finally {
      malloc.free(refPtr);
    }
  }

  /// `git bisect skip [<refs...>]`. Empty `refs` skips HEAD.
  void skipBisect({List<String> refs = const <String>[]}) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      refs,
      (array, count) => _bindings.bisectSkip(_session, array, count),
    );
  }

  /// `git bisect reset [<target>]`. `target` empty returns to whatever
  /// [startBisect] was run from.
  void resetBisect({String target = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> targetPtr = target.toNativeUtf8();
    try {
      _bindings.bisectReset(_session, targetPtr);
    } finally {
      malloc.free(targetPtr);
    }
  }

  /// Detects `git-lfs` (once per session, cached) and re-reads tracked
  /// patterns and file status. Async: fires GBM_EVENT_LFS_UPDATED.
  void refreshLfs() {
    if (_session == nullptr) return;
    _bindings.lfsRefresh(_session);
  }

  /// `git lfs install --local`.
  void installLfs() {
    if (_session == nullptr) return;
    _bindings.lfsInstall(_session);
  }

  /// `git lfs track "<pattern>"`. Editing `.gitattributes` further
  /// (staging, committing) is left to the caller.
  void trackLfsPattern(String pattern) {
    if (_session == nullptr) return;
    final Pointer<Utf8> patternPtr = pattern.toNativeUtf8();
    try {
      _bindings.lfsTrack(_session, patternPtr);
    } finally {
      malloc.free(patternPtr);
    }
  }

  /// `git lfs untrack "<pattern>"`.
  void untrackLfsPattern(String pattern) {
    if (_session == nullptr) return;
    final Pointer<Utf8> patternPtr = pattern.toNativeUtf8();
    try {
      _bindings.lfsUntrack(_session, patternPtr);
    } finally {
      malloc.free(patternPtr);
    }
  }

  /// `git lfs pull [<remote>]`. `remoteName` empty uses the default remote.
  /// Same credential-prompt routing as [fetchRemote].
  void pullLfs({String remoteName = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    try {
      _bindings.lfsPull(_session, remotePtr);
    } finally {
      malloc.free(remotePtr);
    }
  }

  /// `git lfs fetch [<remote>]`: downloads objects without touching the
  /// work tree. Same credential-prompt routing as [fetchRemote].
  void fetchLfs({String remoteName = ''}) {
    if (_session == nullptr) return;
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    try {
      _bindings.lfsFetch(_session, remotePtr);
    } finally {
      malloc.free(remotePtr);
    }
  }

  /// `git lfs prune [--dry-run]`.
  void pruneLfs({bool dryRun = false}) {
    if (_session == nullptr) return;
    _bindings.lfsPrune(_session, dryRun ? 1 : 0);
  }

  /// `git format-patch -1 <commit> --start-number <n> -o <dir>`, once per
  /// commit in `commitHexes` (oldest first, same convention as
  /// [cherryPick]). Async: fires GBM_EVENT_WORKING_COPY_OPERATION_FINISHED;
  /// nothing in the repository changes, so no further refresh follows.
  void exportPatches(List<String> commitHexes, String outputDir) {
    if (_session == nullptr) return;
    final Pointer<Utf8> outputDirPtr = outputDir.toNativeUtf8();
    try {
      _withNativeStringArray(
        commitHexes,
        (array, count) =>
            _bindings.patchExport(_session, array, count, outputDirPtr),
      );
    } finally {
      malloc.free(outputDirPtr);
    }
  }

  /// `git apply`: applies a plain diff without creating a commit.
  /// `threeWay` falls back to a merge (leaving conflict markers) instead of
  /// refusing outright when the patch does not apply cleanly; `updateIndex`
  /// also stages the result. Async: fires
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and on success refreshes
  /// the working copy.
  void applyPatchFiles(
    List<String> patchFiles, {
    bool threeWay = false,
    bool updateIndex = false,
  }) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      patchFiles,
      (array, count) => _bindings.patchApplyFiles(
        _session,
        array,
        count,
        threeWay ? 1 : 0,
        updateIndex ? 1 : 0,
      ),
    );
  }

  /// `git am`: applies one or more `format-patch`-style patches as commits,
  /// preserving author/date/message. Async: fires
  /// GBM_EVENT_OPERATION_FINISHED; a patch that does not apply stops the
  /// sequence exactly like [cherryPick], leaving the rest queued for
  /// [continueImport]/[skipImport]/[abortImport].
  void importPatches(List<String> patchFiles, {bool threeWay = false}) {
    if (_session == nullptr) return;
    _withNativeStringArray(
      patchFiles,
      (array, count) =>
          _bindings.patchImport(_session, array, count, threeWay ? 1 : 0),
    );
  }

  void continueImport() {
    if (_session == nullptr) return;
    _bindings.patchImportContinue(_session);
  }

  void skipImport() {
    if (_session == nullptr) return;
    _bindings.patchImportSkip(_session);
  }

  void abortImport() {
    if (_session == nullptr) return;
    _bindings.patchImportAbort(_session);
  }

  /// Async: see gbm_local_identity_refresh()'s doc comment in gbm_capi.h.
  void refreshLocalIdentity() {
    if (_session == nullptr) return;
    _bindings.localIdentityRefresh(_session);
  }

  /// Async: see gbm_effective_identity_refresh()'s doc comment.
  void refreshEffectiveIdentity() {
    if (_session == nullptr) return;
    _bindings.effectiveIdentityRefresh(_session);
  }

  /// `git config --local user.name <name>` then `user.email <email>`.
  /// Async: fires GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, and on success
  /// refreshes both [RepoSessionState.localIdentity] and
  /// [RepoSessionState.effectiveIdentity].
  void setLocalIdentity(String name, String email) {
    if (_session == nullptr) return;
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> emailPtr = email.toNativeUtf8();
    try {
      _bindings.setLocalIdentity(_session, namePtr, emailPtr);
    } finally {
      malloc.free(namePtr);
      malloc.free(emailPtr);
    }
  }

  /// `git config --local --unset user.name`/`user.email`, best-effort. Same
  /// event/refresh contract as [setLocalIdentity].
  void clearLocalIdentity() {
    if (_session == nullptr) return;
    _bindings.clearLocalIdentity(_session);
  }

  /// Filesystem check only, no subprocess -- see gbm_has_commit_graph()'s
  /// doc comment in gbm_capi.h. Synchronous; updates
  /// [RepoSessionState.hasCommitGraph] immediately.
  void refreshHasCommitGraph() {
    if (_session == nullptr) return;
    state = state.copyWith(
      hasCommitGraph: _bindings.hasCommitGraph(_session) != 0,
    );
  }

  /// `git commit-graph write --reachable [--changed-paths] [--split]`.
  /// Async: fires GBM_EVENT_COMMIT_GRAPH_WRITE_FINISHED into
  /// [RepoSessionState.lastCommitGraphWriteSucceeded].
  void writeCommitGraph() {
    if (_session == nullptr) return;
    _bindings.writeCommitGraph(_session);
  }

  /// Marshals `paths` into a native `const char* const*` for the lifetime of
  /// `body`, then frees every string and the array itself.
  void _withNativeStringArray(
    List<String> paths,
    void Function(Pointer<Pointer<Utf8>> array, int count) body,
  ) {
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

final StateNotifierProviderFamily<
  RepoSessionController,
  RepoSessionState,
  RepoIdentity
>
repoSessionProvider =
    StateNotifierProvider.family<
      RepoSessionController,
      RepoSessionState,
      RepoIdentity
    >((ref, identity) {
      final GbmBindings bindings = ref.watch(gbmBindingsProvider);
      return RepoSessionController(bindings, identity);
    });
