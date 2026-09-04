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
  static const int blameReady = 13;
  static const int fileHistoryReady = 14;
  static const int lineHistoryReady = 15;
  static const int reflogReady = 16;
  static const int rebasePlanReady = 17;
  static const int submodulesUpdated = 18;
  static const int bisectStatusUpdated = 19;
  static const int lfsUpdated = 20;
  static const int cleanPreviewReady = 21;
  static const int localIdentityUpdated = 22;
  static const int effectiveIdentityUpdated = 23;
  static const int commitGraphWriteFinished = 24;
  static const int workingTreeContentReady = 25;
  static const int commitMetaReady = 26;
  static const int commitFilesReady = 27;
  static const int commitFileDiffReady = 28;
  static const int compareReady = 29;
  static const int compareFileDiffReady = 30;
  static const int remotePrunePreviewReady = 31;
  static const int compareWithWorkingCopyReady = 32;
  static const int originalOperationMessageReady = 33;
  static const int fileAtRevisionExported = 34;
  static const int commitFileCountsReady = 35;
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

typedef _LastResultJsonCopyNative =
    Void Function(Pointer<Uint8> out, Int32 outLen);
typedef LastResultJsonCopyDart = void Function(Pointer<Uint8> out, int outLen);

typedef _SessionOpenNative =
    Pointer<Void> Function(
      Pointer<Utf8> workDir,
      Pointer<Utf8> gitDir,
      Pointer<Utf8> commonDir,
    );
typedef SessionOpenDart =
    Pointer<Void> Function(
      Pointer<Utf8> workDir,
      Pointer<Utf8> gitDir,
      Pointer<Utf8> commonDir,
    );

typedef _SessionCloseNative = Void Function(Pointer<Void> session);
typedef SessionCloseDart = void Function(Pointer<Void> session);

typedef _RegisterCallbackNative =
    Void Function(
      Pointer<Void> session,
      Pointer<NativeFunction<GbmEventCallbackNative>> callback,
      Pointer<Void> userData,
    );
typedef RegisterCallbackDart =
    void Function(
      Pointer<Void> session,
      Pointer<NativeFunction<GbmEventCallbackNative>> callback,
      Pointer<Void> userData,
    );

typedef _RepoStateJsonNative = Int32 Function(Pointer<Void> session);
typedef RepoStateJsonDart = int Function(Pointer<Void> session);

typedef _RemoveStaleIndexLockNative = Int32 Function(Pointer<Void> session);
typedef RemoveStaleIndexLockDart = int Function(Pointer<Void> session);

typedef _HistoryRefreshNative = Void Function(Pointer<Void> session);
typedef HistoryRefreshDart = void Function(Pointer<Void> session);
typedef _HistorySetFilterNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> includeRefs,
      Int32 includeRefCount,
      Int32 firstParentOnly,
      Int32 noMerges,
    );
typedef HistorySetFilterDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> includeRefs,
      int includeRefCount,
      int firstParentOnly,
      int noMerges,
    );

typedef _RefsJsonNative = Int32 Function(Pointer<Void> session);
typedef RefsJsonDart = int Function(Pointer<Void> session);

typedef _GraphRowsNative =
    Pointer<Uint8> Function(
      Pointer<Void> session,
      Pointer<Int32> rowCount,
      Pointer<Int32> rowStride,
    );
typedef GraphRowsDart =
    Pointer<Uint8> Function(
      Pointer<Void> session,
      Pointer<Int32> rowCount,
      Pointer<Int32> rowStride,
    );

typedef _GraphOidsNative =
    Pointer<Uint8> Function(
      Pointer<Void> session,
      Pointer<Int32> oidCount,
      Pointer<Int32> oidStride,
    );
typedef GraphOidsDart =
    Pointer<Uint8> Function(
      Pointer<Void> session,
      Pointer<Int32> oidCount,
      Pointer<Int32> oidStride,
    );

typedef _GraphParentsNative =
    Pointer<Uint32> Function(Pointer<Void> session, Pointer<Int32> parentCount);
typedef GraphParentsDart =
    Pointer<Uint32> Function(Pointer<Void> session, Pointer<Int32> parentCount);

typedef _GraphEdgesNative =
    Pointer<Uint8> Function(
      Pointer<Void> session,
      Pointer<Int32> edgeCount,
      Pointer<Int32> edgeStride,
    );
typedef GraphEdgesDart =
    Pointer<Uint8> Function(
      Pointer<Void> session,
      Pointer<Int32> edgeCount,
      Pointer<Int32> edgeStride,
    );

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

typedef _BranchCreateNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> name,
      Pointer<Utf8> startPoint,
      Int32 checkoutAfter,
      Int32 setUpstream,
      Pointer<Utf8> upstream,
    );
typedef BranchCreateDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> name,
      Pointer<Utf8> startPoint,
      int checkoutAfter,
      int setUpstream,
      Pointer<Utf8> upstream,
    );

typedef _BranchRenameNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> from,
      Pointer<Utf8> to,
      Int32 force,
      Int32 renameRemote,
      Pointer<Utf8> remoteName,
    );
typedef BranchRenameDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> from,
      Pointer<Utf8> to,
      int force,
      int renameRemote,
      Pointer<Utf8> remoteName,
    );

typedef _BranchDeleteNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> names,
      Int32 nameCount,
      Int32 force,
      Int32 isRemote,
      Pointer<Utf8> remoteName,
    );
typedef BranchDeleteDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> names,
      int nameCount,
      int force,
      int isRemote,
      Pointer<Utf8> remoteName,
    );

typedef _ResetToNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> target, Int32 mode);
typedef ResetToDart =
    void Function(Pointer<Void> session, Pointer<Utf8> target, int mode);

typedef _MergeBranchNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> target,
      Int32 mode,
      Pointer<Utf8> message,
      Int32 stashFirst,
    );
typedef MergeBranchDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> target,
      int mode,
      Pointer<Utf8> message,
      int stashFirst,
    );

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

typedef _CherryPickContinueWithMessageNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> message);
typedef CherryPickContinueWithMessageDart =
    void Function(Pointer<Void> session, Pointer<Utf8> message);

typedef _RequestOriginalOperationMessageNative =
    Void Function(Pointer<Void> session);
typedef RequestOriginalOperationMessageDart =
    void Function(Pointer<Void> session);

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
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> commitHexes,
      int commitCount,
      int noCommit,
      int stashFirst,
    );

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

typedef _RequestWorkingTreeContentNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> path);
typedef RequestWorkingTreeContentDart =
    void Function(Pointer<Void> session, Pointer<Utf8> path);

typedef _ExportFileAtRevisionNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> revision,
      Pointer<Utf8> path,
      Pointer<Utf8> destPath,
    );
typedef ExportFileAtRevisionDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> revision,
      Pointer<Utf8> path,
      Pointer<Utf8> destPath,
    );

typedef _ParseConflictMarkersNative = Int32 Function(Pointer<Utf8> content);
typedef ParseConflictMarkersDart = int Function(Pointer<Utf8> content);

typedef _WorkingCopyRefreshNative = Void Function(Pointer<Void> session);
typedef WorkingCopyRefreshDart = void Function(Pointer<Void> session);

typedef _WorkingCopyStatusJsonNative = Int32 Function(Pointer<Void> session);
typedef WorkingCopyStatusJsonDart = int Function(Pointer<Void> session);

typedef _WorkingCopyDiffNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> path, Int32 staged);
typedef WorkingCopyDiffDart =
    void Function(Pointer<Void> session, Pointer<Utf8> path, int staged);

typedef _StageFilesNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      Int32 pathCount,
    );
typedef StageFilesDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      int pathCount,
    );

typedef _UnstageFilesNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      Int32 pathCount,
    );
typedef UnstageFilesDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      int pathCount,
    );

typedef _CommitChangesNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> message,
      Int32 amend,
      Int32 signOff,
    );
typedef CommitChangesDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> message,
      int amend,
      int signOff,
    );

typedef _StageHunkNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> path, Int32 hunkIndex);
typedef StageHunkDart =
    void Function(Pointer<Void> session, Pointer<Utf8> path, int hunkIndex);

typedef _StageLinesNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Int32 hunkIndex,
      Pointer<Int32> lineIndices,
      Int32 lineIndexCount,
    );
typedef StageLinesDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      int hunkIndex,
      Pointer<Int32> lineIndices,
      int lineIndexCount,
    );

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

typedef _StashApplyNative =
    Void Function(Pointer<Void> session, Int32 index, Int32 pop);
typedef StashApplyDart =
    void Function(Pointer<Void> session, int index, int pop);

typedef _StashDropNative = Void Function(Pointer<Void> session, Int32 index);
typedef StashDropDart = void Function(Pointer<Void> session, int index);

typedef _StashBranchNative =
    Void Function(Pointer<Void> session, Int32 index, Pointer<Utf8> branchName);
typedef StashBranchDart =
    void Function(Pointer<Void> session, int index, Pointer<Utf8> branchName);

typedef _StashRequestDiffNative =
    Void Function(Pointer<Void> session, Int32 index);
typedef StashRequestDiffDart = void Function(Pointer<Void> session, int index);

typedef _TagCreateNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> name,
      Pointer<Utf8> target,
      Pointer<Utf8> message,
      Int32 force,
    );
typedef TagCreateDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> name,
      Pointer<Utf8> target,
      Pointer<Utf8> message,
      int force,
    );

typedef _TagDeleteNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> name,
      Int32 alsoRemote,
      Pointer<Utf8> remoteName,
    );
typedef TagDeleteDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> name,
      int alsoRemote,
      Pointer<Utf8> remoteName,
    );

typedef _TagPushNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Utf8> name,
    );
typedef TagPushDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Utf8> name,
    );

typedef _WorktreeRefreshNative = Void Function(Pointer<Void> session);
typedef WorktreeRefreshDart = void Function(Pointer<Void> session);
typedef _WorktreeRequestPendingCountsNative =
    Void Function(Pointer<Void> session);
typedef WorktreeRequestPendingCountsDart = void Function(Pointer<Void> session);

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

typedef _WorktreeRemoveNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> path, Int32 force);
typedef WorktreeRemoveDart =
    void Function(Pointer<Void> session, Pointer<Utf8> path, int force);

typedef _WorktreePruneNative = Void Function(Pointer<Void> session);
typedef WorktreePruneDart = void Function(Pointer<Void> session);

typedef _WorktreeLockNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Pointer<Utf8> reason,
    );
typedef WorktreeLockDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Pointer<Utf8> reason,
    );

typedef _WorktreeUnlockNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> path);
typedef WorktreeUnlockDart =
    void Function(Pointer<Void> session, Pointer<Utf8> path);

typedef _RemoteRefreshNative = Void Function(Pointer<Void> session);
typedef RemoteRefreshDart = void Function(Pointer<Void> session);

typedef _RemotesJsonNative = Int32 Function(Pointer<Void> session);
typedef RemotesJsonDart = int Function(Pointer<Void> session);

typedef _RemoteFetchNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Pointer<Utf8>> refs,
      Int32 refCount,
      Int32 prune,
      Int32 tags,
    );
typedef RemoteFetchDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Pointer<Utf8>> refs,
      int refCount,
      int prune,
      int tags,
    );

typedef _PullNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Utf8> branch,
      Int32 rebase,
      Int32 stashFirst,
    );
typedef PullDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Utf8> branch,
      int rebase,
      int stashFirst,
    );

typedef _PushNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Pointer<Utf8>> branches,
      Int32 branchCount,
      Int32 setUpstream,
      Int32 pushTags,
      Int32 forceWithLease,
    );
typedef PushDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Pointer<Utf8>> branches,
      int branchCount,
      int setUpstream,
      int pushTags,
      int forceWithLease,
    );

typedef _ProvideCredentialNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> secret);
typedef ProvideCredentialDart =
    void Function(Pointer<Void> session, Pointer<Utf8> secret);

typedef _CancelCredentialNative = Void Function(Pointer<Void> session);
typedef CancelCredentialDart = void Function(Pointer<Void> session);

typedef _RequestBlameNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Pointer<Utf8> revision,
      Int32 startLine,
      Int32 endLine,
    );
typedef RequestBlameDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Pointer<Utf8> revision,
      int startLine,
      int endLine,
    );

typedef _RequestCommitMetaNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> oids,
      Int32 oidCount,
    );
typedef RequestCommitMetaDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> oids,
      int oidCount,
    );

typedef _RequestCommitFileCountsNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> oids,
      Int32 oidCount,
    );
typedef RequestCommitFileCountsDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> oids,
      int oidCount,
    );

typedef _RequestCommitFilesNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> oid);
typedef RequestCommitFilesDart =
    void Function(Pointer<Void> session, Pointer<Utf8> oid);

typedef _RequestCommitFileDiffNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> oid, Pointer<Utf8> path);
typedef RequestCommitFileDiffDart =
    void Function(Pointer<Void> session, Pointer<Utf8> oid, Pointer<Utf8> path);

typedef _RequestCompareRefsNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> leftRef,
      Pointer<Utf8> rightRef,
      Int32 threeDot,
    );
typedef RequestCompareRefsDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> leftRef,
      Pointer<Utf8> rightRef,
      int threeDot,
    );

typedef _RequestCompareFileDiffNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> leftRef,
      Pointer<Utf8> rightRef,
      Int32 threeDot,
      Pointer<Utf8> path,
    );
typedef RequestCompareFileDiffDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> leftRef,
      Pointer<Utf8> rightRef,
      int threeDot,
      Pointer<Utf8> path,
    );

typedef _RequestRemotePrunePreviewNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> remoteName);
typedef RequestRemotePrunePreviewDart =
    void Function(Pointer<Void> session, Pointer<Utf8> remoteName);

typedef _RequestCompareWithWorkingCopyNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> ref);
typedef RequestCompareWithWorkingCopyDart =
    void Function(Pointer<Void> session, Pointer<Utf8> ref);

typedef _RemotePruneNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Pointer<Utf8>> refs,
      Int32 refCount,
    );
typedef RemotePruneDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> remoteName,
      Pointer<Pointer<Utf8>> refs,
      int refCount,
    );

typedef _RemoteAddNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> name, Pointer<Utf8> url);
typedef RemoteAddDart =
    void Function(Pointer<Void> session, Pointer<Utf8> name, Pointer<Utf8> url);

typedef _RemoteRemoveNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> name);
typedef RemoteRemoveDart =
    void Function(Pointer<Void> session, Pointer<Utf8> name);

typedef _RequestFileHistoryNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Pointer<Utf8> startRevision,
    );
typedef RequestFileHistoryDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Pointer<Utf8> startRevision,
    );

typedef _RequestLineHistoryNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      Int32 startLine,
      Int32 endLine,
      Pointer<Utf8> startRevision,
    );
typedef RequestLineHistoryDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> path,
      int startLine,
      int endLine,
      Pointer<Utf8> startRevision,
    );

typedef _RequestReflogNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> ref);
typedef RequestReflogDart =
    void Function(Pointer<Void> session, Pointer<Utf8> ref);

typedef _UndoJournalJsonNative = Int32 Function(Pointer<Void> session);
typedef UndoJournalJsonDart = int Function(Pointer<Void> session);

typedef _UndoLastNative = Void Function(Pointer<Void> session);
typedef UndoLastDart = void Function(Pointer<Void> session);

typedef _RestorePathsNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      Int32 pathCount,
      Int32 staged,
      Pointer<Utf8> source,
    );
typedef RestorePathsDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      int pathCount,
      int staged,
      Pointer<Utf8> source,
    );

typedef _CleanPreviewNative =
    Void Function(Pointer<Void> session, Int32 includeIgnored);
typedef CleanPreviewDart =
    void Function(Pointer<Void> session, int includeIgnored);

typedef _CleanUntrackedNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      Int32 pathCount,
      Int32 includeIgnored,
    );
typedef CleanUntrackedDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      int pathCount,
      int includeIgnored,
    );

typedef _RequestRebasePlanNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> upstream);
typedef RequestRebasePlanDart =
    void Function(Pointer<Void> session, Pointer<Utf8> upstream);

typedef _RebaseInteractiveStartNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> upstream,
      Pointer<Utf8> onto,
      Pointer<Int32> actions,
      Pointer<Pointer<Utf8>> oids,
      Pointer<Pointer<Utf8>> subjects,
      Int32 entryCount,
      Int32 stashFirst,
    );
typedef RebaseInteractiveStartDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> upstream,
      Pointer<Utf8> onto,
      Pointer<Int32> actions,
      Pointer<Pointer<Utf8>> oids,
      Pointer<Pointer<Utf8>> subjects,
      int entryCount,
      int stashFirst,
    );

typedef _RebaseStartNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> upstream,
      Pointer<Utf8> onto,
      Int32 stashFirst,
      Int32 rebaseMerges,
      Int32 autosquash,
    );
typedef RebaseStartDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> upstream,
      Pointer<Utf8> onto,
      int stashFirst,
      int rebaseMerges,
      int autosquash,
    );

typedef _RebaseContinueNative = Void Function(Pointer<Void> session);
typedef RebaseContinueDart = void Function(Pointer<Void> session);

typedef _RebaseContinueWithMessageNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> message);
typedef RebaseContinueWithMessageDart =
    void Function(Pointer<Void> session, Pointer<Utf8> message);

typedef _RebaseSkipNative = Void Function(Pointer<Void> session);
typedef RebaseSkipDart = void Function(Pointer<Void> session);

typedef _RebaseAbortNative = Void Function(Pointer<Void> session);
typedef RebaseAbortDart = void Function(Pointer<Void> session);

typedef _SubmoduleRefreshNative = Void Function(Pointer<Void> session);
typedef SubmoduleRefreshDart = void Function(Pointer<Void> session);

typedef _SubmodulesJsonNative = Int32 Function(Pointer<Void> session);
typedef SubmodulesJsonDart = int Function(Pointer<Void> session);

typedef _SubmoduleAddNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> url,
      Pointer<Utf8> path,
      Pointer<Utf8> branch,
    );
typedef SubmoduleAddDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> url,
      Pointer<Utf8> path,
      Pointer<Utf8> branch,
    );

typedef _SubmoduleInitNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      Int32 pathCount,
      Int32 recursive,
    );
typedef SubmoduleInitDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      int pathCount,
      int recursive,
    );

typedef _SubmoduleUpdateNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      Int32 pathCount,
      Int32 recursive,
      Int32 init,
      Int32 remote,
    );
typedef SubmoduleUpdateDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      int pathCount,
      int recursive,
      int init,
      int remote,
    );

typedef _SubmoduleSyncNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      Int32 pathCount,
      Int32 recursive,
    );
typedef SubmoduleSyncDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      int pathCount,
      int recursive,
    );

typedef _SubmoduleDeinitNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      Int32 pathCount,
      Int32 force,
    );
typedef SubmoduleDeinitDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> paths,
      int pathCount,
      int force,
    );

typedef _BisectRefreshNative = Void Function(Pointer<Void> session);
typedef BisectRefreshDart = void Function(Pointer<Void> session);

typedef _BisectStatusJsonNative = Int32 Function(Pointer<Void> session);
typedef BisectStatusJsonDart = int Function(Pointer<Void> session);

typedef _BisectStartNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> badRef,
      Pointer<Pointer<Utf8>> goodRefs,
      Int32 goodCount,
      Pointer<Pointer<Utf8>> paths,
      Int32 pathCount,
      Int32 noCheckout,
    );
typedef BisectStartDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> badRef,
      Pointer<Pointer<Utf8>> goodRefs,
      int goodCount,
      Pointer<Pointer<Utf8>> paths,
      int pathCount,
      int noCheckout,
    );

typedef _BisectMarkNative =
    Void Function(Pointer<Void> session, Int32 good, Pointer<Utf8> ref);
typedef BisectMarkDart =
    void Function(Pointer<Void> session, int good, Pointer<Utf8> ref);

typedef _BisectSkipNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> refs,
      Int32 refCount,
    );
typedef BisectSkipDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> refs,
      int refCount,
    );

typedef _BisectResetNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> target);
typedef BisectResetDart =
    void Function(Pointer<Void> session, Pointer<Utf8> target);

typedef _LfsRefreshNative = Void Function(Pointer<Void> session);
typedef LfsRefreshDart = void Function(Pointer<Void> session);

typedef _LfsInstallationJsonNative = Int32 Function(Pointer<Void> session);
typedef LfsInstallationJsonDart = int Function(Pointer<Void> session);

typedef _LfsPatternsJsonNative = Int32 Function(Pointer<Void> session);
typedef LfsPatternsJsonDart = int Function(Pointer<Void> session);

typedef _LfsFilesJsonNative = Int32 Function(Pointer<Void> session);
typedef LfsFilesJsonDart = int Function(Pointer<Void> session);

typedef _LfsInstallNative = Void Function(Pointer<Void> session);
typedef LfsInstallDart = void Function(Pointer<Void> session);

typedef _LfsTrackNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> pattern);
typedef LfsTrackDart =
    void Function(Pointer<Void> session, Pointer<Utf8> pattern);

typedef _LfsUntrackNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> pattern);
typedef LfsUntrackDart =
    void Function(Pointer<Void> session, Pointer<Utf8> pattern);

typedef _LfsPullNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> remoteName);
typedef LfsPullDart =
    void Function(Pointer<Void> session, Pointer<Utf8> remoteName);

typedef _LfsFetchNative =
    Void Function(Pointer<Void> session, Pointer<Utf8> remoteName);
typedef LfsFetchDart =
    void Function(Pointer<Void> session, Pointer<Utf8> remoteName);

typedef _LfsPruneNative = Void Function(Pointer<Void> session, Int32 dryRun);
typedef LfsPruneDart = void Function(Pointer<Void> session, int dryRun);

typedef _PatchExportNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> commitHexes,
      Int32 commitCount,
      Pointer<Utf8> outputDir,
    );
typedef PatchExportDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> commitHexes,
      int commitCount,
      Pointer<Utf8> outputDir,
    );

typedef _PatchApplyFilesNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> patchFiles,
      Int32 fileCount,
      Int32 threeWay,
      Int32 updateIndex,
    );
typedef PatchApplyFilesDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> patchFiles,
      int fileCount,
      int threeWay,
      int updateIndex,
    );

typedef _PatchImportNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> patchFiles,
      Int32 fileCount,
      Int32 threeWay,
    );
typedef PatchImportDart =
    void Function(
      Pointer<Void> session,
      Pointer<Pointer<Utf8>> patchFiles,
      int fileCount,
      int threeWay,
    );

typedef _PatchImportContinueNative = Void Function(Pointer<Void> session);
typedef PatchImportContinueDart = void Function(Pointer<Void> session);

typedef _PatchImportSkipNative = Void Function(Pointer<Void> session);
typedef PatchImportSkipDart = void Function(Pointer<Void> session);

typedef _PatchImportAbortNative = Void Function(Pointer<Void> session);
typedef PatchImportAbortDart = void Function(Pointer<Void> session);

typedef _LocalIdentityRefreshNative = Void Function(Pointer<Void> session);
typedef LocalIdentityRefreshDart = void Function(Pointer<Void> session);

typedef _LocalIdentityJsonNative = Int32 Function(Pointer<Void> session);
typedef LocalIdentityJsonDart = int Function(Pointer<Void> session);

typedef _EffectiveIdentityRefreshNative = Void Function(Pointer<Void> session);
typedef EffectiveIdentityRefreshDart = void Function(Pointer<Void> session);

typedef _EffectiveIdentityJsonNative = Int32 Function(Pointer<Void> session);
typedef EffectiveIdentityJsonDart = int Function(Pointer<Void> session);

typedef _SetLocalIdentityNative =
    Void Function(
      Pointer<Void> session,
      Pointer<Utf8> name,
      Pointer<Utf8> email,
    );
typedef SetLocalIdentityDart =
    void Function(
      Pointer<Void> session,
      Pointer<Utf8> name,
      Pointer<Utf8> email,
    );

typedef _ClearLocalIdentityNative = Void Function(Pointer<Void> session);
typedef ClearLocalIdentityDart = void Function(Pointer<Void> session);

typedef _HasCommitGraphNative = Int32 Function(Pointer<Void> session);
typedef HasCommitGraphDart = int Function(Pointer<Void> session);

typedef _WriteCommitGraphNative = Void Function(Pointer<Void> session);
typedef WriteCommitGraphDart = void Function(Pointer<Void> session);

typedef _RepoInitNative = Int32 Function(Pointer<Utf8> path);
typedef RepoInitDart = int Function(Pointer<Utf8> path);

typedef _RepoCloneNative =
    Int32 Function(Pointer<Utf8> url, Pointer<Utf8> destPath);
typedef RepoCloneDart = int Function(Pointer<Utf8> url, Pointer<Utf8> destPath);

typedef _DiscoveryOpenNative = Pointer<Void> Function(Pointer<Utf8> dbPath);
typedef DiscoveryOpenDart = Pointer<Void> Function(Pointer<Utf8> dbPath);

typedef _DiscoveryCloseNative = Void Function(Pointer<Void> discovery);
typedef DiscoveryCloseDart = void Function(Pointer<Void> discovery);

typedef _DiscoveryAddBaseFolderNative =
    Int64 Function(
      Pointer<Void> discovery,
      Pointer<Utf8> path,
      Int32 maxDepth,
      Int32 followLinks,
    );
typedef DiscoveryAddBaseFolderDart =
    int Function(
      Pointer<Void> discovery,
      Pointer<Utf8> path,
      int maxDepth,
      int followLinks,
    );

typedef _DiscoveryScanAllNative = Int32 Function(Pointer<Void> discovery);
typedef DiscoveryScanAllDart = int Function(Pointer<Void> discovery);

typedef _DiscoveryListReposJsonNative = Int32 Function(Pointer<Void> discovery);
typedef DiscoveryListReposJsonDart = int Function(Pointer<Void> discovery);

typedef _DiscoveryBaseFoldersJsonNative =
    Int32 Function(Pointer<Void> discovery);
typedef DiscoveryBaseFoldersJsonDart = int Function(Pointer<Void> discovery);

typedef _DiscoveryRemoveBaseFolderNative =
    Int32 Function(Pointer<Void> discovery, Int64 baseFolderId);
typedef DiscoveryRemoveBaseFolderDart =
    int Function(Pointer<Void> discovery, int baseFolderId);

typedef _DiscoverySetBaseFolderEnabledNative =
    Int32 Function(Pointer<Void> discovery, Int64 baseFolderId, Int32 enabled);
typedef DiscoverySetBaseFolderEnabledDart =
    int Function(Pointer<Void> discovery, int baseFolderId, int enabled);

typedef _DiscoverySetBaseFolderDepthNative =
    Int32 Function(Pointer<Void> discovery, Int64 baseFolderId, Int32 maxDepth);
typedef DiscoverySetBaseFolderDepthDart =
    int Function(Pointer<Void> discovery, int baseFolderId, int maxDepth);

/// Thin, allocation-free wrapper around the `gbm_capi` symbol table. One
/// instance per isolate is enough; construct it once via [GbmBindings.open]
/// and share it through a Riverpod provider.
class GbmBindings {
  /// Resolves the native library (see [openGbmCapiLibrary]) and looks up
  /// every symbol.
  factory GbmBindings.open() => GbmBindings(openGbmCapiLibrary());

  GbmBindings(DynamicLibrary library)
    : freeEventPayload = library
          .lookupFunction<_FreeEventPayloadNative, FreeEventPayloadDart>(
            'gbm_free_event_payload',
          ),
      lastResultJsonLen = library
          .lookupFunction<_LastResultJsonLenNative, LastResultJsonLenDart>(
            'gbm_last_result_json_len',
          ),
      lastResultJsonCopy = library
          .lookupFunction<_LastResultJsonCopyNative, LastResultJsonCopyDart>(
            'gbm_last_result_json_copy',
          ),
      sessionOpen = library.lookupFunction<_SessionOpenNative, SessionOpenDart>(
        'gbm_session_open',
      ),
      sessionClose = library
          .lookupFunction<_SessionCloseNative, SessionCloseDart>(
            'gbm_session_close',
          ),
      registerCallback = library
          .lookupFunction<_RegisterCallbackNative, RegisterCallbackDart>(
            'gbm_register_callback',
          ),
      repoStateJson = library
          .lookupFunction<_RepoStateJsonNative, RepoStateJsonDart>(
            'gbm_repo_state_json',
          ),
      removeStaleIndexLock = library
          .lookupFunction<
            _RemoveStaleIndexLockNative,
            RemoveStaleIndexLockDart
          >('gbm_operation_remove_stale_index_lock'),
      historyRefresh = library
          .lookupFunction<_HistoryRefreshNative, HistoryRefreshDart>(
            'gbm_history_refresh',
          ),
      historySetFilter = library
          .lookupFunction<_HistorySetFilterNative, HistorySetFilterDart>(
            'gbm_history_set_filter',
          ),
      refsJson = library.lookupFunction<_RefsJsonNative, RefsJsonDart>(
        'gbm_refs_json',
      ),
      graphSnapshotRows = library
          .lookupFunction<_GraphRowsNative, GraphRowsDart>(
            'gbm_graph_snapshot_rows',
          ),
      graphSnapshotOids = library
          .lookupFunction<_GraphOidsNative, GraphOidsDart>(
            'gbm_graph_snapshot_oids',
          ),
      graphSnapshotParents = library
          .lookupFunction<_GraphParentsNative, GraphParentsDart>(
            'gbm_graph_snapshot_parents',
          ),
      graphSnapshotEdges = library
          .lookupFunction<_GraphEdgesNative, GraphEdgesDart>(
            'gbm_graph_snapshot_edges',
          ),
      graphSnapshotLaneCount = library
          .lookupFunction<_GraphIntQueryNative, GraphIntQueryDart>(
            'gbm_graph_snapshot_lane_count',
          ),
      graphSnapshotComplete = library
          .lookupFunction<_GraphIntQueryNative, GraphIntQueryDart>(
            'gbm_graph_snapshot_complete',
          ),
      graphSnapshotTruncated = library
          .lookupFunction<_GraphIntQueryNative, GraphIntQueryDart>(
            'gbm_graph_snapshot_truncated',
          ),
      graphSnapshotRelease = library
          .lookupFunction<_GraphReleaseNative, GraphReleaseDart>(
            'gbm_graph_snapshot_release',
          ),
      branchCheckout = library
          .lookupFunction<_BranchCheckoutNative, BranchCheckoutDart>(
            'gbm_branch_checkout',
          ),
      branchCreate = library
          .lookupFunction<_BranchCreateNative, BranchCreateDart>(
            'gbm_branch_create',
          ),
      branchRename = library
          .lookupFunction<_BranchRenameNative, BranchRenameDart>(
            'gbm_branch_rename',
          ),
      branchDelete = library
          .lookupFunction<_BranchDeleteNative, BranchDeleteDart>(
            'gbm_branch_delete',
          ),
      resetTo = library.lookupFunction<_ResetToNative, ResetToDart>(
        'gbm_reset_to',
      ),
      mergeBranch = library.lookupFunction<_MergeBranchNative, MergeBranchDart>(
        'gbm_merge_branch',
      ),
      mergeAbort = library.lookupFunction<_MergeAbortNative, MergeAbortDart>(
        'gbm_merge_abort',
      ),
      cherryPick = library.lookupFunction<_CherryPickNative, CherryPickDart>(
        'gbm_cherry_pick',
      ),
      cherryPickContinue = library
          .lookupFunction<_CherryPickContinueNative, CherryPickContinueDart>(
            'gbm_cherry_pick_continue',
          ),
      cherryPickContinueWithMessage = library
          .lookupFunction<
            _CherryPickContinueWithMessageNative,
            CherryPickContinueWithMessageDart
          >('gbm_cherry_pick_continue_with_message'),
      requestOriginalOperationMessage = library
          .lookupFunction<
            _RequestOriginalOperationMessageNative,
            RequestOriginalOperationMessageDart
          >('gbm_request_original_operation_message'),
      cherryPickSkip = library
          .lookupFunction<_CherryPickSkipNative, CherryPickSkipDart>(
            'gbm_cherry_pick_skip',
          ),
      cherryPickAbort = library
          .lookupFunction<_CherryPickAbortNative, CherryPickAbortDart>(
            'gbm_cherry_pick_abort',
          ),
      revert = library.lookupFunction<_RevertNative, RevertDart>('gbm_revert'),
      resolveConflict = library
          .lookupFunction<_ResolveConflictNative, ResolveConflictDart>(
            'gbm_resolve_conflict',
          ),
      requestWorkingTreeContent = library
          .lookupFunction<
            _RequestWorkingTreeContentNative,
            RequestWorkingTreeContentDart
          >('gbm_request_working_tree_content'),
      exportFileAtRevision = library
          .lookupFunction<
            _ExportFileAtRevisionNative,
            ExportFileAtRevisionDart
          >('gbm_export_file_at_revision'),
      parseConflictMarkers = library
          .lookupFunction<
            _ParseConflictMarkersNative,
            ParseConflictMarkersDart
          >('gbm_parse_conflict_markers'),
      workingCopyRefresh = library
          .lookupFunction<_WorkingCopyRefreshNative, WorkingCopyRefreshDart>(
            'gbm_working_copy_refresh',
          ),
      workingCopyStatusJson = library
          .lookupFunction<
            _WorkingCopyStatusJsonNative,
            WorkingCopyStatusJsonDart
          >('gbm_working_copy_status_json'),
      workingCopyDiff = library
          .lookupFunction<_WorkingCopyDiffNative, WorkingCopyDiffDart>(
            'gbm_working_copy_diff',
          ),
      stageFiles = library.lookupFunction<_StageFilesNative, StageFilesDart>(
        'gbm_stage_files',
      ),
      unstageFiles = library
          .lookupFunction<_UnstageFilesNative, UnstageFilesDart>(
            'gbm_unstage_files',
          ),
      stageHunk = library.lookupFunction<_StageHunkNative, StageHunkDart>(
        'gbm_stage_hunk',
      ),
      unstageHunk = library.lookupFunction<_StageHunkNative, StageHunkDart>(
        'gbm_unstage_hunk',
      ),
      stageLines = library.lookupFunction<_StageLinesNative, StageLinesDart>(
        'gbm_stage_lines',
      ),
      unstageLines = library.lookupFunction<_StageLinesNative, StageLinesDart>(
        'gbm_unstage_lines',
      ),
      discardLines = library.lookupFunction<_StageLinesNative, StageLinesDart>(
        'gbm_discard_lines',
      ),
      commitChanges = library
          .lookupFunction<_CommitChangesNative, CommitChangesDart>(
            'gbm_commit_changes',
          ),
      stashRefresh = library
          .lookupFunction<_StashRefreshNative, StashRefreshDart>(
            'gbm_stash_refresh',
          ),
      stashesJson = library.lookupFunction<_StashesJsonNative, StashesJsonDart>(
        'gbm_stashes_json',
      ),
      stashSave = library.lookupFunction<_StashSaveNative, StashSaveDart>(
        'gbm_stash_save',
      ),
      stashApply = library.lookupFunction<_StashApplyNative, StashApplyDart>(
        'gbm_stash_apply',
      ),
      stashDrop = library.lookupFunction<_StashDropNative, StashDropDart>(
        'gbm_stash_drop',
      ),
      stashBranch = library.lookupFunction<_StashBranchNative, StashBranchDart>(
        'gbm_stash_branch',
      ),
      stashRequestDiff = library
          .lookupFunction<_StashRequestDiffNative, StashRequestDiffDart>(
            'gbm_stash_request_diff',
          ),
      tagCreate = library.lookupFunction<_TagCreateNative, TagCreateDart>(
        'gbm_tag_create',
      ),
      tagDelete = library.lookupFunction<_TagDeleteNative, TagDeleteDart>(
        'gbm_tag_delete',
      ),
      tagPush = library.lookupFunction<_TagPushNative, TagPushDart>(
        'gbm_tag_push',
      ),
      worktreeRefresh = library
          .lookupFunction<_WorktreeRefreshNative, WorktreeRefreshDart>(
            'gbm_worktree_refresh',
          ),
      worktreeRequestPendingCounts = library
          .lookupFunction<
            _WorktreeRequestPendingCountsNative,
            WorktreeRequestPendingCountsDart
          >('gbm_worktree_request_pending_counts'),
      worktreesJson = library
          .lookupFunction<_WorktreesJsonNative, WorktreesJsonDart>(
            'gbm_worktrees_json',
          ),
      worktreeAdd = library.lookupFunction<_WorktreeAddNative, WorktreeAddDart>(
        'gbm_worktree_add',
      ),
      worktreeRemove = library
          .lookupFunction<_WorktreeRemoveNative, WorktreeRemoveDart>(
            'gbm_worktree_remove',
          ),
      worktreePrune = library
          .lookupFunction<_WorktreePruneNative, WorktreePruneDart>(
            'gbm_worktree_prune',
          ),
      worktreeLock = library
          .lookupFunction<_WorktreeLockNative, WorktreeLockDart>(
            'gbm_worktree_lock',
          ),
      worktreeUnlock = library
          .lookupFunction<_WorktreeUnlockNative, WorktreeUnlockDart>(
            'gbm_worktree_unlock',
          ),
      remoteRefresh = library
          .lookupFunction<_RemoteRefreshNative, RemoteRefreshDart>(
            'gbm_remote_refresh',
          ),
      remotesJson = library.lookupFunction<_RemotesJsonNative, RemotesJsonDart>(
        'gbm_remotes_json',
      ),
      remoteFetch = library.lookupFunction<_RemoteFetchNative, RemoteFetchDart>(
        'gbm_remote_fetch',
      ),
      pull = library.lookupFunction<_PullNative, PullDart>('gbm_pull'),
      push = library.lookupFunction<_PushNative, PushDart>('gbm_push'),
      provideCredential = library
          .lookupFunction<_ProvideCredentialNative, ProvideCredentialDart>(
            'gbm_provide_credential',
          ),
      cancelCredential = library
          .lookupFunction<_CancelCredentialNative, CancelCredentialDart>(
            'gbm_cancel_credential',
          ),
      requestBlame = library
          .lookupFunction<_RequestBlameNative, RequestBlameDart>(
            'gbm_request_blame',
          ),
      requestCommitMeta = library
          .lookupFunction<_RequestCommitMetaNative, RequestCommitMetaDart>(
            'gbm_request_commit_meta',
          ),
      requestCommitFileCounts = library
          .lookupFunction<
            _RequestCommitFileCountsNative,
            RequestCommitFileCountsDart
          >('gbm_request_commit_file_counts'),
      requestCommitFiles = library
          .lookupFunction<_RequestCommitFilesNative, RequestCommitFilesDart>(
            'gbm_request_commit_files',
          ),
      requestCommitFileDiff = library
          .lookupFunction<
            _RequestCommitFileDiffNative,
            RequestCommitFileDiffDart
          >('gbm_request_commit_file_diff'),
      requestCompareRefs = library
          .lookupFunction<_RequestCompareRefsNative, RequestCompareRefsDart>(
            'gbm_request_compare_refs',
          ),
      requestCompareFileDiff = library
          .lookupFunction<
            _RequestCompareFileDiffNative,
            RequestCompareFileDiffDart
          >('gbm_request_compare_file_diff'),
      requestRemotePrunePreview = library
          .lookupFunction<
            _RequestRemotePrunePreviewNative,
            RequestRemotePrunePreviewDart
          >('gbm_request_remote_prune_preview'),
      remotePrune = library.lookupFunction<_RemotePruneNative, RemotePruneDart>(
        'gbm_remote_prune',
      ),
      remoteAdd = library.lookupFunction<_RemoteAddNative, RemoteAddDart>(
        'gbm_remote_add',
      ),
      remoteRemove = library
          .lookupFunction<_RemoteRemoveNative, RemoteRemoveDart>(
            'gbm_remote_remove',
          ),
      requestCompareWithWorkingCopy = library
          .lookupFunction<
            _RequestCompareWithWorkingCopyNative,
            RequestCompareWithWorkingCopyDart
          >('gbm_request_compare_with_working_copy'),
      requestFileHistory = library
          .lookupFunction<_RequestFileHistoryNative, RequestFileHistoryDart>(
            'gbm_request_file_history',
          ),
      requestLineHistory = library
          .lookupFunction<_RequestLineHistoryNative, RequestLineHistoryDart>(
            'gbm_request_line_history',
          ),
      requestReflog = library
          .lookupFunction<_RequestReflogNative, RequestReflogDart>(
            'gbm_request_reflog',
          ),
      undoJournalJson = library
          .lookupFunction<_UndoJournalJsonNative, UndoJournalJsonDart>(
            'gbm_undo_journal_json',
          ),
      undoLast = library.lookupFunction<_UndoLastNative, UndoLastDart>(
        'gbm_undo_last',
      ),
      restorePaths = library
          .lookupFunction<_RestorePathsNative, RestorePathsDart>(
            'gbm_restore_paths',
          ),
      cleanPreview = library
          .lookupFunction<_CleanPreviewNative, CleanPreviewDart>(
            'gbm_clean_preview',
          ),
      cleanUntracked = library
          .lookupFunction<_CleanUntrackedNative, CleanUntrackedDart>(
            'gbm_clean_untracked',
          ),
      requestRebasePlan = library
          .lookupFunction<_RequestRebasePlanNative, RequestRebasePlanDart>(
            'gbm_request_rebase_plan',
          ),
      rebaseInteractiveStart = library
          .lookupFunction<
            _RebaseInteractiveStartNative,
            RebaseInteractiveStartDart
          >('gbm_rebase_interactive_start'),
      rebaseStart = library.lookupFunction<_RebaseStartNative, RebaseStartDart>(
        'gbm_rebase_start',
      ),
      rebaseContinue = library
          .lookupFunction<_RebaseContinueNative, RebaseContinueDart>(
            'gbm_rebase_continue',
          ),
      rebaseContinueWithMessage = library
          .lookupFunction<
            _RebaseContinueWithMessageNative,
            RebaseContinueWithMessageDart
          >('gbm_rebase_continue_with_message'),
      rebaseSkip = library.lookupFunction<_RebaseSkipNative, RebaseSkipDart>(
        'gbm_rebase_skip',
      ),
      rebaseAbort = library.lookupFunction<_RebaseAbortNative, RebaseAbortDart>(
        'gbm_rebase_abort',
      ),
      submoduleRefresh = library
          .lookupFunction<_SubmoduleRefreshNative, SubmoduleRefreshDart>(
            'gbm_submodule_refresh',
          ),
      submodulesJson = library
          .lookupFunction<_SubmodulesJsonNative, SubmodulesJsonDart>(
            'gbm_submodules_json',
          ),
      submoduleAdd = library
          .lookupFunction<_SubmoduleAddNative, SubmoduleAddDart>(
            'gbm_submodule_add',
          ),
      submoduleInit = library
          .lookupFunction<_SubmoduleInitNative, SubmoduleInitDart>(
            'gbm_submodule_init',
          ),
      submoduleUpdate = library
          .lookupFunction<_SubmoduleUpdateNative, SubmoduleUpdateDart>(
            'gbm_submodule_update',
          ),
      submoduleSync = library
          .lookupFunction<_SubmoduleSyncNative, SubmoduleSyncDart>(
            'gbm_submodule_sync',
          ),
      submoduleDeinit = library
          .lookupFunction<_SubmoduleDeinitNative, SubmoduleDeinitDart>(
            'gbm_submodule_deinit',
          ),
      bisectRefresh = library
          .lookupFunction<_BisectRefreshNative, BisectRefreshDart>(
            'gbm_bisect_refresh',
          ),
      bisectStatusJson = library
          .lookupFunction<_BisectStatusJsonNative, BisectStatusJsonDart>(
            'gbm_bisect_status_json',
          ),
      bisectStart = library.lookupFunction<_BisectStartNative, BisectStartDart>(
        'gbm_bisect_start',
      ),
      bisectMark = library.lookupFunction<_BisectMarkNative, BisectMarkDart>(
        'gbm_bisect_mark',
      ),
      bisectSkip = library.lookupFunction<_BisectSkipNative, BisectSkipDart>(
        'gbm_bisect_skip',
      ),
      bisectReset = library.lookupFunction<_BisectResetNative, BisectResetDart>(
        'gbm_bisect_reset',
      ),
      lfsRefresh = library.lookupFunction<_LfsRefreshNative, LfsRefreshDart>(
        'gbm_lfs_refresh',
      ),
      lfsInstallationJson = library
          .lookupFunction<_LfsInstallationJsonNative, LfsInstallationJsonDart>(
            'gbm_lfs_installation_json',
          ),
      lfsPatternsJson = library
          .lookupFunction<_LfsPatternsJsonNative, LfsPatternsJsonDart>(
            'gbm_lfs_patterns_json',
          ),
      lfsFilesJson = library
          .lookupFunction<_LfsFilesJsonNative, LfsFilesJsonDart>(
            'gbm_lfs_files_json',
          ),
      lfsInstall = library.lookupFunction<_LfsInstallNative, LfsInstallDart>(
        'gbm_lfs_install',
      ),
      lfsTrack = library.lookupFunction<_LfsTrackNative, LfsTrackDart>(
        'gbm_lfs_track',
      ),
      lfsUntrack = library.lookupFunction<_LfsUntrackNative, LfsUntrackDart>(
        'gbm_lfs_untrack',
      ),
      lfsPull = library.lookupFunction<_LfsPullNative, LfsPullDart>(
        'gbm_lfs_pull',
      ),
      lfsFetch = library.lookupFunction<_LfsFetchNative, LfsFetchDart>(
        'gbm_lfs_fetch',
      ),
      lfsPrune = library.lookupFunction<_LfsPruneNative, LfsPruneDart>(
        'gbm_lfs_prune',
      ),
      patchExport = library.lookupFunction<_PatchExportNative, PatchExportDart>(
        'gbm_patch_export',
      ),
      patchApplyFiles = library
          .lookupFunction<_PatchApplyFilesNative, PatchApplyFilesDart>(
            'gbm_patch_apply_files',
          ),
      patchImport = library.lookupFunction<_PatchImportNative, PatchImportDart>(
        'gbm_patch_import',
      ),
      patchImportContinue = library
          .lookupFunction<_PatchImportContinueNative, PatchImportContinueDart>(
            'gbm_patch_import_continue',
          ),
      patchImportSkip = library
          .lookupFunction<_PatchImportSkipNative, PatchImportSkipDart>(
            'gbm_patch_import_skip',
          ),
      patchImportAbort = library
          .lookupFunction<_PatchImportAbortNative, PatchImportAbortDart>(
            'gbm_patch_import_abort',
          ),
      localIdentityRefresh = library
          .lookupFunction<
            _LocalIdentityRefreshNative,
            LocalIdentityRefreshDart
          >('gbm_local_identity_refresh'),
      localIdentityJson = library
          .lookupFunction<_LocalIdentityJsonNative, LocalIdentityJsonDart>(
            'gbm_local_identity_json',
          ),
      effectiveIdentityRefresh = library
          .lookupFunction<
            _EffectiveIdentityRefreshNative,
            EffectiveIdentityRefreshDart
          >('gbm_effective_identity_refresh'),
      effectiveIdentityJson = library
          .lookupFunction<
            _EffectiveIdentityJsonNative,
            EffectiveIdentityJsonDart
          >('gbm_effective_identity_json'),
      setLocalIdentity = library
          .lookupFunction<_SetLocalIdentityNative, SetLocalIdentityDart>(
            'gbm_set_local_identity',
          ),
      clearLocalIdentity = library
          .lookupFunction<_ClearLocalIdentityNative, ClearLocalIdentityDart>(
            'gbm_clear_local_identity',
          ),
      hasCommitGraph = library
          .lookupFunction<_HasCommitGraphNative, HasCommitGraphDart>(
            'gbm_has_commit_graph',
          ),
      writeCommitGraph = library
          .lookupFunction<_WriteCommitGraphNative, WriteCommitGraphDart>(
            'gbm_write_commit_graph',
          ),
      repoInit = library.lookupFunction<_RepoInitNative, RepoInitDart>(
        'gbm_repo_init',
      ),
      repoClone = library.lookupFunction<_RepoCloneNative, RepoCloneDart>(
        'gbm_repo_clone',
      ),
      discoveryOpen = library
          .lookupFunction<_DiscoveryOpenNative, DiscoveryOpenDart>(
            'gbm_discovery_open',
          ),
      discoveryClose = library
          .lookupFunction<_DiscoveryCloseNative, DiscoveryCloseDart>(
            'gbm_discovery_close',
          ),
      discoveryAddBaseFolder = library
          .lookupFunction<
            _DiscoveryAddBaseFolderNative,
            DiscoveryAddBaseFolderDart
          >('gbm_discovery_add_base_folder'),
      discoveryScanAll = library
          .lookupFunction<_DiscoveryScanAllNative, DiscoveryScanAllDart>(
            'gbm_discovery_scan_all',
          ),
      discoveryListReposJson = library
          .lookupFunction<
            _DiscoveryListReposJsonNative,
            DiscoveryListReposJsonDart
          >('gbm_discovery_list_repos_json'),
      discoveryBaseFoldersJson = library
          .lookupFunction<
            _DiscoveryBaseFoldersJsonNative,
            DiscoveryBaseFoldersJsonDart
          >('gbm_discovery_base_folders_json'),
      discoveryRemoveBaseFolder = library
          .lookupFunction<
            _DiscoveryRemoveBaseFolderNative,
            DiscoveryRemoveBaseFolderDart
          >('gbm_discovery_remove_base_folder'),
      discoverySetBaseFolderEnabled = library
          .lookupFunction<
            _DiscoverySetBaseFolderEnabledNative,
            DiscoverySetBaseFolderEnabledDart
          >('gbm_discovery_set_base_folder_enabled'),
      discoverySetBaseFolderDepth = library
          .lookupFunction<
            _DiscoverySetBaseFolderDepthNative,
            DiscoverySetBaseFolderDepthDart
          >('gbm_discovery_set_base_folder_depth');

  final FreeEventPayloadDart freeEventPayload;
  final LastResultJsonLenDart lastResultJsonLen;
  final LastResultJsonCopyDart lastResultJsonCopy;
  final SessionOpenDart sessionOpen;
  final SessionCloseDart sessionClose;
  final RegisterCallbackDart registerCallback;
  final RepoStateJsonDart repoStateJson;
  final RemoveStaleIndexLockDart removeStaleIndexLock;
  final HistoryRefreshDart historyRefresh;
  final HistorySetFilterDart historySetFilter;
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
  final BranchCreateDart branchCreate;
  final BranchRenameDart branchRename;
  final BranchDeleteDart branchDelete;
  final ResetToDart resetTo;
  final MergeBranchDart mergeBranch;
  final MergeAbortDart mergeAbort;
  final CherryPickDart cherryPick;
  final CherryPickContinueDart cherryPickContinue;
  final CherryPickContinueWithMessageDart cherryPickContinueWithMessage;
  final RequestOriginalOperationMessageDart requestOriginalOperationMessage;
  final CherryPickSkipDart cherryPickSkip;
  final CherryPickAbortDart cherryPickAbort;
  final RevertDart revert;
  final ResolveConflictDart resolveConflict;
  final RequestWorkingTreeContentDart requestWorkingTreeContent;
  final ExportFileAtRevisionDart exportFileAtRevision;
  final ParseConflictMarkersDart parseConflictMarkers;
  final WorkingCopyRefreshDart workingCopyRefresh;
  final WorkingCopyStatusJsonDart workingCopyStatusJson;
  final WorkingCopyDiffDart workingCopyDiff;
  final StageFilesDart stageFiles;
  final UnstageFilesDart unstageFiles;
  final StageHunkDart stageHunk;
  final StageHunkDart unstageHunk;
  final StageLinesDart stageLines;
  final StageLinesDart unstageLines;

  /// Same signature as the two above, but rewrites the work tree instead of
  /// the index -- `git apply --reverse` without `--cached`. Destructive; see
  /// gbm_discard_lines()'s doc comment in gbm_capi.h.
  final StageLinesDart discardLines;
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
  final WorktreeRequestPendingCountsDart worktreeRequestPendingCounts;
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
  final RequestBlameDart requestBlame;
  final RequestCommitMetaDart requestCommitMeta;
  final RequestCommitFileCountsDart requestCommitFileCounts;
  final RequestCommitFilesDart requestCommitFiles;
  final RequestCommitFileDiffDart requestCommitFileDiff;
  final RequestCompareRefsDart requestCompareRefs;
  final RequestCompareFileDiffDart requestCompareFileDiff;
  final RequestRemotePrunePreviewDart requestRemotePrunePreview;
  final RemotePruneDart remotePrune;
  final RemoteAddDart remoteAdd;
  final RemoteRemoveDart remoteRemove;
  final RequestCompareWithWorkingCopyDart requestCompareWithWorkingCopy;
  final RequestFileHistoryDart requestFileHistory;
  final RequestLineHistoryDart requestLineHistory;
  final RequestReflogDart requestReflog;
  final UndoJournalJsonDart undoJournalJson;
  final UndoLastDart undoLast;
  final RestorePathsDart restorePaths;
  final CleanPreviewDart cleanPreview;
  final CleanUntrackedDart cleanUntracked;
  final RequestRebasePlanDart requestRebasePlan;
  final RebaseInteractiveStartDart rebaseInteractiveStart;
  final RebaseStartDart rebaseStart;
  final RebaseContinueDart rebaseContinue;
  final RebaseContinueWithMessageDart rebaseContinueWithMessage;
  final RebaseSkipDart rebaseSkip;
  final RebaseAbortDart rebaseAbort;
  final SubmoduleRefreshDart submoduleRefresh;
  final SubmodulesJsonDart submodulesJson;
  final SubmoduleAddDart submoduleAdd;
  final SubmoduleInitDart submoduleInit;
  final SubmoduleUpdateDart submoduleUpdate;
  final SubmoduleSyncDart submoduleSync;
  final SubmoduleDeinitDart submoduleDeinit;
  final BisectRefreshDart bisectRefresh;
  final BisectStatusJsonDart bisectStatusJson;
  final BisectStartDart bisectStart;
  final BisectMarkDart bisectMark;
  final BisectSkipDart bisectSkip;
  final BisectResetDart bisectReset;
  final LfsRefreshDart lfsRefresh;
  final LfsInstallationJsonDart lfsInstallationJson;
  final LfsPatternsJsonDart lfsPatternsJson;
  final LfsFilesJsonDart lfsFilesJson;
  final LfsInstallDart lfsInstall;
  final LfsTrackDart lfsTrack;
  final LfsUntrackDart lfsUntrack;
  final LfsPullDart lfsPull;
  final LfsFetchDart lfsFetch;
  final LfsPruneDart lfsPrune;
  final PatchExportDart patchExport;
  final PatchApplyFilesDart patchApplyFiles;
  final PatchImportDart patchImport;
  final PatchImportContinueDart patchImportContinue;
  final PatchImportSkipDart patchImportSkip;
  final PatchImportAbortDart patchImportAbort;
  final LocalIdentityRefreshDart localIdentityRefresh;
  final LocalIdentityJsonDart localIdentityJson;
  final EffectiveIdentityRefreshDart effectiveIdentityRefresh;
  final EffectiveIdentityJsonDart effectiveIdentityJson;
  final SetLocalIdentityDart setLocalIdentity;
  final ClearLocalIdentityDart clearLocalIdentity;
  final HasCommitGraphDart hasCommitGraph;
  final WriteCommitGraphDart writeCommitGraph;
  final RepoInitDart repoInit;
  final RepoCloneDart repoClone;
  final DiscoveryOpenDart discoveryOpen;
  final DiscoveryCloseDart discoveryClose;
  final DiscoveryAddBaseFolderDart discoveryAddBaseFolder;
  final DiscoveryScanAllDart discoveryScanAll;
  final DiscoveryListReposJsonDart discoveryListReposJson;
  final DiscoveryBaseFoldersJsonDart discoveryBaseFoldersJson;
  final DiscoveryRemoveBaseFolderDart discoveryRemoveBaseFolder;
  final DiscoverySetBaseFolderEnabledDart discoverySetBaseFolderEnabled;
  final DiscoverySetBaseFolderDepthDart discoverySetBaseFolderDepth;
}
