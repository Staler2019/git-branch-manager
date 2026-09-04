#pragma once

// A Qt-free sibling of RepositorySession (src/app/bridge/RepositorySession.h)
// built directly on gbm_core, publishing results through CallbackRegistry
// instead of Qt signals. One instance per open repository.
//
// Composition mirrors RepositorySession deliberately: same core objects
// (RefStore, HistoryProvider, OperationRunner), same "immutable snapshot
// published under a lock, read without one" discipline for the graph -- see
// docs/ARCHITECTURE.md's invariant 2. Only the M0/M1 subset (refs, history,
// graph, checkout) exists so far; later milestones add the remaining
// RepositorySession methods one domain at a time, matching src/capi/*.cpp.

#include "capi/AskpassPoller.h"
#include "capi/CallbackRegistry.h"
#include "capi/gbm_capi.h"
#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/Logging.h"
#include "core/git/BlameStore.h"
#include "core/git/CommitMetaStore.h"
#include "core/git/DiffService.h"
#include "core/git/FileHistoryStore.h"
#include "core/git/GitExecutable.h"
#include "core/git/HistoryProvider.h"
#include "core/git/IProcessRunner.h"
#include "core/git/OperationRunner.h"
#include "core/git/RefStore.h"
#include "core/git/ReflogStore.h"
#include "core/git/RepoPaths.h"
#include "core/git/RepoState.h"
#include "core/git/WorkingCopyStatus.h"
#include "core/git/ops/BisectOps.h"
#include "core/git/ops/BlobOps.h"
#include "core/git/ops/BranchOps.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/git/ops/CherryPickOps.h"
#include "core/git/ops/CommitOps.h"
#include "core/git/ops/CompareOps.h"
#include "core/git/ops/ConfigOps.h"
#include "core/git/ops/ConflictOps.h"
#include "core/git/ops/LfsOps.h"
#include "core/git/ops/MaintenanceOps.h"
#include "core/git/ops/MergeOps.h"
#include "core/git/ops/PatchOps.h"
#include "core/git/ops/RebaseOps.h"
#include "core/git/ops/RemoteOps.h"
#include "core/git/ops/ResetOps.h"
#include "core/git/ops/RevertOps.h"
#include "core/git/ops/StageOps.h"
#include "core/git/ops/StashOps.h"
#include "core/git/ops/SubmoduleOps.h"
#include "core/git/ops/TagOps.h"
#include "core/git/ops/UndoOps.h"
#include "core/git/ops/WorktreeOps.h"
#include "core/graph/GraphSnapshot.h"
#include "core/workers/DelayTimer.h"
#include "core/workers/RefreshCoalescer.h"
#include "core/workers/ThreadPool.h"

#include <functional>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace gbm::capi {

using StashListPtr = std::shared_ptr<const std::vector<StashEntry>>;
using WorktreeListPtr = std::shared_ptr<const std::vector<WorktreeInfo>>;
using RemoteListPtr = std::shared_ptr<const std::vector<RemoteInfo>>;
using SubmoduleListPtr = std::shared_ptr<const std::vector<SubmoduleInfo>>;
using BisectStatusPtr = std::shared_ptr<const BisectStatus>;
using LfsPatternListPtr = std::shared_ptr<const std::vector<std::string>>;
using LfsFileListPtr = std::shared_ptr<const std::vector<LfsFileInfo>>;
using LocalIdentityPtr = std::shared_ptr<const LocalIdentity>;
using EffectiveIdentityPtr = std::shared_ptr<const EffectiveIdentity>;

/// Resolves and caches the git installation once per process. Every Session
/// shares it: re-probing `git --version` per open repository would be pure
/// waste. Honors the GBM_GIT_PATH environment variable as an explicit
/// override. Only a successful detection is cached -- a failure is retried on
/// the next call, since the app has no way to prompt a restart after the user
/// fixes the underlying problem.
GitResult<GitInstallation> sharedGitInstallation();

/// Test-only: clears the cache populated by sharedGitInstallation() so a test
/// can force re-detection, e.g. after changing GBM_GIT_PATH.
void resetSharedGitInstallationForTest();

/// Shared read-worker pool, sized like RepositorySession's readPool_
/// (ThreadPool::defaultThreadCount()). One per process, not per session --
/// see ThreadPool's own class comment on why discovery gets a separate pool
/// (Discovery.cpp uses none yet; scans run synchronously in M0).
ThreadPool& sharedReadPool();

class Session {
public:
    static std::unique_ptr<Session> open(std::string workDir,
                                         std::string gitDir,
                                         std::string commonDir,
                                         GitError* outError);

    ~Session();

    Session(const Session&) = delete;
    Session& operator=(const Session&) = delete;

    void registerCallback(GbmEventCallback callback, void* userData);

    const RepoPaths& paths() const { return paths_; }

    RepoState repoState() const;

    /// Sync: see gbm_operation_remove_stale_index_lock()'s doc comment in
    /// gbm_capi.h. Delegates straight to OperationRunner::removeStaleIndexLock()
    /// -- the age re-check and kStaleLockSeconds threshold live there, next to
    /// preflight()'s own use of the same constant, not duplicated here.
    bool removeStaleIndexLock();

    /// Async: see gbm_history_refresh()'s doc comment in gbm_capi.h.
    void refreshHistory();

    /// Narrows every subsequent history walk, including the ones an operation
    /// or an auto-fetch resync triggers on their own -- the filter is session
    /// state, not a parameter of one walk, so it survives until changed. See
    /// gbm_history_set_filter().
    void setHistoryFilter(std::vector<std::string> includeRefs,
                          bool firstParentOnly,
                          bool noMerges);

    /// The most recently published graph snapshot, or null if
    /// refreshHistory() has not yet produced one. Thread-safe; never blocks.
    GraphSnapshotPtr currentGraph() const;

    /// The most recently published ref snapshot, or null if
    /// refreshHistory() has not yet produced one. Thread-safe; never blocks.
    RefSnapshotPtr currentRefs() const;

    /// Pins the current graph snapshot for zero-copy export (see
    /// gbm_graph_snapshot_rows() in gbm_capi.h) and returns it. Replaces
    /// whatever was previously pinned -- callers reading buffer pointers
    /// from the prior pin must have finished before calling this again.
    GraphSnapshotPtr exportGraph();

    /// Releases the pinned snapshot, if any. Safe to call when nothing is
    /// pinned.
    void releaseExportedGraph();

    /// Async: see gbm_branch_checkout()'s doc comment in gbm_capi.h.
    void checkout(CheckoutRequest request);

    /// Async: see gbm_branch_create()/_rename()/_delete()'s doc comments.
    void createBranch(CreateBranchRequest request);
    void renameBranch(RenameBranchRequest request);
    void deleteBranch(DeleteBranchRequest request);

    /// Async: see gbm_reset_to()'s doc comment in gbm_capi.h.
    void resetTo(ResetRequest request);

    /// Async: see gbm_working_copy_refresh()'s doc comment in gbm_capi.h.
    void refreshWorkingCopy();

    /// The most recently published working-copy status, or null if
    /// refreshWorkingCopy() has not yet produced one. Thread-safe; never
    /// blocks.
    WorkingCopyStatusPtr currentWorkingCopyStatus() const;

    /// Async: see gbm_working_copy_diff()'s doc comment in gbm_capi.h.
    void requestWorkingCopyDiff(std::string path, bool staged);

    /// Async: see gbm_stage_files()/gbm_unstage_files()'s doc comments.
    void stageFiles(std::vector<std::string> paths);
    void unstageFiles(std::vector<std::string> paths);

    /// Async: see gbm_stage_hunk()/gbm_unstage_hunk()/gbm_stage_lines()/
    /// gbm_unstage_lines()'s doc comments in gbm_capi.h.
    void stageHunk(std::string path, std::size_t hunkIndex);
    void unstageHunk(std::string path, std::size_t hunkIndex);
    void stageLines(std::string path, std::size_t hunkIndex, std::vector<std::size_t> lineIndices);
    void unstageLines(std::string path,
                      std::size_t hunkIndex,
                      std::vector<std::size_t> lineIndices);

    /// Async: see gbm_discard_lines()'s doc comment in gbm_capi.h. Unlike
    /// the four above, this one rewrites the work tree.
    void discardLines(std::string path,
                      std::size_t hunkIndex,
                      std::vector<std::size_t> lineIndices);

    /// Async: see gbm_commit_changes()'s doc comment in gbm_capi.h.
    void commitChanges(CommitRequest request);

    /// Async: see gbm_merge_branch()/gbm_merge_abort()'s doc comments.
    /// A conflicting merge is reported as outcome.succeeded == false with
    /// GitError::Code::Conflict (see MergeOps.h) -- the working copy is
    /// still refreshed so the conflicted paths show up.
    void mergeBranch(MergeRequest request);
    void abortMerge();

    /// Async: see gbm_cherry_pick()/_continue()/_skip()/_abort()'s doc
    /// comments.
    void cherryPick(CherryPickRequest request);
    void continueCherryPick();
    void skipCherryPick();
    void abortCherryPick();

    /// Async: see gbm_cherry_pick_continue_with_message()'s doc comment.
    void continueCherryPickWithMessage(std::string message);

    /// Async: see gbm_revert()'s doc comment.
    void revertCommit(RevertRequest request);

    /// Async: see gbm_resolve_conflict()'s doc comment.
    void resolveConflict(ResolveConflictRequest request);

    /// Async: see gbm_request_original_operation_message()'s doc comment.
    void requestOriginalOperationMessage();

    /// Async: see gbm_request_working_tree_content()'s doc comment.
    void requestWorkingTreeContent(std::string path);

    /// Async: see gbm_export_file_at_revision()'s doc comment.
    void exportFileAtRevision(std::string revision, std::string path, std::string destPath);

    /// Async: see gbm_stash_refresh()'s doc comment.
    void refreshStashes();

    /// The most recently published stash list, or null if refreshStashes()
    /// has not yet produced one. Thread-safe; never blocks.
    StashListPtr currentStashes() const;

    /// Async: see gbm_stash_save()/_apply()/_drop()/_branch()'s doc comments.
    void saveStash(StashSaveRequest request);
    void applyStash(StashApplyRequest request);
    void dropStash(StashDropRequest request);
    void branchFromStash(StashBranchRequest request);

    /// Async: see gbm_stash_request_diff()'s doc comment.
    void requestStashDiff(int index);

    /// Async: see gbm_tag_create()/_delete()/_push()'s doc comments.
    void createTag(CreateTagRequest request);
    void deleteTag(DeleteTagRequest request);
    void pushTag(PushTagRequest request);

    /// Async: see gbm_worktree_refresh()'s doc comment.
    void refreshWorktrees();

    /// Async: re-lists the worktrees *and* measures each one's uncommitted
    /// change count, then republishes. See gbm_worktree_request_pending_counts().
    ///
    /// **`request*`, not `refresh*`, and that is a structural claim rather
    /// than a naming preference.** Every zero-argument `refresh*` on this
    /// class is a member of the focus-regain/F5 refresh set; this one must
    /// not be, because it costs one `git status` process per worktree and is
    /// wanted only while the worktrees panel is open -- a user selection that
    /// need not still exist when the window comes back. The `request*` family
    /// is excluded from that set by construction, so a later reader does not
    /// have to notice a comment saying so.
    ///
    /// A `refreshWorktrees(bool withStatus)` overload was considered and
    /// rejected for the same reason: the zero-argument form would still
    /// exist, and nothing at the call site would say which one it reached.
    void requestWorktreePendingCounts();

    /// The most recently published worktree list, or null if
    /// refreshWorktrees() has not yet produced one. Thread-safe; never
    /// blocks.
    WorktreeListPtr currentWorktrees() const;

    /// Async: see gbm_worktree_add()/_remove()/_prune()/_lock()/_unlock()'s
    /// doc comments.
    void addWorktree(AddWorktreeRequest request);
    void removeWorktree(RemoveWorktreeRequest request);
    void pruneWorktrees();
    void lockWorktree(LockWorktreeRequest request);
    void unlockWorktree(UnlockWorktreeRequest request);

    /// Async: see gbm_remote_refresh()'s doc comment.
    void refreshRemotes();

    /// The most recently published remote list, or null if
    /// refreshRemotes() has not yet produced one. Thread-safe; never blocks.
    RemoteListPtr currentRemotes() const;

    /// Async: see gbm_remote_fetch()/gbm_pull()/gbm_push()'s doc comments.
    /// Each wires a fresh askpass request directory into its request before
    /// submitting, per beginAskpass()'s doc comment.
    void fetchRemote(FetchRequest request);
    void pullChanges(PullRequest request);
    void pushChanges(PushRequest request);

    /// Async: see gbm_request_remote_prune_preview()'s doc comment.
    void requestRemotePrunePreview(std::string remoteName);

    /// Async: see gbm_remote_prune()'s doc comment.
    void pruneRemote(PruneRemoteRequest request);

    /// Async: see gbm_remote_add()/gbm_remote_remove()'s doc comments.
    void addRemote(AddRemoteRequest request);
    void removeRemote(RemoveRemoteRequest request);

    /// Async: see gbm_provide_credential()/gbm_cancel_credential()'s doc
    /// comments. A no-op if no prompt is currently outstanding.
    void provideCredential(std::string secret);
    void cancelCredential();

    /// Async: see gbm_request_blame()'s doc comment.
    void requestBlame(std::string path, std::string revision, int startLine, int endLine);

    /// Async: see gbm_request_commit_meta()'s doc comment.
    void requestCommitMeta(std::vector<std::string> oids);

    /// Async: see gbm_request_commit_files()'s doc comment.
    void requestCommitFileCounts(std::vector<std::string> oids);

    void requestCommitFiles(std::string oid);

    /// Async: see gbm_request_commit_file_diff()'s doc comment.
    void requestCommitFileDiff(std::string oid, std::string path);

    /// Async: see gbm_request_compare_refs()'s doc comment. left/right/
    /// threeDot are echoed back in the event payload so a caller with
    /// several Compare tabs open at once (each its own ref pair) can match
    /// the reply to the tab that asked for it.
    void requestCompareRefs(std::string leftRef, std::string rightRef, bool threeDot);

    /// Async: see gbm_request_compare_file_diff()'s doc comment.
    void requestCompareFileDiff(std::string leftRef,
                                std::string rightRef,
                                bool threeDot,
                                std::string path);

    /// Async: see gbm_request_compare_with_working_copy()'s doc comment.
    void requestCompareWithWorkingCopy(std::string ref);

    /// Async: see gbm_request_file_history()/gbm_request_line_history()'s
    /// doc comments.
    void requestFileHistory(std::string path, std::string startRevision);
    void requestLineHistory(std::string path,
                            int startLine,
                            int endLine,
                            std::string startRevision);

    /// Async: see gbm_request_reflog()'s doc comment.
    void requestReflog(std::string ref);

    /// The most recently published undo journal, newest last. Thread-safe;
    /// never blocks. See undoJournalCache_'s doc comment for why this is a
    /// snapshot rather than a live read of operations_->undoJournal().
    std::vector<OperationRunner::UndoEntry> undoJournal() const;

    /// Async: see gbm_undo_last()'s doc comment.
    void undoLastOperation();

    /// Async: see gbm_restore_paths()'s doc comment.
    void restorePaths(RestoreRequest request);

    /// Async: see gbm_clean_preview()'s doc comment.
    void requestCleanPreview(bool includeIgnored);

    /// Async: see gbm_clean_untracked()'s doc comment.
    void cleanUntracked(CleanRequest request);

    /// Async: see gbm_request_rebase_plan()'s doc comment.
    void requestRebasePlan(std::string upstream);

    /// Async: see gbm_rebase_interactive_start()/_start()/_continue()/
    /// _skip()/_abort()'s doc comments. Like merge/cherry-pick, a
    /// conflicting or `edit`-stopped rebase is reported as
    /// outcome.succeeded == false -- the working copy is still refreshed so
    /// the stopped-at state shows up.
    void startInteractiveRebase(RebaseInteractiveRequest request);
    void startRebase(RebaseRequest request);
    void continueRebase();
    void skipRebase();
    void abortRebase();

    /// Async: see gbm_rebase_continue_with_message()'s doc comment.
    void continueRebaseWithMessage(std::string message);

    /// Async: see gbm_submodule_refresh()'s doc comment.
    void refreshSubmodules();

    /// The most recently published submodule list, or null if
    /// refreshSubmodules() has not yet produced one. Thread-safe; never
    /// blocks.
    SubmoduleListPtr currentSubmodules() const;

    /// Async: see gbm_submodule_add()/_init()/_update()/_sync()/_deinit()'s
    /// doc comments. add()/update() wire a fresh askpass request directory
    /// into their request before submitting, per beginAskpass()'s doc
    /// comment -- both can clone/fetch over the network.
    void addSubmodule(AddSubmoduleRequest request);
    void initSubmodules(SubmodulePathsRequest request);
    void updateSubmodules(UpdateSubmodulesRequest request);
    void syncSubmodules(SubmodulePathsRequest request);
    void deinitSubmodules(DeinitSubmodulesRequest request);

    /// Async: see gbm_bisect_refresh()'s doc comment.
    void refreshBisectStatus();

    /// The most recently published BisectStatus, or null if
    /// refreshBisectStatus() has not yet produced one. Thread-safe; never
    /// blocks.
    BisectStatusPtr currentBisectStatus() const;

    /// Async: see gbm_bisect_start()/_mark()/_skip()/_reset()'s doc
    /// comments.
    void startBisect(BisectStartRequest request);
    void markBisect(BisectMarkRequest request);
    void skipBisect(BisectSkipRequest request);
    void resetBisect(BisectResetRequest request);

    /// Async: see gbm_lfs_refresh()'s doc comment. Detects `git-lfs` only on
    /// the first call (see lfsInstallation_'s doc comment); every call
    /// re-reads tracked patterns and file status.
    void refreshLfs();

    /// The most recently detected LFS installation, or nullopt if
    /// refreshLfs() has not yet run. Thread-safe; never blocks.
    std::optional<LfsInstallation> currentLfsInstallation() const;

    /// The most recently published tracked-pattern/file lists, or null if
    /// refreshLfs() has not yet produced one. Thread-safe; never blocks.
    LfsPatternListPtr currentLfsPatterns() const;
    LfsFileListPtr currentLfsFiles() const;

    /// Async: see gbm_lfs_install()/_track()/_untrack()/_pull()/_fetch()/
    /// _prune()'s doc comments. pull()/fetch() wire a fresh askpass request
    /// directory into their request before submitting, like
    /// addSubmodule()/updateSubmodules().
    void installLfs();
    void trackLfsPattern(LfsTrackRequest request);
    void untrackLfsPattern(LfsUntrackRequest request);
    void pullLfs(LfsTransferRequest request);
    void fetchLfs(LfsTransferRequest request);
    void pruneLfs(LfsPruneRequest request);

    /// Async: see gbm_patch_export()/_apply_files()/_import()/_continue()/
    /// _skip()/_abort()'s doc comments.
    void exportPatches(ExportPatchesRequest request);
    void applyPatchFiles(ApplyPatchFilesRequest request);
    void importPatches(ImportPatchesRequest request);
    void continueImport();
    void skipImport();
    void abortImport();

    /// Async: see gbm_local_identity_refresh()'s doc comment.
    void refreshLocalIdentity();

    /// The most recently published LocalIdentity, or null if
    /// refreshLocalIdentity() has not yet produced one. Thread-safe; never
    /// blocks.
    LocalIdentityPtr currentLocalIdentity() const;

    /// Async: see gbm_effective_identity_refresh()'s doc comment.
    void refreshEffectiveIdentity();

    /// The most recently published EffectiveIdentity, or null if
    /// refreshEffectiveIdentity() has not yet produced one. Thread-safe;
    /// never blocks.
    EffectiveIdentityPtr currentEffectiveIdentity() const;

    /// Async: see gbm_set_local_identity()/gbm_clear_local_identity()'s doc
    /// comments.
    void setLocalIdentityOverride(SetLocalIdentityRequest request);
    void clearLocalIdentityOverride();

    /// Sync: see gbm_has_commit_graph()'s doc comment.
    bool hasCommitGraph() const;

    /// Async: see gbm_write_commit_graph()'s doc comment.
    void writeCommitGraph();

    /// The process-wide gbm::Log operation sink, installed once (via
    /// std::call_once in the constructor) and shared by every open Session:
    /// gbm::Log is itself a process-wide singleton, with no notion of which
    /// session a given git invocation belongs to. Looks `record.repoDir` up
    /// against the .cpp file's anonymous-namespace registry of live Session
    /// instances (keyed by work tree) and forwards to the matching one's
    /// publishOperationLogRecord(). Public only so gbm::Log::setOperationSink
    /// (called from an anonymous-namespace free function, not a Session
    /// member) can take its address -- not part of the gbm_capi.h surface,
    /// so no Dart caller can reach it.
    static void dispatchOperationLogRecord(const OperationRecord& record);

private:
    Session(GitInstallation installation, RepoPaths paths, std::unique_ptr<IProcessRunner> runner);

    /// Publishes a chunk of the walk that `generation` dispatched, dropping
    /// it if a newer dispatch has already superseded that one. See
    /// dispatchRefresh().
    void publishGraph(GraphSnapshotPtr snapshot, RefreshCoalescer::Generation generation);

    /// Posts the actual refs + history read for the dispatch identified by
    /// `generation` onto sharedReadPool(), and guarantees exactly one
    /// finishRefresh(generation) on every terminal path the read can take.
    void dispatchRefresh(RefreshCoalescer::Generation generation, CancellationToken token);

    /// Reports the dispatch identified by `generation` as complete, and
    /// re-drives the timer immediately when a request folded in while it was
    /// running (RefreshCoalescer::onFinished()'s contract).
    void finishRefresh(RefreshCoalescer::Generation generation);

    /// Called on the refresh timer's own thread once the coalescing window
    /// has settled: takes the merged batch and dispatches it.
    void onRefreshTimerFired();

    /// Whether `generation` may still publish into refs_/graph_. Caller must
    /// hold graphMutex_. Monotonic, not merely an equality check against the
    /// current generation: that alone leaves a window between the check and
    /// the store in which a newer dispatch can land, and a stale snapshot
    /// overwriting a newer one is worse than the log noise this whole
    /// mechanism exists to remove.
    bool claimPublishLocked(RefreshCoalescer::Generation generation);

    /// Runs `operation` on operations_, emits
    /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED with its outcome, calls
    /// `onAlways` unconditionally (e.g. to end an askpass watch or refresh
    /// the working copy even on a conflicting result), then calls
    /// `onSuccess` if the operation succeeded (e.g. to chain a further
    /// refresh) -- the shared tail of stageFiles/unstageFiles/
    /// commitChanges/stash/tag/worktree/remote mutations, mirroring
    /// RepositorySession::submitWorkingCopyOperation /
    /// RepositorySession::submitAndRefresh (the same helper in the Qt app,
    /// despite the different names -- every M3+ domain mutation there goes
    /// through it, not just the working-copy-specific ones).
    void submitWorkingCopyOperation(std::unique_ptr<Operation> operation,
                                    std::function<void()> onSuccess,
                                    std::function<void()> onAlways = nullptr);

    /// Creates a fresh askpass request directory and starts polling it,
    /// forwarding each prompt as GBM_EVENT_CREDENTIAL_REQUESTED. Returns the
    /// directory (possibly empty, if it could not be created -- see
    /// askpass::makeRequestDir()'s doc comment) for the caller to assign to
    /// its request's askpassDir field before submitting. Pair with
    /// endAskpass() in the operation's completion hook, unconditionally.
    std::filesystem::path beginAskpass();

    /// Stops the askpass poller and removes its request directory. A no-op
    /// if beginAskpass() was not called for the operation that just
    /// finished (askpassDir was empty, e.g. gbm_tag_delete() without
    /// alsoRemote) -- safe to call unconditionally from every completion
    /// hook.
    void endAskpass();

    /// Serializes `record` and emits it as GBM_EVENT_OPERATION_LOG_RECORD.
    void publishOperationLogRecord(const OperationRecord& record);

    /// Copies operations_->undoJournal() into undoJournalCache_ under
    /// undoMutex_. Called only from within submitOperation()'s/
    /// submitWorkingCopyOperation()'s completion callback -- i.e. only ever
    /// on operations_'s own serial worker thread, which is also the only
    /// thread that ever calls OperationRunner::recordUndoPoint() (the thing
    /// that mutates the journal operations_->undoJournal() references). That
    /// makes this call site-safe even though OperationRunner::undoJournal()
    /// itself returns an unsynchronized `const vector&` (see its doc
    /// comment): nothing else can be appending to the vector while this
    /// runs, because this callback running IS the worker thread being busy.
    /// undoJournal() (the public accessor below) is the only thing that may
    /// be called from an arbitrary thread (an FFI caller), which is exactly
    /// why it reads the mutex-guarded copy instead of going through
    /// operations_ directly.
    void refreshUndoJournalCache();

    /// Runs `operation` on operations_, emits GBM_EVENT_OPERATION_FINISHED
    /// with its outcome, and always refreshes the working copy (a
    /// checkout/reset/merge/cherry-pick/revert/rebase/bisect can leave
    /// conflicted or simply changed paths whether or not it "succeeded" in
    /// the OperationOutcome sense -- see mergeBranch()'s doc comment above).
    /// Refreshes history too, but only when `refreshHistoryOnSuccess` and
    /// the operation actually succeeded, since a conflicting/aborted
    /// operation has not moved any ref. `onAlways`, if given, runs
    /// unconditionally right after the event is emitted -- the hook
    /// beginAskpass() requires, since a credential watch has to be stopped
    /// whether the operation succeeded or not. `onSuccess`, if given, runs
    /// last and only on success -- e.g. bisect operations use it to also
    /// refresh their own status snapshot, which nothing else here knows to
    /// do. Same two-callback shape as submitWorkingCopyOperation() above.
    void submitOperation(std::unique_ptr<Operation> operation,
                         bool refreshHistoryOnSuccess,
                         std::function<void()> onSuccess = nullptr,
                         std::function<void()> onAlways = nullptr);

    GitInstallation installation_;
    RepoPaths paths_;
    std::unique_ptr<IProcessRunner> runner_;
    std::unique_ptr<RefStore> refStore_;
    std::unique_ptr<HistoryProvider> history_;
    std::unique_ptr<OperationRunner> operations_;
    std::unique_ptr<WorkingCopyStatusReader> workingCopyStatusReader_;
    std::unique_ptr<DiffService> diffs_;
    std::unique_ptr<StashStore> stashStore_;
    std::unique_ptr<WorktreeStore> worktreeStore_;
    std::unique_ptr<RemoteStore> remoteStore_;
    std::unique_ptr<CompareStore> compareStore_;
    std::unique_ptr<BlobStore> blobStore_;
    std::unique_ptr<BlameStore> blameStore_;
    std::unique_ptr<CommitMetaStore> commitMetaStore_;
    std::unique_ptr<FileHistoryStore> fileHistoryStore_;
    std::unique_ptr<ReflogStore> reflogStore_;
    std::unique_ptr<SubmoduleStore> submoduleStore_;
    std::unique_ptr<BisectStore> bisectStore_;
    std::unique_ptr<LfsStore> lfsStore_;
    std::unique_ptr<LocalIdentityStore> localIdentityStore_;

    CallbackRegistry callbacks_;
    AskpassPoller askpass_;

    mutable std::mutex graphMutex_;
    GraphSnapshotPtr graph_;
    RefSnapshotPtr refs_;
    /// The branch filter, guarded by graphMutex_ because refreshHistory()
    /// reads it from a pool thread. Empty includeRefs means an unfiltered
    /// walk, which is the default.
    std::vector<std::string> historyIncludeRefs_;
    bool historyFirstParentOnly_ = false;
    bool historyNoMerges_ = false;
    /// Only ever written from the thread that calls exportGraph()/
    /// releaseExportedGraph() -- Dart's FFI calls are made from a single
    /// isolate at a time by convention, so this needs no lock of its own.
    GraphSnapshotPtr exportedGraph_;

    /// Separate from graphMutex_: working-copy status changes far more
    /// often (every stage/unstage/commit) and independently of history
    /// refreshes, so sharing one lock would serialise unrelated readers for
    /// no reason.
    mutable std::mutex workingCopyMutex_;
    WorkingCopyStatusPtr workingCopyStatus_;

    /// Guards refreshCoalescer_ and historyCancel_ below. refreshHistory() is
    /// reached from at least two threads in the shipping app --
    /// gbm_history_refresh() on Dart's FFI thread, and the refreshHistory()
    /// call inside submitOperation()/submitWorkingCopyOperation()'s
    /// completion callback, which runs on OperationRunner's worker thread --
    /// plus refreshTimer_'s own thread, and RefreshCoalescer is deliberately
    /// not thread-safe (it was written for a Qt UI thread).
    ///
    /// historyCancel_'s cancel-then-replace is a plain shared_ptr assignment;
    /// unguarded, two concurrent calls tear the callback list in
    /// CancellationState apart and one of them invokes a freed
    /// std::function: ThreadSanitizer reports the race and then a SEGV in
    /// CancellationSource::cancel(). See
    /// HistoryRefreshApiTest.ConcurrentRefreshesDoNotRaceOnTheCancellationSource.
    ///
    /// Held across cancel() itself, not just across the assignment. That is
    /// safe because the only callback ever registered on this source is
    /// ProcessRunner::execute()'s `child->terminate()` (ProcessRunner.cpp),
    /// which sends a signal and returns -- it takes no lock of ours and
    /// cannot re-enter Session.
    mutable std::mutex refreshMutex_;

    /// Collapses a burst of refreshHistory() calls into one walk. See
    /// refreshHistory() for why this replaced "cancel whatever is running,
    /// then start mine".
    RefreshCoalescer refreshCoalescer_;

    /// Cancels the in-flight history walk. Only two callers cancel it now:
    /// setHistoryFilter(), which genuinely supersedes a walk whose filter is
    /// already wrong, and ~Session(). Routine refreshes fold instead, which
    /// is what stops them terminating each other's git processes.
    CancellationSource historyCancel_;

    /// Which dispatch last wrote refs_/graph_, so a superseded walk cannot
    /// publish over a newer one's snapshot. Guarded by graphMutex_ (not
    /// refreshMutex_) because it is read and written in the same critical
    /// section as the snapshots it orders.
    RefreshCoalescer::Generation publishedGeneration_ = 0;

    /// Drives refreshCoalescer_'s delay window. Declared last of the refresh
    /// members on purpose: its constructor starts a thread that can call back
    /// into this Session, so everything that call touches must already be
    /// built. The thread parks until the first arm(), and ~Session() stops it
    /// explicitly rather than waiting for member destruction -- see the
    /// ordering comment there.
    DelayTimer refreshTimer_;

    /// Stash/worktree/remote/submodule/bisect/LFS state all change far less
    /// often than the graph or working-copy status, and independently of
    /// each other, but not so independently-and-often that they need
    /// graphMutex_/workingCopyMutex_'s split -- one shared lock across all
    /// of them is simpler and does not meaningfully serialize anything that
    /// matters.
    mutable std::mutex auxMutex_;
    StashListPtr stashes_;
    WorktreeListPtr worktrees_;
    RemoteListPtr remotes_;
    SubmoduleListPtr submodules_;
    BisectStatusPtr bisectStatus_;
    /// Detected once per session, on the first refreshLfs() call -- see
    /// refreshLfs()'s doc comment. Distinct from the other auxMutex_ fields
    /// above by staying set once populated (a session's `git-lfs`
    /// availability cannot change mid-session), rather than being replaced
    /// on every refresh.
    std::optional<LfsInstallation> lfsInstallation_;
    LfsPatternListPtr lfsPatterns_;
    LfsFileListPtr lfsFiles_;
    LocalIdentityPtr localIdentity_;
    EffectiveIdentityPtr effectiveIdentity_;

    /// A snapshot of operations_->undoJournal(), refreshed by
    /// refreshUndoJournalCache() (see its doc comment for why this
    /// indirection exists rather than exposing operations_->undoJournal()
    /// directly: that accessor is not internally synchronized, so a caller
    /// on an arbitrary FFI thread reading it concurrently with the worker
    /// thread's OperationRunner::recordUndoPoint() would be a data race).
    /// This cache is the capi layer's own translation of a Qt-app assumption
    /// (a single UI thread reading a cheap accessor "often") into something
    /// safe to call from any thread.
    mutable std::mutex undoMutex_;
    std::vector<OperationRunner::UndoEntry> undoJournalCache_;
};

}  // namespace gbm::capi
