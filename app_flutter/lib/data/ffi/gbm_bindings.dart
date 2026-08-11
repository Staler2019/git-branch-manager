import 'dart:ffi';

import 'package:ffi/ffi.dart' show Utf8;

import 'native_library.dart';

// Hand-written bindings mirroring src/capi/gbm_capi.h function-for-function.
// The plan calls for ffigen-generated bindings once the FFI surface
// stabilizes; gbm_capi.h is still small and changing during M0/M1, so a
// hand-written binding (kept in the same order as the header, one typedef
// pair per function) is easier to keep in sync by inspection for now. Revisit
// with ffigen once src/capi/*.cpp covers more than history/graph/branches/
// discovery -- see the plan's milestone roadmap.

typedef GbmSessionHandle = Pointer<Void>;
typedef GbmDiscoveryHandle = Pointer<Void>;

/// Matches `enum GbmEventType` in gbm_capi.h.
abstract final class GbmEventType {
  static const int graphUpdated = 0;
  static const int refsUpdated = 1;
  static const int errorOccurred = 2;
  static const int operationFinished = 3;
  static const int workingCopyStatusUpdated = 4;
  static const int workingCopyOperationFinished = 5;
  static const int workingCopyDiffReady = 6;
  static const int stashesUpdated = 7;
  static const int stashDiffReady = 8;
  static const int worktreesUpdated = 9;
  static const int remotesUpdated = 10;
  static const int credentialRequested = 11;
  static const int operationLogRecord = 12;
}

/// `void (*)(GbmSessionHandle, int32_t, const uint8_t*, int32_t, void*)`.
typedef GbmEventCallbackNative =
    Void Function(
      Pointer<Void> session,
      Int32 eventType,
      Pointer<Uint8> payload,
      Int32 payloadLen,
      Pointer<Void> userData,
    );

typedef _FreeEventPayloadNative = Void Function(Pointer<Uint8> payload);
typedef FreeEventPayloadDart = void Function(Pointer<Uint8> payload);

typedef _LastResultJsonLenNative = Int32 Function();
typedef LastResultJsonLenDart = int Function();

typedef _LastResultJsonCopyNative = Void Function(Pointer<Uint8> out, Int32 outLen);
typedef LastResultJsonCopyDart = void Function(Pointer<Uint8> out, int outLen);

typedef _SessionOpenNative =
    Pointer<Void> Function(Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir);
typedef SessionOpenDart =
    Pointer<Void> Function(Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir);

typedef _SessionCloseNative = Void Function(Pointer<Void> session);
typedef SessionCloseDart = void Function(Pointer<Void> session);

typedef _RegisterCallbackNative =
    Void Function(Pointer<Void> session, Pointer<NativeFunction<GbmEventCallbackNative>> callback, Pointer<Void> userData);
typedef RegisterCallbackDart =
    void Function(Pointer<Void> session, Pointer<NativeFunction<GbmEventCallbackNative>> callback, Pointer<Void> userData);

typedef _RepoStateJsonNative = Int32 Function(Pointer<Void> session);
typedef RepoStateJsonDart = int Function(Pointer<Void> session);

typedef _HistoryRefreshNative = Void Function(Pointer<Void> session);
typedef HistoryRefreshDart = void Function(Pointer<Void> session);

typedef _RefsJsonNative = Int32 Function(Pointer<Void> session);
typedef RefsJsonDart = int Function(Pointer<Void> session);

typedef _GraphRowsNative = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> rowCount, Pointer<Int32> rowStride);
typedef GraphRowsDart = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> rowCount, Pointer<Int32> rowStride);

typedef _GraphOidsNative = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> oidCount, Pointer<Int32> oidStride);
typedef GraphOidsDart = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> oidCount, Pointer<Int32> oidStride);

typedef _GraphParentsNative = Pointer<Uint32> Function(Pointer<Void> session, Pointer<Int32> parentCount);
typedef GraphParentsDart = Pointer<Uint32> Function(Pointer<Void> session, Pointer<Int32> parentCount);

typedef _GraphEdgesNative = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> edgeCount, Pointer<Int32> edgeStride);
typedef GraphEdgesDart = Pointer<Uint8> Function(Pointer<Void> session, Pointer<Int32> edgeCount, Pointer<Int32> edgeStride);

typedef _GraphIntQueryNative = Int32 Function(Pointer<Void> session);
typedef GraphIntQueryDart = int Function(Pointer<Void> session);

typedef _GraphReleaseNative = Void Function(Pointer<Void> session);
typedef GraphReleaseDart = void Function(Pointer<Void> session);

typedef _BranchCheckoutNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> target,
      Int32 detach,
      Int32 createBranch,
      Pointer<Utf8> newBranchName,
      Int32 force,
      Int32 stashFirst,
      Int32 recurseSubmodules,
    );
typedef BranchCheckoutDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> target,
      int detach,
      int createBranch,
      Pointer<Utf8> newBranchName,
      int force,
      int stashFirst,
      int recurseSubmodules,
    );

typedef _ResetToNative = Void Function(Pointer<Void> session, Pointer<Utf8> target, Int32 mode);
typedef ResetToDart = void Function(Pointer<Void> session, Pointer<Utf8> target, int mode);

typedef _MergeBranchNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> target, Int32 mode, Pointer<Utf8> message, Int32 stashFirst);
typedef MergeBranchDart =
    void Function(Pointer<Void> session, Pointer<Utf8> target, int mode, Pointer<Utf8> message, int stashFirst);

typedef _MergeAbortNative = Void Function(Pointer<Void> session);
typedef MergeAbortDart = void Function(Pointer<Void> session);

typedef _CherryPickNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> commitHexes,
      Int32 commitCount,
      Int32 mainline,
      Int32 noCommit,
      Int32 stashFirst,
    );
typedef CherryPickDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> commitHexes,
      int commitCount,
      int mainline,
      int noCommit,
      int stashFirst,
    );

typedef _CherryPickContinueNative = Void Function(Pointer<Void> session);
typedef CherryPickContinueDart = void Function(Pointer<Void> session);

typedef _CherryPickSkipNative = Void Function(Pointer<Void> session);
typedef CherryPickSkipDart = void Function(Pointer<Void> session);

typedef _CherryPickAbortNative = Void Function(Pointer<Void> session);
typedef CherryPickAbortDart = void Function(Pointer<Void> session);

typedef _RevertNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> commitHexes,
      Int32 commitCount,
      Int32 noCommit,
      Int32 stashFirst,
    );
typedef RevertDart =
    void Function(Pointer<Void> session, Pointer<Pointer<Utf8>> commitHexes, int commitCount, int noCommit, int stashFirst);

typedef _ResolveConflictNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Int32 resolution,
      Int32 oursBlobMissing,
      Int32 theirsBlobMissing,
      Pointer<Utf8> resolvedContent,
    );
typedef ResolveConflictDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      int resolution,
      int oursBlobMissing,
      int theirsBlobMissing,
      Pointer<Utf8> resolvedContent,
    );

typedef _WorkingCopyRefreshNative = Void Function(Pointer<Void> session);
typedef WorkingCopyRefreshDart = void Function(Pointer<Void> session);

typedef _WorkingCopyStatusJsonNative = Int32 Function(Pointer<Void> session);
typedef WorkingCopyStatusJsonDart = int Function(Pointer<Void> session);

typedef _WorkingCopyDiffNative = Void Function(Pointer<Void> session, Pointer<Utf8> path, Int32 staged);
typedef WorkingCopyDiffDart = void Function(Pointer<Void> session, Pointer<Utf8> path, int staged);

typedef _StageFilesNative =
    Void Function(Pointer<Void> session, Pointer<Pointer<Utf8>> paths, Int32 pathCount);
typedef StageFilesDart = void Function(Pointer<Void> session, Pointer<Pointer<Utf8>> paths, int pathCount);

typedef _UnstageFilesNative =
    Void Function(Pointer<Void> session, Pointer<Pointer<Utf8>> paths, Int32 pathCount);
typedef UnstageFilesDart = void Function(Pointer<Void> session, Pointer<Pointer<Utf8>> paths, int pathCount);

typedef _CommitChangesNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> message, Int32 amend, Int32 signOff);
typedef CommitChangesDart = void Function(Pointer<Void> session, Pointer<Utf8> message, int amend, int signOff);

typedef _StashRefreshNative = Void Function(Pointer<Void> session);
typedef StashRefreshDart = void Function(Pointer<Void> session);

typedef _StashesJsonNative = Int32 Function(Pointer<Void> session);
typedef StashesJsonDart = int Function(Pointer<Void> session);

typedef _StashSaveNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> message,
      Int32 includeUntracked,
      Int32 keepIndex,
      Pointer<Pointer<Utf8>> paths,
      Int32 pathCount,
    );
typedef StashSaveDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> message,
      int includeUntracked,
      int keepIndex,
      Pointer<Pointer<Utf8>> paths,
      int pathCount,
    );

typedef _StashApplyNative = Void Function(Pointer<Void> session, Int32 index, Int32 pop);
typedef StashApplyDart = void Function(Pointer<Void> session, int index, int pop);

typedef _StashDropNative = Void Function(Pointer<Void> session, Int32 index);
typedef StashDropDart = void Function(Pointer<Void> session, int index);

typedef _StashBranchNative = Void Function(Pointer<Void> session, Int32 index, Pointer<Utf8> branchName);
typedef StashBranchDart = void Function(Pointer<Void> session, int index, Pointer<Utf8> branchName);

typedef _StashRequestDiffNative = Void Function(Pointer<Void> session, Int32 index);
typedef StashRequestDiffDart = void Function(Pointer<Void> session, int index);

typedef _TagCreateNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> name, Pointer<Utf8> target, Pointer<Utf8> message, Int32 force);
typedef TagCreateDart =
    void Function(Pointer<Void> session, Pointer<Utf8> name, Pointer<Utf8> target, Pointer<Utf8> message, int force);

typedef _TagDeleteNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> name, Int32 alsoRemote, Pointer<Utf8> remoteName);
typedef TagDeleteDart =
    void Function(Pointer<Void> session, Pointer<Utf8> name, int alsoRemote, Pointer<Utf8> remoteName);

typedef _TagPushNative = Void Function(Pointer<Void> session, Pointer<Utf8> remoteName, Pointer<Utf8> name);
typedef TagPushDart = void Function(Pointer<Void> session, Pointer<Utf8> remoteName, Pointer<Utf8> name);

typedef _WorktreeRefreshNative = Void Function(Pointer<Void> session);
typedef WorktreeRefreshDart = void Function(Pointer<Void> session);

typedef _WorktreesJsonNative = Int32 Function(Pointer<Void> session);
typedef WorktreesJsonDart = int Function(Pointer<Void> session);

typedef _WorktreeAddNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Pointer<Utf8> branch,
      Int32 createBranch,
      Pointer<Utf8> newBranchName,
      Int32 detach,
      Int32 force,
    );
typedef WorktreeAddDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Pointer<Utf8> branch,
      int createBranch,
      Pointer<Utf8> newBranchName,
      int detach,
      int force,
    );

typedef _WorktreeRemoveNative = Void Function(Pointer<Void> session, Pointer<Utf8> path, Int32 force);
typedef WorktreeRemoveDart = void Function(Pointer<Void> session, Pointer<Utf8> path, int force);

typedef _WorktreePruneNative = Void Function(Pointer<Void> session);
typedef WorktreePruneDart = void Function(Pointer<Void> session);

typedef _WorktreeLockNative = Void Function(Pointer<Void> session, Pointer<Utf8> path, Pointer<Utf8> reason);
typedef WorktreeLockDart = void Function(Pointer<Void> session, Pointer<Utf8> path, Pointer<Utf8> reason);

typedef _WorktreeUnlockNative = Void Function(Pointer<Void> session, Pointer<Utf8> path);
typedef WorktreeUnlockDart = void Function(Pointer<Void> session, Pointer<Utf8> path);

typedef _RemoteRefreshNative = Void Function(Pointer<Void> session);
typedef RemoteRefreshDart = void Function(Pointer<Void> session);

typedef _RemotesJsonNative = Int32 Function(Pointer<Void> session);
typedef RemotesJsonDart = int Function(Pointer<Void> session);

typedef _RemoteFetchNative = Void Function(Pointer<Void> session, Pointer<Utf8> remoteName, Int32 prune, Int32 tags);
typedef RemoteFetchDart = void Function(Pointer<Void> session, Pointer<Utf8> remoteName, int prune, int tags);

typedef _PullNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> remoteName, Pointer<Utf8> branch, Int32 rebase, Int32 stashFirst);
typedef PullDart =
    void Function(Pointer<Void> session, Pointer<Utf8> remoteName, Pointer<Utf8> branch, int rebase, int stashFirst);

typedef _PushNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Utf8> branch,
      Int32 setUpstream,
      Int32 pushTags,
      Int32 forceWithLease,
    );
typedef PushDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Utf8> branch,
      int setUpstream,
      int pushTags,
      int forceWithLease,
    );

typedef _ProvideCredentialNative = Void Function(Pointer<Void> session, Pointer<Utf8> secret);
typedef ProvideCredentialDart = void Function(Pointer<Void> session, Pointer<Utf8> secret);

typedef _CancelCredentialNative = Void Function(Pointer<Void> session);
typedef CancelCredentialDart = void Function(Pointer<Void> session);

typedef _DiscoveryOpenNative = Pointer<Void> Function(Pointer<Utf8> dbPath);
typedef DiscoveryOpenDart = Pointer<Void> Function(Pointer<Utf8> dbPath);

typedef _DiscoveryCloseNative = Void Function(Pointer<Void> discovery);
typedef DiscoveryCloseDart = void Function(Pointer<Void> discovery);

typedef _DiscoveryAddBaseFolderNative =
    Int64 Function(Pointer<Void> discovery, Pointer<Utf8> path, Int32 maxDepth, Int32 followLinks);
typedef DiscoveryAddBaseFolderDart =
    int Function(Pointer<Void> discovery, Pointer<Utf8> path, int maxDepth, int followLinks);

typedef _DiscoveryScanAllNative = Int32 Function(Pointer<Void> discovery);
typedef DiscoveryScanAllDart = int Function(Pointer<Void> discovery);

typedef _DiscoveryListReposJsonNative = Int32 Function(Pointer<Void> discovery);
typedef DiscoveryListReposJsonDart = int Function(Pointer<Void> discovery);

typedef _DiscoveryBaseFoldersJsonNative = Int32 Function(Pointer<Void> discovery);
typedef DiscoveryBaseFoldersJsonDart = int Function(Pointer<Void> discovery);

typedef _DiscoveryRemoveBaseFolderNative = Int32 Function(Pointer<Void> discovery, Int64 baseFolderId);
typedef DiscoveryRemoveBaseFolderDart = int Function(Pointer<Void> discovery, int baseFolderId);

typedef _DiscoverySetBaseFolderEnabledNative =
    Int32 Function(Pointer<Void> discovery, Int64 baseFolderId, Int32 enabled);
typedef DiscoverySetBaseFolderEnabledDart = int Function(Pointer<Void> discovery, int baseFolderId, int enabled);

/// Thin, allocation-free wrapper around the `gbm_capi` symbol table. One
/// instance per isolate is enough; construct it once via [GbmBindings.open]
/// and share it through a Riverpod provider.
class GbmBindings {
  /// Resolves the native library (see [openGbmCapiLibrary]) and looks up
  /// every symbol.
  factory GbmBindings.open() => GbmBindings(openGbmCapiLibrary());

  GbmBindings(DynamicLibrary library)
    : freeEventPayload = library.lookupFunction<_FreeEventPayloadNative, FreeEventPayloadDart>(
        'gbm_free_event_payload',
      ),
      lastResultJsonLen = library.lookupFunction<_LastResultJsonLenNative, LastResultJsonLenDart>(
        'gbm_last_result_json_len',
      ),
      lastResultJsonCopy = library.lookupFunction<_LastResultJsonCopyNative, LastResultJsonCopyDart>(
        'gbm_last_result_json_copy',
      ),
      sessionOpen = library.lookupFunction<_SessionOpenNative, SessionOpenDart>('gbm_session_open'),
      sessionClose = library.lookupFunction<_SessionCloseNative, SessionCloseDart>('gbm_session_close'),
      registerCallback = library.lookupFunction<_RegisterCallbackNative, RegisterCallbackDart>(
        'gbm_register_callback',
      ),
      repoStateJson = library.lookupFunction<_RepoStateJsonNative, RepoStateJsonDart>('gbm_repo_state_json'),
      historyRefresh = library.lookupFunction<_HistoryRefreshNative, HistoryRefreshDart>('gbm_history_refresh'),
      refsJson = library.lookupFunction<_RefsJsonNative, RefsJsonDart>('gbm_refs_json'),
      graphSnapshotRows = library.lookupFunction<_GraphRowsNative, GraphRowsDart>('gbm_graph_snapshot_rows'),
      graphSnapshotOids = library.lookupFunction<_GraphOidsNative, GraphOidsDart>('gbm_graph_snapshot_oids'),
      graphSnapshotParents = library.lookupFunction<_GraphParentsNative, GraphParentsDart>(
        'gbm_graph_snapshot_parents',
      ),
      graphSnapshotEdges = library.lookupFunction<_GraphEdgesNative, GraphEdgesDart>('gbm_graph_snapshot_edges'),
      graphSnapshotLaneCount = library.lookupFunction<_GraphIntQueryNative, GraphIntQueryDart>(
        'gbm_graph_snapshot_lane_count',
      ),
      graphSnapshotComplete = library.lookupFunction<_GraphIntQueryNative, GraphIntQueryDart>(
        'gbm_graph_snapshot_complete',
      ),
      graphSnapshotTruncated = library.lookupFunction<_GraphIntQueryNative, GraphIntQueryDart>(
        'gbm_graph_snapshot_truncated',
      ),
      graphSnapshotRelease = library.lookupFunction<_GraphReleaseNative, GraphReleaseDart>(
        'gbm_graph_snapshot_release',
      ),
      branchCheckout = library.lookupFunction<_BranchCheckoutNative, BranchCheckoutDart>('gbm_branch_checkout'),
      resetTo = library.lookupFunction<_ResetToNative, ResetToDart>('gbm_reset_to'),
      mergeBranch = library.lookupFunction<_MergeBranchNative, MergeBranchDart>('gbm_merge_branch'),
      mergeAbort = library.lookupFunction<_MergeAbortNative, MergeAbortDart>('gbm_merge_abort'),
      cherryPick = library.lookupFunction<_CherryPickNative, CherryPickDart>('gbm_cherry_pick'),
      cherryPickContinue = library.lookupFunction<_CherryPickContinueNative, CherryPickContinueDart>(
        'gbm_cherry_pick_continue',
      ),
      cherryPickSkip = library.lookupFunction<_CherryPickSkipNative, CherryPickSkipDart>('gbm_cherry_pick_skip'),
      cherryPickAbort = library.lookupFunction<_CherryPickAbortNative, CherryPickAbortDart>('gbm_cherry_pick_abort'),
      revert = library.lookupFunction<_RevertNative, RevertDart>('gbm_revert'),
      resolveConflict = library.lookupFunction<_ResolveConflictNative, ResolveConflictDart>('gbm_resolve_conflict'),
      workingCopyRefresh = library.lookupFunction<_WorkingCopyRefreshNative, WorkingCopyRefreshDart>(
        'gbm_working_copy_refresh',
      ),
      workingCopyStatusJson = library
          .lookupFunction<_WorkingCopyStatusJsonNative, WorkingCopyStatusJsonDart>('gbm_working_copy_status_json'),
      workingCopyDiff = library.lookupFunction<_WorkingCopyDiffNative, WorkingCopyDiffDart>(
        'gbm_working_copy_diff',
      ),
      stageFiles = library.lookupFunction<_StageFilesNative, StageFilesDart>('gbm_stage_files'),
      unstageFiles = library.lookupFunction<_UnstageFilesNative, UnstageFilesDart>('gbm_unstage_files'),
      commitChanges = library.lookupFunction<_CommitChangesNative, CommitChangesDart>('gbm_commit_changes'),
      stashRefresh = library.lookupFunction<_StashRefreshNative, StashRefreshDart>('gbm_stash_refresh'),
      stashesJson = library.lookupFunction<_StashesJsonNative, StashesJsonDart>('gbm_stashes_json'),
      stashSave = library.lookupFunction<_StashSaveNative, StashSaveDart>('gbm_stash_save'),
      stashApply = library.lookupFunction<_StashApplyNative, StashApplyDart>('gbm_stash_apply'),
      stashDrop = library.lookupFunction<_StashDropNative, StashDropDart>('gbm_stash_drop'),
      stashBranch = library.lookupFunction<_StashBranchNative, StashBranchDart>('gbm_stash_branch'),
      stashRequestDiff = library.lookupFunction<_StashRequestDiffNative, StashRequestDiffDart>(
        'gbm_stash_request_diff',
      ),
      tagCreate = library.lookupFunction<_TagCreateNative, TagCreateDart>('gbm_tag_create'),
      tagDelete = library.lookupFunction<_TagDeleteNative, TagDeleteDart>('gbm_tag_delete'),
      tagPush = library.lookupFunction<_TagPushNative, TagPushDart>('gbm_tag_push'),
      worktreeRefresh = library.lookupFunction<_WorktreeRefreshNative, WorktreeRefreshDart>('gbm_worktree_refresh'),
      worktreesJson = library.lookupFunction<_WorktreesJsonNative, WorktreesJsonDart>('gbm_worktrees_json'),
      worktreeAdd = library.lookupFunction<_WorktreeAddNative, WorktreeAddDart>('gbm_worktree_add'),
      worktreeRemove = library.lookupFunction<_WorktreeRemoveNative, WorktreeRemoveDart>('gbm_worktree_remove'),
      worktreePrune = library.lookupFunction<_WorktreePruneNative, WorktreePruneDart>('gbm_worktree_prune'),
      worktreeLock = library.lookupFunction<_WorktreeLockNative, WorktreeLockDart>('gbm_worktree_lock'),
      worktreeUnlock = library.lookupFunction<_WorktreeUnlockNative, WorktreeUnlockDart>('gbm_worktree_unlock'),
      remoteRefresh = library.lookupFunction<_RemoteRefreshNative, RemoteRefreshDart>('gbm_remote_refresh'),
      remotesJson = library.lookupFunction<_RemotesJsonNative, RemotesJsonDart>('gbm_remotes_json'),
      remoteFetch = library.lookupFunction<_RemoteFetchNative, RemoteFetchDart>('gbm_remote_fetch'),
      pull = library.lookupFunction<_PullNative, PullDart>('gbm_pull'),
      push = library.lookupFunction<_PushNative, PushDart>('gbm_push'),
      provideCredential = library.lookupFunction<_ProvideCredentialNative, ProvideCredentialDart>(
        'gbm_provide_credential',
      ),
      cancelCredential = library.lookupFunction<_CancelCredentialNative, CancelCredentialDart>(
        'gbm_cancel_credential',
      ),
      discoveryOpen = library.lookupFunction<_DiscoveryOpenNative, DiscoveryOpenDart>('gbm_discovery_open'),
      discoveryClose = library.lookupFunction<_DiscoveryCloseNative, DiscoveryCloseDart>('gbm_discovery_close'),
      discoveryAddBaseFolder = library
          .lookupFunction<_DiscoveryAddBaseFolderNative, DiscoveryAddBaseFolderDart>('gbm_discovery_add_base_folder'),
      discoveryScanAll = library.lookupFunction<_DiscoveryScanAllNative, DiscoveryScanAllDart>(
        'gbm_discovery_scan_all',
      ),
      discoveryListReposJson = library
          .lookupFunction<_DiscoveryListReposJsonNative, DiscoveryListReposJsonDart>('gbm_discovery_list_repos_json'),
      discoveryBaseFoldersJson = library
          .lookupFunction<_DiscoveryBaseFoldersJsonNative, DiscoveryBaseFoldersJsonDart>(
            'gbm_discovery_base_folders_json',
          ),
      discoveryRemoveBaseFolder = library
          .lookupFunction<_DiscoveryRemoveBaseFolderNative, DiscoveryRemoveBaseFolderDart>(
            'gbm_discovery_remove_base_folder',
          ),
      discoverySetBaseFolderEnabled = library
          .lookupFunction<_DiscoverySetBaseFolderEnabledNative, DiscoverySetBaseFolderEnabledDart>(
            'gbm_discovery_set_base_folder_enabled',
          );

  final FreeEventPayloadDart freeEventPayload;
  final LastResultJsonLenDart lastResultJsonLen;
  final LastResultJsonCopyDart lastResultJsonCopy;
  final SessionOpenDart sessionOpen;
  final SessionCloseDart sessionClose;
  final RegisterCallbackDart registerCallback;
  final RepoStateJsonDart repoStateJson;
  final HistoryRefreshDart historyRefresh;
  final RefsJsonDart refsJson;
  final GraphRowsDart graphSnapshotRows;
  final GraphOidsDart graphSnapshotOids;
  final GraphParentsDart graphSnapshotParents;
  final GraphEdgesDart graphSnapshotEdges;
  final GraphIntQueryDart graphSnapshotLaneCount;
  final GraphIntQueryDart graphSnapshotComplete;
  final GraphIntQueryDart graphSnapshotTruncated;
  final GraphReleaseDart graphSnapshotRelease;
  final BranchCheckoutDart branchCheckout;
  final ResetToDart resetTo;
  final MergeBranchDart mergeBranch;
  final MergeAbortDart mergeAbort;
  final CherryPickDart cherryPick;
  final CherryPickContinueDart cherryPickContinue;
  final CherryPickSkipDart cherryPickSkip;
  final CherryPickAbortDart cherryPickAbort;
  final RevertDart revert;
  final ResolveConflictDart resolveConflict;
  final WorkingCopyRefreshDart workingCopyRefresh;
  final WorkingCopyStatusJsonDart workingCopyStatusJson;
  final WorkingCopyDiffDart workingCopyDiff;
  final StageFilesDart stageFiles;
  final UnstageFilesDart unstageFiles;
  final CommitChangesDart commitChanges;
  final StashRefreshDart stashRefresh;
  final StashesJsonDart stashesJson;
  final StashSaveDart stashSave;
  final StashApplyDart stashApply;
  final StashDropDart stashDrop;
  final StashBranchDart stashBranch;
  final StashRequestDiffDart stashRequestDiff;
  final TagCreateDart tagCreate;
  final TagDeleteDart tagDelete;
  final TagPushDart tagPush;
  final WorktreeRefreshDart worktreeRefresh;
  final WorktreesJsonDart worktreesJson;
  final WorktreeAddDart worktreeAdd;
  final WorktreeRemoveDart worktreeRemove;
  final WorktreePruneDart worktreePrune;
  final WorktreeLockDart worktreeLock;
  final WorktreeUnlockDart worktreeUnlock;
  final RemoteRefreshDart remoteRefresh;
  final RemotesJsonDart remotesJson;
  final RemoteFetchDart remoteFetch;
  final PullDart pull;
  final PushDart push;
  final ProvideCredentialDart provideCredential;
  final CancelCredentialDart cancelCredential;
  final DiscoveryOpenDart discoveryOpen;
  final DiscoveryCloseDart discoveryClose;
  final DiscoveryAddBaseFolderDart discoveryAddBaseFolder;
  final DiscoveryScanAllDart discoveryScanAll;
  final DiscoveryListReposJsonDart discoveryListReposJson;
  final DiscoveryBaseFoldersJsonDart discoveryBaseFoldersJson;
  final DiscoveryRemoveBaseFolderDart discoveryRemoveBaseFolder;
  final DiscoverySetBaseFolderEnabledDart discoverySetBaseFolderEnabled;
}
