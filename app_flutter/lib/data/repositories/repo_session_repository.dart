import 'dart:collection';
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/event_dispatcher.dart';
import '../ffi/gbm_bindings.dart';
import '../ffi/json_codec.dart';
import '../models/bisect_status.dart';
import '../models/blame_result.dart';
import '../models/changed_file.dart';
import '../models/clean_entry.dart';
import '../models/commit_meta.dart';
import '../models/compare_commit_entry.dart';
import '../models/file_history_entry.dart';
import '../models/git_error.dart';
import '../models/git_identity.dart';
import '../models/graph_snapshot.dart';
import '../models/lfs_state.dart';
import '../models/line_history_chunk.dart';
import '../models/operation_choice.dart';
import '../models/app_log_events.dart';
import '../models/operation_record.dart';
import '../models/parsed_conflict_file.dart';
import '../models/parsed_diff.dart';
import '../models/rebase_todo_entry.dart';
import '../models/ref_snapshot.dart';
import '../models/reflog_entry.dart';
import '../models/remote_info.dart';
import '../models/remote_prune_preview_entry.dart';
import '../models/repo_state.dart' as model;
import '../models/stash_entry.dart';
import '../models/submodule_info.dart';
import '../models/undo_entry.dart';
import '../models/working_copy_status.dart';
import '../models/worktree_info.dart';
import 'app_preferences_repository.dart';
import 'gbm_bindings_provider.dart';
import 'pending_operation_tracker.dart';
import 'recents_repository.dart';
import 'open_repo_sessions.dart';
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

/// Key of one entry in [RepoSessionState.workingCopyDiffs].
///
/// Both halves are load-bearing: the same path has two independent diffs
/// (work tree vs index, index vs HEAD) and the Working Copy view shows them
/// at the same time, so a key that dropped `staged` would make the two
/// overwrite each other -- which is the single-slot behaviour this replaced.
String workingCopyDiffKey(String path, {required bool staged}) =>
    '$staged:$path';

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

/// Reply to [RepoSessionController.exportFileAtRevision]: mirrors
/// GBM_EVENT_FILE_AT_REVISION_EXPORTED's payload shape.
///
/// The three request parameters are echoed back by the capi so a listener
/// with several exports in flight can tell which one this is -- match on
/// [destPath], which the caller chose and is therefore unique per request,
/// rather than on [path], which repeats across revisions.
class FileAtRevisionExport {
  const FileAtRevisionExport({
    required this.revision,
    required this.path,
    required this.destPath,
    required this.succeeded,
    this.error,
  });

  factory FileAtRevisionExport.fromJson(Map<String, dynamic> json) {
    final Object? error = json['error'];
    return FileAtRevisionExport(
      revision: json['revision'] as String,
      path: json['path'] as String,
      destPath: json['destPath'] as String,
      succeeded: json['succeeded'] as bool,
      error: error is Map<String, dynamic> ? GitError.fromJson(error) : null,
    );
  }

  final String revision;
  final String path;

  /// Where the bytes were written. Only meaningful when [succeeded] --
  /// nothing is created on disk otherwise, so a caller must never hand this
  /// to the OS without checking.
  final String destPath;
  final bool succeeded;

  /// Why it failed, or null on success. Present rather than routed through
  /// `lastError` because a failed export is the answer to one specific
  /// request, not a repository-wide error state.
  final GitError? error;
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

/// Reply to [RepoSessionController.requestCompareRefs]: mirrors
/// GBM_EVENT_COMPARE_READY's payload shape. left/right/threeDot are echoed
/// back from the request, since several Compare tabs can be open at once
/// with different ref pairs -- see [key] for how a tab matches a reply back
/// to itself in [RepoSessionState.compareResults].
class CompareResult {
  const CompareResult({
    required this.left,
    required this.right,
    required this.threeDot,
    required this.mergeBase,
    required this.commits,
    required this.files,
  });

  factory CompareResult.fromJson(Map<String, dynamic> json) {
    return CompareResult(
      left: json['left'] as String,
      right: json['right'] as String,
      threeDot: json['threeDot'] as bool,
      mergeBase: json['mergeBase'] as String,
      commits: CompareCommitEntry.listFromJson(
        json['commits'] as List<dynamic>,
      ),
      files: (json['files'] as List<dynamic>)
          .map((e) => DiffFile.fromJson(e as Map<String, dynamic>))
          .toList(growable: false),
    );
  }

  /// Composite lookup key into [RepoSessionState.compareResults] -- the same
  /// left/right/threeDot triple a Compare tab requested with.
  static String key(String left, String right, bool threeDot) =>
      '$left::$right::$threeDot';

  final String left;
  final String right;
  final bool threeDot;

  /// Empty when the two refs share no common ancestor -- a valid result
  /// (unrelated histories) to display, not an error.
  final String mergeBase;
  final List<CompareCommitEntry> commits;
  final List<DiffFile> files;
}

/// Reply to [RepoSessionController.requestCompareFileDiff]: mirrors
/// GBM_EVENT_COMPARE_FILE_DIFF_READY's payload shape. Same echo-the-request
/// reasoning as [CompareResult].
class CompareFileDiffResult {
  const CompareFileDiffResult({
    required this.left,
    required this.right,
    required this.threeDot,
    required this.path,
    required this.diff,
  });

  factory CompareFileDiffResult.fromJson(Map<String, dynamic> json) {
    return CompareFileDiffResult(
      left: json['left'] as String,
      right: json['right'] as String,
      threeDot: json['threeDot'] as bool,
      path: json['path'] as String,
      diff: ParsedDiff.fromJson(json['diff'] as Map<String, dynamic>),
    );
  }

  /// Composite lookup key into [RepoSessionState.compareFileDiffResults].
  static String key(String left, String right, bool threeDot, String path) =>
      '$left::$right::$threeDot::$path';

  final String left;
  final String right;
  final bool threeDot;
  final String path;
  final ParsedDiff diff;
}

/// Which remotes a just-completed fetch should be asked to preview for
/// pruning, per spec page 02's three-stage gone flow (stage 1 and 2 mark,
/// stage 3 -- an explicit Remote -> Prune remote branches -- removes).
///
/// [fetchedRemote] is the name the fetch was submitted with; an empty string
/// is `git fetch --all` (`FetchOperation::run`, RemoteOps.cpp) and only then
/// does this fan out. Scoping matters because `git remote prune --dry-run`
/// contacts the network: previewing every remote after `fetch origin` would
/// fire round trips the user never asked for.
///
/// The fan-out derives remote names from [refs], **not** from
/// `RepoSessionState.remotes`: `RepoSessionController._open()` calls
/// `_readRepoState`/`refreshHistory`/`refreshWorkingCopy` and never
/// `refreshRemotes()`, so `remotes` is routinely empty and would silently
/// preview nothing. A named remote is returned even when the snapshot has no
/// refs for it -- a remote fetched for the first time has no remote-tracking
/// refs yet.
///
/// Order is stable (first appearance in the snapshot) so the resulting calls,
/// and any test asserting on them, are deterministic.
@visibleForTesting
List<String> remotesToPreviewAfterFetch(
  String fetchedRemote,
  RefSnapshot refs,
) {
  if (fetchedRemote.isNotEmpty) return <String>[fetchedRemote];
  final LinkedHashSet<String> names = LinkedHashSet<String>();
  for (final RefInfo ref in refs.remoteBranches) {
    final (String remote, String _) = remoteBranchParts(ref.fullName);
    if (remote.isNotEmpty) names.add(remote);
  }
  return names.toList(growable: false);
}

/// Reply to [RepoSessionController.requestRemotePrunePreview]: mirrors
/// GBM_EVENT_REMOTE_PRUNE_PREVIEW_READY's payload shape.
class RemotePrunePreview {
  const RemotePrunePreview({required this.remote, required this.refs});

  factory RemotePrunePreview.fromJson(Map<String, dynamic> json) {
    return RemotePrunePreview(
      remote: json['remote'] as String,
      refs: RemotePrunePreviewEntry.listFromJson(json['refs'] as List<dynamic>),
    );
  }

  final String remote;
  final List<RemotePrunePreviewEntry> refs;
}

/// Reply to [RepoSessionController.requestCompareWithWorkingCopy]: mirrors
/// GBM_EVENT_COMPARE_WITH_WORKING_COPY_READY's payload shape -- the "compare
/// a ref with Working Copy" side of the Compare tab, distinct from
/// [CompareResult] because a working-tree diff has no second ref, no
/// threeDot toggle and no merge base.
class CompareWithWorkingCopyResult {
  const CompareWithWorkingCopyResult({required this.ref, required this.diff});

  factory CompareWithWorkingCopyResult.fromJson(Map<String, dynamic> json) {
    return CompareWithWorkingCopyResult(
      ref: json['ref'] as String,
      diff: ParsedDiff.fromJson(json['diff'] as Map<String, dynamic>),
    );
  }

  /// Composite lookup key into
  /// [RepoSessionState.compareWithWorkingCopyResults] -- just `ref`, since a
  /// Compare tab comparing against Working Copy has only one other side
  /// (unlike [CompareResult.key], which also needs `right`/`threeDot`).
  static String key(String ref) => ref;

  final String ref;
  final ParsedDiff diff;
}

/// Default cap for how many [GbmLogEntry]s [RepoSessionState.operationLog]
/// keeps, used only when [RepoSessionController] isn't given an explicit
/// value. The real cap in normal operation comes from
/// [AppPreferences.logMemoryLimit] (spec page 10 LOGRULES: "記憶體中保留最近
/// 2,000 筆…上限寫在 Preferences，不隱藏") -- this constant is *not* mirroring
/// `OperationRunner.cpp`'s `kMaxUndoEntries` (that guards a different list,
/// `undoJournal_`, the one Undo Last reads; it has never been the same
/// number as this one, and changing it has no effect here). This value
/// matches [AppPreferences]'s own default so the two stay in sync absent an
/// explicit override.
const int _kDefaultMaxOperationLogEntries = 2000;

/// Caps how many entries [RepoSessionState.commitMetaCache] keeps. Unlike
/// [_kDefaultMaxOperationLogEntries], there is no core-side precedent to
/// mirror -- this cache has no cap at all today, so a long session that scrolls
/// through a very large repo's entire history grows it without bound. 5000
/// is generous enough that normal browsing (a viewport's worth of rows plus
/// scrollback) never hits it, while still bounding worst-case memory for a
/// session that never closes.
const int _kMaxCommitMetaCacheEntries = 5000;

/// Caps [RepoSessionState.commitFileCountCache], for the same reason and by
/// the same rule as [_kMaxCommitMetaCacheEntries] -- both are viewport-filled
/// caches with no natural bound. Deliberately the same number rather than a
/// separately-tuned one: the two are populated from the same rows, so a
/// different cap would only mean one of them evicting a commit the other
/// still remembers.
const int _kMaxCommitFileCountCacheEntries = 5000;

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
    this.workingCopyDiffs = const <String, WorkingCopyDiffReply>{},
    this.lastWorkingTreeContent,
    this.lastFileAtRevisionExport,
    this.stashes = const <StashEntry>[],
    this.lastStashDiff,
    this.worktrees = const <WorktreeInfo>[],
    this.remotes = const <RemoteInfo>[],
    this.credentialPrompt,
    this.operationLog = const <GbmLogEntry>[],
    this.lastBlame,
    this.commitMetaCache = const <String, CommitMeta>{},
    this.commitFileCountCache = const <String, int>{},
    this.lastFileHistory = const <FileHistoryEntry>[],
    this.commitFiles = const <ChangedFile>[],
    this.selectedCommitFileDiff,
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
    this.compareResults = const <String, CompareResult>{},
    this.compareFileDiffResults = const <String, CompareFileDiffResult>{},
    this.lastRemotePrunePreview,
    this.gonePendingByRemote = const <String, List<String>>{},
    this.compareWithWorkingCopyResults =
        const <String, CompareWithWorkingCopyResult>{},
    this.originalOperationMessage,
  });

  final bool isOpen;
  final model.RepoState? repoState;
  final RefSnapshot refs;
  final GraphSnapshotView graph;
  final bool isRefreshing;
  final GitError? lastError;
  final WorkingCopyStatus workingCopyStatus;

  /// Every working-copy diff fetched for the currently selected file,
  /// keyed by [workingCopyDiffKey] (`'<staged>:<path>'`).
  ///
  /// A map rather than the single `lastDiff` slot this replaced: the Working
  /// Copy view asks for **both** sides of a file at once and shows them side
  /// by side, and two replies to two in-flight requests race. Last-write-wins
  /// meant one of the two was always the one you could not see. Same shape,
  /// and the same reason, as [gonePendingByRemote].
  final Map<String, WorkingCopyDiffReply> workingCopyDiffs;
  final WorkingTreeContentReply? lastWorkingTreeContent;
  final FileAtRevisionExport? lastFileAtRevisionExport;
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

  /// Newest-last, capped at [RepoSessionController.maxOperationLogEntries]
  /// (sourced from [AppPreferences.logMemoryLimit]).
  final List<GbmLogEntry> operationLog;
  final BlameResult? lastBlame;

  /// Batch-fetched commit metadata (author/subject/body), keyed by oid and
  /// accumulated across every GBM_EVENT_COMMIT_META_READY reply rather than
  /// replaced -- unlike [lastBlame]/[lastFileHistory], a viewport scroll
  /// only ever asks for the newly-visible rows, so a later reply must add
  /// to this cache, not overwrite the rows fetched by an earlier one. See
  /// history_repository.dart's `commitMetaProvider`/`requestCommitMeta`.
  final Map<String, CommitMeta> commitMetaCache;

  /// How many files each commit changed, keyed by oid -- the History Changed
  /// files column's data. Merged rather than replaced on every reply, exactly
  /// like [commitMetaCache], and for the same reason: a viewport scroll only
  /// asks for the newly-visible rows.
  ///
  /// A commit git could not answer for is **absent**, never present with 0 --
  /// see GBM_EVENT_COMMIT_FILE_COUNTS_READY. Caching a 0 for an unanswerable
  /// oid would show "0 files" for the rest of the session.
  final Map<String, int> commitFileCountCache;
  final List<FileHistoryEntry> lastFileHistory;
  final List<ChangedFile> commitFiles;
  final ParsedDiff? selectedCommitFileDiff;
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

  /// Every GBM_EVENT_COMPARE_READY reply received this session, keyed by
  /// [CompareResult.key] and accumulated across replies (like
  /// [commitMetaCache]) rather than replaced -- several Compare tabs can be
  /// open at once, each awaiting its own left/right/threeDot query, and a
  /// later-resolving tab's reply must not clobber an earlier tab's still
  /// on-screen result.
  final Map<String, CompareResult> compareResults;

  /// Every GBM_EVENT_COMPARE_FILE_DIFF_READY reply received this session,
  /// keyed by [CompareFileDiffResult.key]. Same accumulate-not-replace
  /// reasoning as [compareResults].
  final Map<String, CompareFileDiffResult> compareFileDiffResults;

  /// The most recent GBM_EVENT_REMOTE_PRUNE_PREVIEW_READY reply -- a single
  /// "latest" field is enough here, unlike [compareResults]: only one Prune
  /// dialog can be open at a time.
  final RemotePrunePreview? lastRemotePrunePreview;

  /// Remote name -> the full ref names on that remote which `git remote
  /// prune --dry-run` says no longer exist upstream.
  ///
  /// Spec page 02's "遠端分支被刪除時怎麼看得到" is explicitly three-staged:
  /// a fetch marks the row (半透明 + 刪除線 + cloud-off, plus a pending count
  /// in the section header), the local branch tracking it gets a `gone`
  /// badge, and only an explicit Remote -> Prune remote branches actually
  /// removes the ref. Git will not report `[gone]` in `%(upstream:track)`
  /// until the remote-tracking ref is already deleted locally, so stage 1
  /// and 2 need a source of truth that does *not* delete anything -- which
  /// is what the dry-run preview is.
  ///
  /// Keyed per remote, and replaced per remote by [withGonePendingFor],
  /// because `git fetch --all` fires one preview per remote and the replies
  /// arrive independently: a whole-map overwrite would let the second reply
  /// erase the first. Distinct from [lastRemotePrunePreview], which stays a
  /// single last-write-wins field for the Prune dialog -- one dialog, one
  /// remote, no accumulation wanted there.
  final Map<String, List<String>> gonePendingByRemote;

  /// Every gone-pending ref across all remotes, flattened -- the only thing
  /// UI code should read.
  Set<String> get gonePendingRefs =>
      gonePendingByRemote.values.expand((refs) => refs).toSet();

  /// Every GBM_EVENT_COMPARE_WITH_WORKING_COPY_READY reply received this
  /// session, keyed by [CompareWithWorkingCopyResult.key]. Same
  /// accumulate-not-replace reasoning as [compareResults] -- several
  /// Compare tabs can each have Working Copy as one side, comparing against
  /// a different ref.
  final Map<String, CompareWithWorkingCopyResult> compareWithWorkingCopyResults;

  /// Git's own proposed commit message (MERGE_MSG / rebase-merge/message)
  /// for the commit currently stopped on in a conflicted cherry-pick or
  /// rebase -- the MSGS-table default the conflict resolve window's message
  /// step pre-fills with. Null until
  /// [RepoSessionController.requestOriginalOperationMessage]'s reply
  /// arrives; that call also nulls this first, so a null value while a
  /// request is in flight can't be mistaken for a stale previous reply.
  final String? originalOperationMessage;

  /// Single source of truth for "is this repo in a conflict state" --
  /// every conflict-aware surface (banner, toolbar, branch switching,
  /// working copy's Conflicted section, commit box, status bar) must read
  /// this rather than re-deriving its own check, or they will drift.
  ///
  /// Mirrors `RepoState::isSequencerOperation()`'s own justification
  /// (src/core/git/RepoState.h) for why this is an OR of two independent
  /// signals, not just one: `isSequencerOperation` deliberately excludes a
  /// plain `Merge` flag, and a `git apply --3way` conflict leaves no
  /// sequencer state file at all -- so `workingCopyStatus.conflicted` is
  /// the only signal that catches those cases, while `isSequencerOperation`
  /// catches an interrupted rebase/cherry-pick/revert before any per-file
  /// conflict has necessarily been scanned yet.
  bool get conflictActive =>
      (repoState?.isSequencerOperation ?? false) ||
      workingCopyStatus.conflicted.isNotEmpty;

  RepoSessionState copyWith({
    bool? isOpen,
    model.RepoState? repoState,
    RefSnapshot? refs,
    GraphSnapshotView? graph,
    bool? isRefreshing,
    GitError? lastError,
    bool clearError = false,
    WorkingCopyStatus? workingCopyStatus,
    Map<String, WorkingCopyDiffReply>? workingCopyDiffs,
    WorkingTreeContentReply? lastWorkingTreeContent,
    FileAtRevisionExport? lastFileAtRevisionExport,
    List<StashEntry>? stashes,
    StashDiffReply? lastStashDiff,
    List<WorktreeInfo>? worktrees,
    List<RemoteInfo>? remotes,
    String? credentialPrompt,
    bool clearCredentialPrompt = false,
    List<GbmLogEntry>? operationLog,
    BlameResult? lastBlame,
    Map<String, CommitMeta>? commitMetaCache,
    Map<String, int>? commitFileCountCache,
    List<FileHistoryEntry>? lastFileHistory,
    List<ChangedFile>? commitFiles,
    ParsedDiff? selectedCommitFileDiff,
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
    Map<String, CompareResult>? compareResults,
    Map<String, CompareFileDiffResult>? compareFileDiffResults,
    RemotePrunePreview? lastRemotePrunePreview,
    Map<String, List<String>>? gonePendingByRemote,
    Map<String, CompareWithWorkingCopyResult>? compareWithWorkingCopyResults,
    String? originalOperationMessage,
    bool clearOriginalOperationMessage = false,
  }) {
    return RepoSessionState(
      isOpen: isOpen ?? this.isOpen,
      repoState: repoState ?? this.repoState,
      refs: refs ?? this.refs,
      graph: graph ?? this.graph,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      lastError: clearError ? null : (lastError ?? this.lastError),
      workingCopyStatus: workingCopyStatus ?? this.workingCopyStatus,
      workingCopyDiffs: workingCopyDiffs ?? this.workingCopyDiffs,
      lastWorkingTreeContent:
          lastWorkingTreeContent ?? this.lastWorkingTreeContent,
      lastFileAtRevisionExport:
          lastFileAtRevisionExport ?? this.lastFileAtRevisionExport,
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
      commitFileCountCache: commitFileCountCache ?? this.commitFileCountCache,
      lastFileHistory: lastFileHistory ?? this.lastFileHistory,
      commitFiles: commitFiles ?? this.commitFiles,
      selectedCommitFileDiff:
          selectedCommitFileDiff ?? this.selectedCommitFileDiff,
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
      compareResults: compareResults ?? this.compareResults,
      compareFileDiffResults:
          compareFileDiffResults ?? this.compareFileDiffResults,
      lastRemotePrunePreview:
          lastRemotePrunePreview ?? this.lastRemotePrunePreview,
      gonePendingByRemote: gonePendingByRemote ?? this.gonePendingByRemote,
      compareWithWorkingCopyResults:
          compareWithWorkingCopyResults ?? this.compareWithWorkingCopyResults,
      originalOperationMessage: clearOriginalOperationMessage
          ? null
          : (originalOperationMessage ?? this.originalOperationMessage),
    );
  }

  /// Merges [metas] into [commitMetaCache] keyed by oid -- see that field's
  /// doc comment for why a reply must add to the cache rather than replace
  /// it -- then caps the result at [_kMaxCommitMetaCacheEntries] by
  /// dropping the oldest entries in insertion order, the same sublist
  /// pattern [operationLog]'s cap uses (though that one's cap is
  /// configurable via [AppPreferences.logMemoryLimit]; this one is not).
  /// Replaces [remote]'s slice of [gonePendingByRemote] with [entries],
  /// normalised to full ref names via [RemotePrunePreviewEntry.fullRefName].
  ///
  /// An empty [entries] drops the remote from the map instead of storing an
  /// empty list: a ref the user pruned in a terminal must stop being marked,
  /// and a remote that contributes nothing should not keep an entry that
  /// later reads as "this remote has been checked".
  RepoSessionState withGonePendingFor(
    String remote,
    List<RemotePrunePreviewEntry> entries,
  ) {
    final Map<String, List<String>> next = <String, List<String>>{
      ...gonePendingByRemote,
    };
    if (entries.isEmpty) {
      next.remove(remote);
    } else {
      next[remote] = entries.map((e) => e.fullRefName).toList(growable: false);
    }
    return copyWith(
      gonePendingByRemote: Map<String, List<String>>.unmodifiable(next),
    );
  }

  /// Drops [refs] from [remote]'s slice of [gonePendingByRemote] -- what a
  /// *successful* `pruneRemote` means for the marking.
  ///
  /// Removal rather than a whole-slice clear because the Prune dialog lets
  /// the user deselect entries: the refs actually pruned are a subset of
  /// what was previewed, and the ones left behind are still gone-pending.
  ///
  /// [refs] is normalised through [fullRemoteRefName] because the call
  /// sites disagree on form -- `prune_remote_branches_dialog.dart` sends
  /// git's short names, `sidebar_panel.dart` sends full ones -- and this
  /// map stores full names. Comparing without normalising would silently
  /// no-op for every dialog-initiated prune.
  ///
  /// A real prune also makes git start reporting `[gone]` in
  /// `%(upstream:track)`, so the existing [RefInfo.isGone] path takes over
  /// the display for any local branch that tracked one of these refs; that
  /// is why this removes rather than leaving both sources lit at once.
  RepoSessionState withGonePendingRemoved(String remote, List<String> refs) {
    final List<String>? current = gonePendingByRemote[remote];
    if (current == null) return this;
    final Set<String> removed = refs.map(fullRemoteRefName).toSet();
    final List<String> kept = current
        .where((String ref) => !removed.contains(ref))
        .toList(growable: false);
    if (kept.length == current.length) return this;
    final Map<String, List<String>> next = <String, List<String>>{
      ...gonePendingByRemote,
    };
    if (kept.isEmpty) {
      next.remove(remote);
    } else {
      next[remote] = kept;
    }
    return copyWith(
      gonePendingByRemote: Map<String, List<String>>.unmodifiable(next),
    );
  }

  RepoSessionState withCommitMeta(List<CommitMeta> metas) {
    final Map<String, CommitMeta> merged = <String, CommitMeta>{
      ...commitMetaCache,
      for (final CommitMeta meta in metas) meta.oid: meta,
    };
    final Map<String, CommitMeta> capped =
        merged.length <= _kMaxCommitMetaCacheEntries
        ? merged
        : Map<String, CommitMeta>.fromEntries(
            merged.entries.skip(merged.length - _kMaxCommitMetaCacheEntries),
          );
    return copyWith(commitMetaCache: capped);
  }

  /// Merges [counts] into [commitFileCountCache], then caps the result at
  /// [_kMaxCommitFileCountCacheEntries] the same way [withCommitMeta] does.
  RepoSessionState withCommitFileCounts(Map<String, int> counts) {
    final Map<String, int> merged = <String, int>{
      ...commitFileCountCache,
      ...counts,
    };
    final Map<String, int> capped =
        merged.length <= _kMaxCommitFileCountCacheEntries
        ? merged
        : Map<String, int>.fromEntries(
            merged.entries.skip(
              merged.length - _kMaxCommitFileCountCacheEntries,
            ),
          );
    return copyWith(commitFileCountCache: capped);
  }

  /// Appends [record] to [operationLog], then evicts the oldest entries
  /// (sublist from the tail) once over [maxEntries] -- the same shape as
  /// [withCommitMeta]'s eviction, extracted here (rather than left inline in
  /// [RepoSessionController]'s event handler) so the cap logic is
  /// unit-testable against a plain [RepoSessionState] without a live FFI
  /// session. [maxEntries] is a parameter, not a class constant, because the
  /// real cap is [RepoSessionController.maxOperationLogEntries] (sourced
  /// from [AppPreferences.logMemoryLimit]), which this pure state class has
  /// no way to read for itself.
  RepoSessionState withOperationRecord(
    GbmLogEntry record, {
    required int maxEntries,
  }) {
    final List<GbmLogEntry> updated = <GbmLogEntry>[...operationLog, record];
    return copyWith(
      operationLog: updated.length > maxEntries
          ? updated.sublist(updated.length - maxEntries)
          : updated,
    );
  }
}

/// Owns one `gbm_capi` session handle end to end: opens it, subscribes to
/// its events, and closes it on dispose. One instance per open repository
/// (`workspaceScreen`'s route scope owns the provider lifetime -- see the
/// routing table in the plan).
class RepoSessionController extends StateNotifier<RepoSessionState>
    implements ClosableRepoSession {
  RepoSessionController(
    this._bindings,
    this._identity,
    this._recents, {
    this.maxOperationLogEntries = _kDefaultMaxOperationLogEntries,
    this._openSessions,
  }) : super(const RepoSessionState()) {
    _openSessions?.register(this);
    _open();
  }

  /// Null in tests that do not care. Registration happens before
  /// [_open] so a session that fails to open is still unregistered by
  /// [dispose] rather than lingering in the registry forever.
  final OpenRepoSessions? _openSessions;

  final GbmBindings _bindings;
  final RepoIdentity _identity;
  final RecentsRepository _recents;

  /// Cap for [RepoSessionState.operationLog], read once at construction from
  /// [AppPreferences.logMemoryLimit] by [repoSessionProvider] (via
  /// `ref.read`, deliberately not `ref.watch` -- watching would rebuild this
  /// whole controller, tearing down and reopening the live `gbm_capi`
  /// session, every time the user changes the Preferences slider). A
  /// preference change takes effect the next time a repository is opened,
  /// not retroactively on an already-open session. Not underscore-prefixed
  /// like this class's other fields, since it doubles as a test seam --
  /// tests that need a small cap to exercise eviction pass it explicitly
  /// instead of feeding thousands of events.
  final int maxOperationLogEntries;
  Pointer<Void> _session = nullptr;
  GbmSessionEvents? _events;
  StreamSubscription<GbmEvent>? _subscription;

  /// Attributes each GBM_EVENT_OPERATION_FINISHED outcome to the
  /// checkout()/deleteBranch() call that produced it, keyed by the "kind"
  /// the C++ side stamps on the outcome (OperationRunner::Operation::kind()).
  /// This exists because `queue_` on the C++ side (OperationRunner.h) is a
  /// `std::deque` that can hold more than one operation at a time -- FIFO
  /// completion order is guaranteed, but *which* completion answers *which*
  /// request is not implied by order alone once anything else on the shared
  /// submitOperation channel (roughly thirty other methods: mergeBranch,
  /// resetTo, cherryPick*, *Rebase, pruneRemote, *Bisect, *Import, ...) is
  /// submitted in between. See [PendingOperationTracker]'s doc comment.
  final PendingOperationTracker _pending = PendingOperationTracker();

  /// The most recent *failed* checkout/deleteBranch request, kept around so
  /// a recovery choice picked from [RepoSessionState.checkoutChoices] /
  /// [RepoSessionState.deleteBranchChoices] can resubmit that exact request
  /// with `stashFirst`/`force` set -- mirrors `MainWindow::checkoutBranch()`'s
  /// own `[this, request]` retry closure in the Qt app. Populated when
  /// [_handleOperationOutcome] pops a matching request off [_pending] and
  /// the outcome failed; cleared on success or once a retry/dismiss consumes
  /// it.
  PendingCheckoutRequest? _lastFailedCheckoutRequest;
  PendingDeleteBranchRequest? _lastFailedDeleteBranchRequest;

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
    // LOGRULES 記什麼 lists 「開啟 repo」 alongside git invocations. Emitted
    // here rather than in the provider, because this is the point at which
    // the handle is genuinely allocated -- every earlier return in this
    // method is an open that did not happen.
    _appendAppLog(
      AppLogEvents.repositoryOpened(
        _identity.workDir,
        atEpochMs: _nowEpochMs(),
      ),
    );
    _readRepoState();
    refreshHistory();
    refreshWorkingCopy();

    // Record this repo as recently opened (fire-and-forget)
    unawaited(_recents.recordOpen(_identity.workDir));
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
        final GitError? error = payload is Map<String, dynamic>
            ? GitError.fromJson(payload)
            : null;
        // Suppression means "do not write", not "write null": an unrelated
        // failure already on screen must survive a background preview
        // failing behind it.
        if (error != null && _isSuppressedAutoPrunePreviewError(error)) {
          state = state.copyWith(isRefreshing: false);
        } else {
          state = state.copyWith(isRefreshing: false, lastError: error);
        }
      case GbmEventType.operationFinished:
        _readRepoState();
        _readUndoJournal();
        final Object? decoded = decodeEventPayload(event.payload);
        final Map<String, dynamic>? payload = decoded is Map<String, dynamic>
            ? decoded
            : null;
        _handleOperationOutcome(payload);
      case GbmEventType.workingCopyStatusUpdated:
        _readWorkingCopyStatus();
      case GbmEventType.workingCopyOperationFinished:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          if (payload['succeeded'] == false) {
            final Object? error = payload['error'];
            state = state.copyWith(
              lastError: error is Map<String, dynamic>
                  ? GitError.fromJson(error)
                  : null,
            );
          }
          _handleWorkingCopyOutcomeKind(payload);
        }
        _readUndoJournal();
      case GbmEventType.workingCopyDiffReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          final WorkingCopyDiffReply reply = WorkingCopyDiffReply.fromJson(
            payload,
          );
          // Merged, never replaced wholesale: the other side of the same
          // file is usually in flight at the same moment and dropping it
          // here is exactly the race the map exists to end.
          state = state.copyWith(
            workingCopyDiffs: <String, WorkingCopyDiffReply>{
              ...state.workingCopyDiffs,
              workingCopyDiffKey(reply.path, staged: reply.staged): reply,
            },
          );
        }
      case GbmEventType.fileAtRevisionExported:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          state = state.copyWith(
            lastFileAtRevisionExport: FileAtRevisionExport.fromJson(payload),
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
          state = state.withOperationRecord(
            OperationRecord.fromJson(payload),
            maxEntries: maxOperationLogEntries,
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
            state = state.withCommitMeta(metas);
          }
        }
      case GbmEventType.commitFileCountsReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is List<dynamic>) {
          final Map<String, int> counts = <String, int>{};
          for (final Object? entry in payload) {
            if (entry is! Map<String, dynamic>) continue;
            final Object? oid = entry['oid'];
            final Object? count = entry['fileCount'];
            if (oid is String && oid.isNotEmpty && count is int) {
              counts[oid] = count;
            }
          }
          if (counts.isNotEmpty) {
            state = state.withCommitFileCounts(counts);
          }
        }
      case GbmEventType.commitFilesReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          final List<dynamic>? files = payload['files'] as List<dynamic>?;
          if (files != null) {
            state = state.copyWith(
              commitFiles: ChangedFile.listFromJson(files),
            );
          }
        }
      case GbmEventType.commitFileDiffReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          final Map<String, dynamic>? diff =
              payload['diff'] as Map<String, dynamic>?;
          if (diff != null) {
            state = state.copyWith(
              selectedCommitFileDiff: ParsedDiff.fromJson(diff),
            );
          }
        }
      case GbmEventType.compareReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          final CompareResult result = CompareResult.fromJson(payload);
          state = state.copyWith(
            compareResults: <String, CompareResult>{
              ...state.compareResults,
              CompareResult.key(result.left, result.right, result.threeDot):
                  result,
            },
          );
        }
      case GbmEventType.compareFileDiffReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          final CompareFileDiffResult result = CompareFileDiffResult.fromJson(
            payload,
          );
          state = state.copyWith(
            compareFileDiffResults: <String, CompareFileDiffResult>{
              ...state.compareFileDiffResults,
              CompareFileDiffResult.key(
                result.left,
                result.right,
                result.threeDot,
                result.path,
              ): result,
            },
          );
        }
      case GbmEventType.remotePrunePreviewReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          final RemotePrunePreview preview = RemotePrunePreview.fromJson(
            payload,
          );
          // Two consumers with different lifetimes, both written here:
          // lastRemotePrunePreview is the Prune dialog's last-write-wins
          // view of one remote, gonePendingByRemote accumulates across
          // remotes so the sidebar can mark rows without deleting any ref
          // (spec page 02's three-stage gone flow, stages 1 and 2).
          _consumeAutoPrunePreview(preview.remote);
          _logNewlyGoneRefs(preview);
          state = state
              .copyWith(lastRemotePrunePreview: preview)
              .withGonePendingFor(preview.remote, preview.refs);
        }
      case GbmEventType.compareWithWorkingCopyReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          final CompareWithWorkingCopyResult result =
              CompareWithWorkingCopyResult.fromJson(payload);
          state = state.copyWith(
            compareWithWorkingCopyResults:
                <String, CompareWithWorkingCopyResult>{
                  ...state.compareWithWorkingCopyResults,
                  CompareWithWorkingCopyResult.key(result.ref): result,
                },
          );
        }
      case GbmEventType.originalOperationMessageReady:
        final Object? payload = decodeEventPayload(event.payload);
        if (payload is Map<String, dynamic>) {
          state = state.copyWith(
            originalOperationMessage: payload['message'] as String? ?? '',
          );
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

  /// Reads the new status **and drops every cached diff**.
  ///
  /// - Key: [workingCopyDiffKey], one entry per (path, side).
  /// - Invalidated by: `GBM_EVENT_WORKING_COPY_STATUS_UPDATED`, the single
  ///   event every stage/unstage/discard/commit ends with. Nothing finer is
  ///   safe -- staging one hunk renumbers the *other* side's hunks too.
  /// - If it were not invalidated: the pane would keep painting the diff
  ///   from before the stage, with hunk indices that now point at different
  ///   lines, so the next "Stage 3 lines" would stage three other lines.
  ///
  /// Clearing here is also what bounds the map: it cannot outgrow one
  /// selected file's two sides.
  void _readWorkingCopyStatus() {
    if (_bindings.workingCopyStatusJson(_session) == 0) {
      final String json = readLastResultJson(_bindings);
      if (json.isNotEmpty) {
        state = state.copyWith(
          workingCopyStatus: WorkingCopyStatus.fromJson(
            jsonDecode(json) as Map<String, dynamic>,
          ),
          workingCopyDiffs: const <String, WorkingCopyDiffReply>{},
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

  /// Derives `succeeded`/`choices` from a GBM_EVENT_OPERATION_FINISHED
  /// payload and, when the payload's "kind" matches a request recorded in
  /// [_pending] (see [PendingOperationTracker]'s doc comment for why
  /// attribution has to go through "kind" rather than "whichever event
  /// arrives next"), updates [RepoSessionState.checkoutChoices] /
  /// [RepoSessionState.deleteBranchChoices] for that specific request. A
  /// "kind" with no matching pending request (or no "kind" at all --
  /// every operation other than checkout/deleteBranch) leaves those fields
  /// untouched.
  void _handleOperationOutcome(Map<String, dynamic>? payload) {
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

    final PendingOperationKind? kind = PendingOperationKind.fromWireName(
      payload?['kind'] as String? ?? '',
    );
    switch (kind) {
      case PendingOperationKind.checkout:
        final PendingCheckoutRequest? request = _pending.takeCheckout();
        if (request == null) break;
        _lastFailedCheckoutRequest = succeeded ? null : request;
        state = state.copyWith(
          checkoutChoices: succeeded ? const <OperationChoice>[] : choices,
        );
        // LOGRULES 記什麼: 「切分支」. Only on success -- a refused checkout
        // already produces a git record carrying the reason, and claiming
        // HEAD moved when it did not is worse than saying nothing.
        if (succeeded) {
          _appendAppLog(
            AppLogEvents.branchCheckedOut(
              target: request.target,
              detach: request.detach,
              createBranch: request.createBranch,
              newBranchName: request.newBranchName,
              atEpochMs: _nowEpochMs(),
            ),
          );
        }
      case PendingOperationKind.deleteBranch:
        final PendingDeleteBranchRequest? request = _pending.takeDeleteBranch();
        if (request == null) break;
        _lastFailedDeleteBranchRequest = succeeded ? null : request;
        state = state.copyWith(
          deleteBranchChoices: succeeded ? const <OperationChoice>[] : choices,
        );
      case PendingOperationKind.fetch:
        // Unreachable, and the exhaustiveness check is what keeps it that
        // way. Fetch goes through Session::submitWorkingCopyOperation, so
        // its outcome arrives on GBM_EVENT_WORKING_COPY_OPERATION_FINISHED
        // and is consumed there -- popping the fetch queue *here* as well
        // would double-pop and misattribute the next fetch. If the capi
        // ever moves fetch onto this channel, this arm is where the change
        // has to be made deliberately rather than absorbed by a default.
        break;
      case PendingOperationKind.pruneRemote:
        final PendingPruneRemoteRequest? request = _pending.takePruneRemote();
        if (request == null) break;
        if (!succeeded) break;
        state = state.withGonePendingRemoved(request.remoteName, request.refs);
        // LOGRULES 記什麼: 「prune 掉哪些 ref」 -- which ones, not just that
        // a prune happened. Skipped for an empty list so a no-op prune does
        // not produce a line saying nothing was removed.
        if (request.refs.isNotEmpty) {
          _appendAppLog(
            AppLogEvents.refsPruned(
              remote: request.remoteName,
              refs: request.refs,
              atEpochMs: _nowEpochMs(),
            ),
          );
        }
      case null:
        break;
    }
  }

  /// Remote name -> how many automatic post-fetch prune previews for that
  /// remote are still awaiting a reply.
  ///
  /// A count rather than a set because `fetch --all` on a repository with the
  /// same remote previewed twice in quick succession would otherwise have one
  /// reply clear a marker that still covers another request in flight.
  final Map<String, int> _autoPrunePreviewsInFlight = <String, int>{};

  /// True when [error] is a failed `git remote prune --dry-run` for a remote
  /// this class asked about itself, in which case it must not reach
  /// [RepoSessionState.lastError] -- `workspace_screen.dart` renders that as
  /// a banner, and a background task the user did not initiate has no
  /// business interrupting them (spec page 10). Consumes one in-flight
  /// marker, so a *second* failure for the same remote (the Prune dialog's)
  /// still surfaces.
  ///
  /// Matched on [GitError.argv] because that is the only discriminator the
  /// capi provides: GBM_EVENT_ERROR_OCCURRED carries no request identity.
  /// Per remote, not "any preview is in flight" -- opening the Prune dialog
  /// for `upstream` during a post-fetch preview of `origin` must still show
  /// the dialog's own failure.
  ///
  /// Known limit, recorded rather than papered over: an automatic and a
  /// dialog-initiated preview of the *same* remote overlapping produce
  /// identical argv, so the dialog's failure would be swallowed once.
  /// Fixing that properly means the capi carrying a request origin, which is
  /// out of scope here.
  bool _isSuppressedAutoPrunePreviewError(GitError error) {
    if (_autoPrunePreviewsInFlight.isEmpty) return false;
    final List<String> argv = error.argv;
    if (!argv.contains('remote') ||
        !argv.contains('prune') ||
        !argv.contains('--dry-run')) {
      return false;
    }
    for (final String remote in _autoPrunePreviewsInFlight.keys) {
      if (!argv.contains(remote)) continue;
      _consumeAutoPrunePreview(remote);
      return true;
    }
    return false;
  }

  /// Appends one app-level log line, honouring the same memory cap git
  /// records go through -- `LOGRULES` 保留 caps the log, not each kind of
  /// entry separately.
  void _appendAppLog(AppLogEntry entry) {
    state = state.withOperationRecord(
      entry,
      maxEntries: maxOperationLogEntries,
    );
  }

  /// Wall-clock for an app-level entry. Named so the one non-deterministic
  /// input in these four call sites is visible rather than inlined five
  /// times.
  int _nowEpochMs() => DateTime.now().millisecondsSinceEpoch;

  /// Logs page 10's gone-marking row, once per ref, for the refs this
  /// preview newly marks.
  ///
  /// Must be called *before* the state is updated, and must diff rather than
  /// log every ref in the preview: an automatic preview runs after every
  /// fetch (see [_remotesToPreviewAfterFetch]), so logging the whole list
  /// would repeat the same warning on every fetch until the user pruned,
  /// which is exactly the kind of noise `LOGRULES` 只有一套 is guarding
  /// against elsewhere.
  void _logNewlyGoneRefs(RemotePrunePreview preview) {
    final Set<String> known =
        (state.gonePendingByRemote[preview.remote] ?? const <String>[]).toSet();
    for (final RemotePrunePreviewEntry entry in preview.refs) {
      if (known.contains(entry.fullRefName)) continue;
      _appendAppLog(
        AppLogEvents.remoteRefGone(entry.ref, atEpochMs: _nowEpochMs()),
      );
    }
  }

  void _consumeAutoPrunePreview(String remote) {
    final int remaining = (_autoPrunePreviewsInFlight[remote] ?? 0) - 1;
    if (remaining <= 0) {
      _autoPrunePreviewsInFlight.remove(remote);
    } else {
      _autoPrunePreviewsInFlight[remote] = remaining;
    }
  }

  /// Consumes the `kind` stamp on a working-copy completion outcome.
  ///
  /// Separate from [_handleOperationOutcome] because the two ride different
  /// capi events (GBM_EVENT_WORKING_COPY_OPERATION_FINISHED vs
  /// GBM_EVENT_OPERATION_FINISHED) even though one `OperationRunner` queue
  /// feeds both -- popping a queue from the wrong handler would double-pop.
  void _handleWorkingCopyOutcomeKind(Map<String, dynamic> payload) {
    final PendingOperationKind? kind = PendingOperationKind.fromWireName(
      payload['kind'] as String? ?? '',
    );
    if (kind != PendingOperationKind.fetch) return;

    // Popped whether or not the fetch succeeded: the queue tracks
    // submissions, so skipping it on failure would hand this request's
    // outcome to the next fetch.
    final PendingFetchRequest? request = _pending.takeFetch();
    if (request == null) return;
    if (payload['succeeded'] != true) return;

    // Spec page 02 is explicit that a fetch must not silently remove a
    // remote-tracking ref, so this asks `git remote prune --dry-run` what a
    // real prune *would* remove and marks those rows instead. Two costs,
    // recorded rather than hidden: the dry run contacts the remote (one
    // round trip per remote, 30s timeout each), and
    // `Session::requestRemotePrunePreview` posts with `postFront`, so these
    // jump ahead of queued viewport reads on the shared read pool. Both are
    // acceptable for something the user triggered by pressing Fetch.
    for (final String remote in remotesToPreviewAfterFetch(
      request.remoteName,
      state.refs,
    )) {
      _autoPrunePreviewsInFlight[remote] =
          (_autoPrunePreviewsInFlight[remote] ?? 0) + 1;
      requestRemotePrunePreview(remote);
    }
  }

  /// Test-only: records a pending fetch request without going through
  /// [fetchRemote], which `FakeRepoSessionController` overrides to log the
  /// call instead of reaching this class's implementation. Same reason
  /// [debugRecordCheckout] exists.
  @visibleForTesting
  void debugRecordFetch({String remoteName = ''}) =>
      _pending.recordFetch(PendingFetchRequest(remoteName: remoteName));

  /// Test-only: records a pending prune-remote request without going through
  /// [pruneRemote], for the same reason [debugRecordFetch] exists.
  @visibleForTesting
  void debugRecordPruneRemote({
    required String remoteName,
    required List<String> refs,
  }) => _pending.recordPruneRemote(
    PendingPruneRemoteRequest(remoteName: remoteName, refs: refs),
  );

  /// Test-only entry point to [_onEvent], so a reducer-level test can feed a
  /// real native event payload without an open session. Takes the event in
  /// its wire form (raw JSON bytes) deliberately -- a hook that accepted an
  /// already-decoded map would skip [decodeEventPayload] and could not
  /// catch a payload-shape mismatch, which is most of what such a test is
  /// for.
  @visibleForTesting
  void debugHandleEvent(GbmEvent event) => _onEvent(event);

  /// Test-only entry point to [_handleOperationOutcome], for a reducer-level
  /// regression test that can't drive the real GBM_EVENT_OPERATION_FINISHED
  /// path (no native session in a widget/unit test). See
  /// [debugRecordCheckout]/[debugRecordDeleteBranch] for arranging the
  /// pending-request precondition this depends on.
  @visibleForTesting
  void debugHandleOperationOutcome(Map<String, dynamic> payload) =>
      _handleOperationOutcome(payload);

  /// Test-only: records a pending checkout request without going through
  /// [checkout] itself. Needed because `FakeRepoSessionController`
  /// (test/support/fake_repo_session.dart) overrides [checkout] to log the
  /// call instead of reaching this class's implementation, so a test can't
  /// arrange "a checkout is in flight" by calling the fake's [checkout].
  @visibleForTesting
  void debugRecordCheckout({
    required String target,
    bool detach = false,
    bool createBranch = false,
    String newBranchName = '',
  }) => _pending.recordCheckout(
    PendingCheckoutRequest(
      target: target,
      detach: detach,
      createBranch: createBranch,
      newBranchName: newBranchName,
    ),
  );

  /// Test-only counterpart to [debugRecordCheckout], for deleteBranch.
  @visibleForTesting
  void debugRecordDeleteBranch({
    required List<String> names,
    bool isRemote = false,
    String remoteName = '',
  }) => _pending.recordDeleteBranch(
    PendingDeleteBranchRequest(
      names: names,
      isRemote: isRemote,
      remoteName: remoteName,
    ),
  );

  /// Synchronously re-reads the undo journal cache -- unlike the other
  /// `_read*` helpers this has no dedicated event; Session refreshes its
  /// cache as part of every operation's completion callback (see
  /// Session::refreshUndoJournalCache()'s doc comment), so this is called
  /// right after GBM_EVENT_OPERATION_FINISHED / GBM_EVENT_WORKING_COPY_OPERATION_FINISHED.
  void _readUndoJournal() {
    // The `_session == nullptr` guard every other `_read*` carries, and
    // which this one was missing. Unreachable in production (events only
    // arrive on an open session), but it is the guard the fake session seam
    // relies on: FakeGbmBindings throws via noSuchMethod on anything it
    // does not implement, so without this any reducer test driving a real
    // event through _onEvent dies here rather than on its own assertion.
    if (_session == nullptr) return;
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

  /// Everything about this repository that can move behind the app's back,
  /// re-read in one call. The single source of truth for "refresh the git
  /// status": both the focus-regain sweep and View -> Refresh call this, so
  /// neither maintains its own list of what that means.
  ///
  /// Membership is a rule, not a hand-picked list: **every zero-argument
  /// `refresh*` on this controller**. That makes "does the new one belong
  /// here" a question with an answer rather than something rediscovered by
  /// the next audit. The `request*` methods are all excluded because they
  /// are keyed to a user selection (a path, an oid, a ref, a stash index)
  /// that need not exist when the window comes back; the three with no
  /// required argument are excluded for their own reasons --
  /// [requestReflog] is fetched per tab by the panel itself,
  /// [requestCleanPreview] walks the entire work tree to feed one dialog,
  /// and [requestOriginalOperationMessage] only means anything mid-conflict.
  ///
  /// **Every one of these is a local read.** The one refresh-shaped call
  /// that reaches the network -- [requestRemotePrunePreview], which backs
  /// gone-marking -- is deliberately not here.
  ///
  /// No git-level judgement is made here either, such as "does this
  /// repository have submodules". Any such predicate is a guess at what git
  /// would have answered, and a guess in Dart is the same mistake as a guess
  /// in core. `git submodule status` costs ~79ms even with zero submodules
  /// (git-submodule is a POSIX shell script, so it is fork + shell startup,
  /// not repository size) -- but it runs on the shared read pool with
  /// nothing on screen waiting for it, so it runs unconditionally like the
  /// rest. Measurements are in docs/ledger.md.
  void refreshRepoStatus() {
    // The two synchronous ones go first: they publish through copyWith
    // rather than waiting on an event, so the conflict badge corrects on
    // this very frame instead of after ten git subprocesses return.
    refreshRepoState();
    refreshHasCommitGraph();
    refreshHistory();
    refreshWorkingCopy();
    refreshStashes();
    refreshWorktrees();
    refreshRemotes();
    refreshSubmodules();
    refreshBisectStatus();
    refreshLfs();
    refreshLocalIdentity();
    refreshEffectiveIdentity();
  }

  /// Re-reads which multi-step git operation, if any, is part-way through.
  ///
  /// **Synchronous, unlike almost every other `refresh*` here**: the others
  /// post to a background pool and fill [state] in later from a GBM event,
  /// while gbm_repo_state_json() populates the staging buffer on this thread
  /// and this method publishes immediately. It can afford to be: the C++
  /// side is `RepoState::read(paths_)`, which stats a handful of paths
  /// inside .git/ and spawns no subprocess, and it recomputes on every call
  /// rather than caching.
  ///
  /// Worth having as a public entry point because [RepoSessionState.repoState]
  /// is the half of [RepoSessionState.conflictActive] that
  /// [refreshWorkingCopy] does not cover -- a rebase begun, continued or
  /// aborted from a terminal changes .git/ and emits no GBM event at all.
  void refreshRepoState() {
    if (_session == nullptr) return;
    _readRepoState();
  }

  /// Requests a refs + history refresh -- see gbm_history_refresh()'s doc
  /// comment in gbm_capi.h. Async: [state] updates as GBM_EVENT_* events
  /// arrive through [_onEvent].
  void refreshHistory() {
    if (_session == nullptr) return;
    state = state.copyWith(isRefreshing: true, clearError: true);
    _bindings.historyRefresh(_session);
  }

  /// Narrows every subsequent history walk. See gbm_history_set_filter()'s
  /// doc comment in gbm_capi.h -- notably that `includeRefs` are *full* ref
  /// names, that the filter is session state so an operation-driven refresh
  /// keeps it, and that an empty list clears it.
  ///
  /// Triggers a walk on its own, so callers must not follow it with
  /// [refreshHistory].
  void setHistoryFilter({
    required List<String> includeRefs,
    bool firstParentOnly = false,
    bool noMerges = false,
  }) {
    if (_session == nullptr) return;
    state = state.copyWith(isRefreshing: true, clearError: true);
    if (includeRefs.isEmpty) {
      // _withNativeStringArray on an empty list would still allocate; the
      // capi reads nothing when the count is 0, so pass a null array.
      _bindings.historySetFilter(
        _session,
        nullptr,
        0,
        firstParentOnly ? 1 : 0,
        noMerges ? 1 : 0,
      );
      return;
    }
    _withNativeStringArray(
      includeRefs,
      (array, count) => _bindings.historySetFilter(
        _session,
        array,
        count,
        firstParentOnly ? 1 : 0,
        noMerges ? 1 : 0,
      ),
    );
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
    _pending.recordCheckout(
      PendingCheckoutRequest(
        target: target,
        detach: detach,
        createBranch: createBranch,
        newBranchName: newBranchName,
      ),
    );
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

  /// Resubmits the checkout request that produced the current
  /// [RepoSessionState.checkoutChoices] with the flag [kind] implies
  /// (stash-and-retry -> `stashFirst`, force-discard -> `force`); any other
  /// kind (Abort/Cancel) just dismisses the choices. A no-op if no failed
  /// checkout is on record -- see [_lastFailedCheckoutRequest].
  void retryCheckoutWithChoice(OperationChoiceKind kind) {
    final PendingCheckoutRequest? request = _lastFailedCheckoutRequest;
    _lastFailedCheckoutRequest = null;
    state = state.copyWith(checkoutChoices: const <OperationChoice>[]);
    if (request == null) return;
    switch (kind) {
      case OperationChoiceKind.stashAndRetry:
        checkout(
          target: request.target,
          detach: request.detach,
          createBranch: request.createBranch,
          newBranchName: request.newBranchName,
          stashFirst: true,
        );
      case OperationChoiceKind.forceDiscard:
        checkout(
          target: request.target,
          detach: request.detach,
          createBranch: request.createBranch,
          newBranchName: request.newBranchName,
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
    _lastFailedCheckoutRequest = null;
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
  ///
  /// [renameRemote] carries the rename through to [remoteName] afterwards
  /// (`push --set-upstream` then `push --delete`); leaving it false unsets
  /// the branch's upstream instead, because `git branch -m` keeps the
  /// tracking config and would otherwise leave the renamed branch pointing
  /// at the old remote branch. Either way the remote work happens in core
  /// as one operation, not as a chain of calls from here -- see
  /// `gbm_branch_rename`'s doc comment.
  void renameBranch({
    required String from,
    required String to,
    bool force = false,
    bool renameRemote = false,
    String remoteName = '',
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> fromPtr = from.toNativeUtf8();
    final Pointer<Utf8> toPtr = to.toNativeUtf8();
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    try {
      _bindings.branchRename(
        _session,
        fromPtr,
        toPtr,
        force ? 1 : 0,
        renameRemote ? 1 : 0,
        remotePtr,
      );
    } finally {
      malloc.free(fromPtr);
      malloc.free(toPtr);
      malloc.free(remotePtr);
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
    _pending.recordDeleteBranch(
      PendingDeleteBranchRequest(
        names: names,
        isRemote: isRemote,
        remoteName: remoteName,
      ),
    );
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

  /// Resubmits the deleteBranch request that produced the current
  /// [RepoSessionState.deleteBranchChoices] with `force` set when [kind] is
  /// [OperationChoiceKind.forceDiscard]; any other kind just dismisses the
  /// choices. A no-op if no failed delete is on record -- see
  /// [_lastFailedDeleteBranchRequest].
  void retryDeleteBranchWithChoice(OperationChoiceKind kind) {
    final PendingDeleteBranchRequest? request = _lastFailedDeleteBranchRequest;
    _lastFailedDeleteBranchRequest = null;
    state = state.copyWith(deleteBranchChoices: const <OperationChoice>[]);
    if (request == null) return;
    switch (kind) {
      case OperationChoiceKind.forceDiscard:
        deleteBranch(
          names: request.names,
          force: true,
          isRemote: request.isRemote,
          remoteName: request.remoteName,
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
    _lastFailedDeleteBranchRequest = null;
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

  /// Same as [cherryPickContinue], except `message` overwrites MERGE_MSG
  /// first -- see gbm_cherry_pick_continue_with_message()'s doc comment in
  /// gbm_capi.h. `message` typically comes from the conflict resolve
  /// window's MSGS-table step, pre-filled from
  /// [requestOriginalOperationMessage]'s reply and edited by the user.
  void cherryPickContinueWithMessage(String message) {
    if (_session == nullptr) return;
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      _bindings.cherryPickContinueWithMessage(_session, messagePtr);
    } finally {
      malloc.free(messagePtr);
    }
  }

  /// Async: fires GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY into
  /// [RepoSessionState.originalOperationMessage]. Nulls that field first so
  /// a still-in-flight request can't be mistaken for a stale previous
  /// reply -- see the field's doc comment.
  void requestOriginalOperationMessage() {
    if (_session == nullptr) return;
    state = state.copyWith(clearOriginalOperationMessage: true);
    _bindings.requestOriginalOperationMessage(_session);
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
  /// Writes `path` as it was at `revision` to `destPath`, for 05-K's "Open
  /// file at this revision" / "Save this revision as...". Async: the outcome
  /// arrives as [RepoSessionState.lastFileAtRevisionExport], echoing all
  /// three arguments back so a listener can match it to this call.
  void exportFileAtRevision({
    required String revision,
    required String path,
    required String destPath,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> revisionPtr = revision.toNativeUtf8();
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Utf8> destPtr = destPath.toNativeUtf8();
    try {
      _bindings.exportFileAtRevision(_session, revisionPtr, pathPtr, destPtr);
    } finally {
      malloc.free(revisionPtr);
      malloc.free(pathPtr);
      malloc.free(destPtr);
    }
  }

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
  /// (staged=true). Async: [state].workingCopyDiffs gains an entry under
  /// [workingCopyDiffKey] when GBM_EVENT_WORKING_COPY_DIFF_READY arrives.
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

  /// Discards a subset of a hunk's lines from the *work tree* -- context
  /// menu 05-G's "Discard N lines…". Unlike [unstageLines], which moves the
  /// index and leaves the file on disk alone, this rewrites the file and
  /// leaves the index alone. Destructive and not recoverable from the
  /// reflog or the stash, so callers route through the discard-changes
  /// confirmation dialog rather than calling this straight from a menu.
  /// Same event/refresh contract as [stageFiles].
  void discardLines(String path, int hunkIndex, List<int> lineIndices) {
    if (_session == nullptr || lineIndices.isEmpty) return;
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    final Pointer<Int32> indices = malloc<Int32>(lineIndices.length);
    try {
      for (int i = 0; i < lineIndices.length; i++) {
        indices[i] = lineIndices[i];
      }
      _bindings.discardLines(
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
  /// [refs] restricts the fetch to those specific refs under [remoteName]
  /// (e.g. one branch, or every branch under a folder prefix) instead of
  /// everything the remote's default refspec would bring in -- empty
  /// fetches everything, the original behavior. See gbm_remote_fetch()'s
  /// doc comment: a non-empty [refs] with an empty [remoteName] is
  /// rejected (no well-defined "these refs from every remote").
  void fetchRemote({
    String remoteName = '',
    List<String> refs = const <String>[],
    bool prune = false,
    bool tags = false,
  }) {
    if (_session == nullptr) return;
    // Recorded before the call, so the outcome that comes back on
    // GBM_EVENT_WORKING_COPY_OPERATION_FINISHED can be attributed to *this*
    // request rather than to whichever fetch happens to be at the head of
    // the queue. See PendingOperationTracker's doc comment.
    _pending.recordFetch(PendingFetchRequest(remoteName: remoteName));
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    try {
      _withNativeStringArray(
        refs,
        (array, count) => _bindings.remoteFetch(
          _session,
          remotePtr,
          array,
          count,
          prune ? 1 : 0,
          tags ? 1 : 0,
        ),
      );
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
  /// there is no plain `--force` (see gbm_push()'s doc comment).
  ///
  /// [branches] empty pushes the current branch. More than one is a
  /// multi-select push: it becomes a single `git push <remote> a b c`, not N
  /// calls, so the whole batch is one background task (spec page 10) and
  /// git's own per-ref reporting supplies "carry on past a ref that failed".
  void pushChanges({
    String remoteName = '',
    List<String> branches = const <String>[],
    bool setUpstream = false,
    bool pushTags = false,
    bool forceWithLease = false,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    try {
      _withNativeStringArray(
        branches,
        (array, count) => _bindings.push(
          _session,
          remotePtr,
          array,
          count,
          setUpstream ? 1 : 0,
          pushTags ? 1 : 0,
          forceWithLease ? 1 : 0,
        ),
      );
    } finally {
      malloc.free(remotePtr);
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

  /// Batch changed-file counts for `oids` -- the History Changed files
  /// column, which is off by default, so this is only ever called for a user
  /// who switched it on. Async: fires GBM_EVENT_COMMIT_FILE_COUNTS_READY,
  /// merged into [RepoSessionState.commitFileCountCache]. Prefer
  /// history_repository.dart's `requestCommitFileCounts`, which dedupes
  /// against already-cached oids first.
  void requestCommitFileCounts(List<String> oids) {
    if (_session == nullptr || oids.isEmpty) return;
    _withNativeStringArray(
      oids,
      (array, count) =>
          _bindings.requestCommitFileCounts(_session, array, count),
    );
  }

  /// Async: fires GBM_EVENT_COMMIT_FILES_READY into
  /// [RepoSessionState.commitFiles].
  void requestCommitFiles(String oid) {
    if (_session == nullptr) return;
    final Pointer<Utf8> oidPtr = oid.toNativeUtf8();
    try {
      _bindings.requestCommitFiles(_session, oidPtr);
    } finally {
      malloc.free(oidPtr);
    }
  }

  /// Async: fires GBM_EVENT_COMMIT_FILE_DIFF_READY into
  /// [RepoSessionState.selectedCommitFileDiff].
  void requestCommitFileDiff(String oid, String path) {
    if (_session == nullptr) return;
    final Pointer<Utf8> oidPtr = oid.toNativeUtf8();
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    try {
      _bindings.requestCommitFileDiff(_session, oidPtr, pathPtr);
    } finally {
      malloc.free(oidPtr);
      malloc.free(pathPtr);
    }
  }

  /// Merge-base + the commit lists unique to each side + the changed-file
  /// summary for two refs, in one round trip. `threeDot` true: `left...right`
  /// (symmetric difference off the merge base, GitHub's PR-diff semantics).
  /// False: `left..right` (only what right has that left doesn't). Async:
  /// fires GBM_EVENT_COMPARE_READY into [RepoSessionState.compareResults],
  /// keyed by [CompareResult.key].
  void requestCompareRefs(
    String leftRef,
    String rightRef, {
    bool threeDot = true,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> leftPtr = leftRef.toNativeUtf8();
    final Pointer<Utf8> rightPtr = rightRef.toNativeUtf8();
    try {
      _bindings.requestCompareRefs(
        _session,
        leftPtr,
        rightPtr,
        threeDot ? 1 : 0,
      );
    } finally {
      malloc.free(leftPtr);
      malloc.free(rightPtr);
    }
  }

  /// One file's full diff between two refs. Async: fires
  /// GBM_EVENT_COMPARE_FILE_DIFF_READY into
  /// [RepoSessionState.compareFileDiffResults], keyed by
  /// [CompareFileDiffResult.key].
  void requestCompareFileDiff(
    String leftRef,
    String rightRef,
    String path, {
    bool threeDot = true,
  }) {
    if (_session == nullptr) return;
    final Pointer<Utf8> leftPtr = leftRef.toNativeUtf8();
    final Pointer<Utf8> rightPtr = rightRef.toNativeUtf8();
    final Pointer<Utf8> pathPtr = path.toNativeUtf8();
    try {
      _bindings.requestCompareFileDiff(
        _session,
        leftPtr,
        rightPtr,
        threeDot ? 1 : 0,
        pathPtr,
      );
    } finally {
      malloc.free(leftPtr);
      malloc.free(rightPtr);
      malloc.free(pathPtr);
    }
  }

  /// The diff between `ref` and the live working tree (uncommitted changes
  /// included) -- the "compare a ref with Working Copy" side of the
  /// Compare tab, distinct from [requestCompareRefs]/[requestCompareFileDiff]
  /// because a working-tree diff has no second ref, no threeDot toggle and
  /// no merge base. `ref` may be any revision expression git accepts
  /// (branch, tag, oid, HEAD~N, ...). Async: fires
  /// GBM_EVENT_COMPARE_WITH_WORKING_COPY_READY into
  /// [RepoSessionState.compareWithWorkingCopyResults], keyed by
  /// [CompareWithWorkingCopyResult.key].
  void requestCompareWithWorkingCopy(String ref) {
    if (_session == nullptr) return;
    final Pointer<Utf8> refPtr = ref.toNativeUtf8();
    try {
      _bindings.requestCompareWithWorkingCopy(_session, refPtr);
    } finally {
      malloc.free(refPtr);
    }
  }

  /// `git remote prune <remoteName> --dry-run`: what [pruneRemote] would
  /// remove, without removing anything. Async: fires
  /// GBM_EVENT_REMOTE_PRUNE_PREVIEW_READY into
  /// [RepoSessionState.lastRemotePrunePreview].
  void requestRemotePrunePreview(String remoteName) {
    if (_session == nullptr) return;
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    try {
      _bindings.requestRemotePrunePreview(_session, remotePtr);
    } finally {
      malloc.free(remotePtr);
    }
  }

  /// Deletes exactly the remote-tracking refs in `refs` (typically a
  /// user-edited subset of a prior [requestRemotePrunePreview] reply) via
  /// `git branch --delete --remotes`. Async: fires
  /// GBM_EVENT_OPERATION_FINISHED (same channel as [deleteBranch], not
  /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED -- pruning remote-tracking
  /// refs never touches the working tree or index), and on success also
  /// refreshes history.
  void pruneRemote(String remoteName, List<String> refs) {
    if (_session == nullptr || refs.isEmpty) return;
    // git's `branch -r -d` only accepts short names, and this method's two
    // producers disagree on form -- see pruneRefArguments() for the measured
    // failure and why the normalisation lives at the wire rather than at each
    // call site. The tracker gets the same normalised list, which stays
    // correct because withGonePendingRemoved() re-expands to full names
    // before comparing against the pending set.
    final List<String> args = pruneRefArguments(refs);
    // Recorded before the call so the outcome can be attributed to *this*
    // request -- see PendingOperationTracker's doc comment. Only a
    // successful prune clears the gone-pending marks it answers for.
    _pending.recordPruneRemote(
      PendingPruneRemoteRequest(remoteName: remoteName, refs: args),
    );
    final Pointer<Utf8> remotePtr = remoteName.toNativeUtf8();
    try {
      _withNativeStringArray(
        args,
        (array, count) =>
            _bindings.remotePrune(_session, remotePtr, array, count),
      );
    } finally {
      malloc.free(remotePtr);
    }
  }

  /// `git remote add`. Async: fires GBM_EVENT_OPERATION_FINISHED, and on
  /// success also refreshes the remote list (same event
  /// gbm_remote_refresh() would fire).
  void addRemote(String name, String url) {
    if (_session == nullptr) return;
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    final Pointer<Utf8> urlPtr = url.toNativeUtf8();
    try {
      _bindings.remoteAdd(_session, namePtr, urlPtr);
    } finally {
      malloc.free(namePtr);
      malloc.free(urlPtr);
    }
  }

  /// `git remote remove`. Async: fires GBM_EVENT_OPERATION_FINISHED, and on
  /// success also refreshes the remote list.
  void removeRemote(String name) {
    if (_session == nullptr) return;
    final Pointer<Utf8> namePtr = name.toNativeUtf8();
    try {
      _bindings.remoteRemove(_session, namePtr);
    } finally {
      malloc.free(namePtr);
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

  /// Same as [continueRebase], except `message` overwrites
  /// rebase-merge/message first -- see
  /// gbm_rebase_continue_with_message()'s doc comment in gbm_capi.h.
  void continueRebaseWithMessage(String message) {
    if (_session == nullptr) return;
    final Pointer<Utf8> messagePtr = message.toNativeUtf8();
    try {
      _bindings.rebaseContinueWithMessage(_session, messagePtr);
    } finally {
      malloc.free(messagePtr);
    }
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

  /// Releases the `gbm_capi` handle without tearing down this notifier.
  ///
  /// Separate from [dispose] because the self-install flow needs the native
  /// side released while the widget tree is still standing -- disposing a
  /// notifier that is still being watched would be a different, worse
  /// problem. Idempotent, so the registry and [dispose] can both call it.
  @override
  void closeNativeSession() {
    if (_session == nullptr) return;
    _bindings.sessionClose(_session);
    _session = nullptr;
  }

  @override
  void dispose() {
    _openSessions?.unregister(this);
    unawaited(_subscription?.cancel());
    _events?.dispose();
    closeNativeSession();
    // No further GBM_EVENT_OPERATION_FINISHED events will arrive to consume
    // whatever is still pending.
    _pending.clear();
    _autoPrunePreviewsInFlight.clear();
    super.dispose();
  }
}

/// Re-reads every local git fact this app tracks for [identity].
///
/// The one entry point for "refresh the git status" -- see
/// [RepoSessionController.refreshRepoStatus] for what that covers and why
/// membership is a rule rather than a list. Both the focus-regain sweep in
/// WorkspaceScreen and View -> Refresh route through here, so the two cannot
/// drift into refreshing different things.
void refreshRepoStatus(WidgetRef ref, RepoIdentity identity) {
  ref.read(repoSessionProvider(identity).notifier).refreshRepoStatus();
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
      final RecentsRepository recents = ref.watch(recentsRepositoryProvider);
      // `ref.read`, not `ref.watch`: this cap only needs to be current as of
      // the moment the session opens. Watching would rebuild the whole
      // controller -- tearing down and reopening the live `gbm_capi` session
      // -- every time the user moves the Preferences slider.
      final int maxOperationLogEntries = ref
          .read(appPreferencesProvider)
          .logMemoryLimit;
      return RepoSessionController(
        bindings,
        identity,
        recents,
        maxOperationLogEntries: maxOperationLogEntries,
        openSessions: ref.read(openRepoSessionsProvider),
      );
    });
