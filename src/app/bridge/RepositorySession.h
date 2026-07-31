#pragma once

#include "app/bridge/AskpassWatcher.h"
#include "app/bridge/SnapshotHolder.h"
#include "core/base/CancellationToken.h"
#include "core/git/BlameStore.h"
#include "core/git/CatFileBatch.h"
#include "core/git/DiffService.h"
#include "core/git/FileHistoryStore.h"
#include "core/git/GitExecutable.h"
#include "core/git/HistoryProvider.h"
#include "core/git/OperationRunner.h"
#include "core/git/RefStore.h"
#include "core/git/ReflogStore.h"
#include "core/git/RepoState.h"
#include "core/git/WorkingCopyStatus.h"
#include "core/git/ops/BisectOps.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/git/ops/CherryPickOps.h"
#include "core/git/ops/CommitOps.h"
#include "core/git/ops/ConflictOps.h"
#include "core/git/ops/LfsOps.h"
#include "core/git/ops/MergeOps.h"
#include "core/git/ops/PatchOps.h"
#include "core/git/ops/RebaseOps.h"
#include "core/git/ops/RemoteOps.h"
#include "core/git/ops/ResetOps.h"
#include "core/git/ops/StageOps.h"
#include "core/git/ops/StashOps.h"
#include "core/git/ops/SubmoduleOps.h"
#include "core/git/ops/TagOps.h"
#include "core/git/ops/UndoOps.h"
#include "core/git/ops/WorktreeOps.h"
#include "core/graph/GraphSnapshot.h"
#include "core/workers/ThreadPool.h"

#include <QObject>
#include <QString>

#include <functional>
#include <memory>
#include <optional>
#include <vector>

namespace gbm {

using StashListPtr = std::shared_ptr<const std::vector<StashEntry>>;
using WorktreeListPtr = std::shared_ptr<const std::vector<WorktreeInfo>>;
using RemoteListPtr = std::shared_ptr<const std::vector<RemoteInfo>>;
using SubmoduleListPtr = std::shared_ptr<const std::vector<SubmoduleInfo>>;
using BisectStatusPtr = std::shared_ptr<const BisectStatus>;
using LfsFileListPtr = std::shared_ptr<const std::vector<LfsFileInfo>>;
using LfsPatternListPtr = std::shared_ptr<const std::vector<std::string>>;

/// One open repository, and the single place where core callbacks become Qt
/// signals.
///
/// Everything expensive happens on the read pool or the operation runner's serial
/// thread; results arrive here and are re-emitted with `Qt::QueuedConnection`, so
/// the UI is only ever touched on the UI thread. Keeping that translation in one
/// class is what stops thread-affinity bugs from spreading through the views.
class RepositorySession : public QObject {
    Q_OBJECT

public:
    RepositorySession(GitInstallation installation,
                      RepoPaths paths,
                      ThreadPool& readPool,
                      QObject* parent = nullptr);
    ~RepositorySession() override;

    const RepoPaths& paths() const { return paths_; }

    QString displayName() const;

    /// The most recent graph. May be a partial snapshot while a walk is running.
    GraphSnapshotPtr graph() const { return graph_.current(); }

    RefSnapshotPtr refs() const { return refs_.current(); }

    RepoState state() const;

    /// Starts (or restarts) the history walk. Any walk already running is
    /// cancelled rather than waited for, which is what makes changing a filter or
    /// switching repositories feel immediate.
    void refreshHistory(HistoryQuery query = {});

    void refreshRefs();

    /// Queues metadata for rows the user can actually see. Called by the model on
    /// a cache miss; never blocks the caller.
    void requestCommitMetadata(std::vector<ObjectId> oids);

    /// Requests the changed-file list and diff for a commit.
    void requestCommitDetails(const ObjectId& commit);

    /// Switches branches. `onFinished` runs on the UI thread.
    void checkout(const CheckoutRequest& request);

    void cancelPendingReads();

    /// The most recent working-copy status. May be stale until the next
    /// `workingCopyStatusUpdated`; never blocks.
    WorkingCopyStatusPtr workingCopyStatus() const { return workingCopyStatus_.current(); }

    /// Re-reads `git status`. Deliberately uncached at the RepositorySession
    /// level too, matching WorkingCopyStatusReader: the work tree changes on
    /// every keystroke, so a snapshot is only ever "as of the last refresh".
    void refreshWorkingCopyStatus();

    /// Diff of one path against the index (staged=false) or HEAD
    /// (staged=true), for the working-copy panel.
    void requestWorkingCopyDiff(const std::string& path, bool staged);

    void stageFiles(std::vector<std::string> paths);
    void unstageFiles(std::vector<std::string> paths);

    /// Applies a hunk- or line-level patch to the index; see
    /// UnifiedDiffParser::buildHunkPatch / buildLineSelectionPatch for how the
    /// patch and `reverse` are meant to be paired.
    void applyPatch(std::string patch, bool reverse);

    void commitChanges(const CommitRequest& request);

    /// `git merge`, in whichever mode the request asks for. A conflict is
    /// reported through `workingCopyOperationFinished` exactly like any other
    /// failure -- see MergeOps.h -- and the conflicted paths then show up in
    /// the next `workingCopyStatusUpdated`.
    void mergeBranch(const MergeRequest& request);
    void abortMerge();

    /// `git cherry-pick`, for a single commit, several, or a caller-expanded
    /// range (see RefStore::resolveRange). Applies in the order the request's
    /// commits are listed.
    void cherryPick(const CherryPickRequest& request);
    void continueCherryPick();
    void skipCherryPick();
    void abortCherryPick();

    /// Resolves one conflicted path from a stopped merge/cherry-pick/revert.
    void resolveConflict(const ResolveConflictRequest& request);

    /// Reads the three stages' blob content for a conflicted path, so a
    /// resolution view can show ancestor/ours/theirs without running `git
    /// checkout --ours/--theirs` just to look. Empty strings for a stage that
    /// does not exist -- see WorkingCopyEntry::ancestorBlob et al.
    void requestConflictSides(const std::string& path,
                              const std::string& ancestorBlob,
                              const std::string& oursBlob,
                              const std::string& theirsBlob);

    // --- M3: stashes -----------------------------------------------------

    StashListPtr stashes() const { return stashes_.current(); }

    void refreshStashes();

    void saveStash(const StashSaveRequest& request);
    void applyStash(const StashApplyRequest& request);
    void dropStash(const StashDropRequest& request);
    void branchFromStash(const StashBranchRequest& request);

    // --- M3: tags ----------------------------------------------------------
    // Tags themselves are read through refs() / RefKind::Tag; only the
    // mutating side is new here.

    void createTag(const CreateTagRequest& request);
    void deleteTag(const DeleteTagRequest& request);
    void pushTag(const PushTagRequest& request);

    // --- M3: worktrees -------------------------------------------------------

    WorktreeListPtr worktrees() const { return worktrees_.current(); }

    void refreshWorktrees();

    void addWorktree(const AddWorktreeRequest& request);
    void removeWorktree(const RemoveWorktreeRequest& request);
    void pruneWorktrees();
    void lockWorktree(const LockWorktreeRequest& request);
    void unlockWorktree(const UnlockWorktreeRequest& request);

    // --- M3: remotes -----------------------------------------------------

    RemoteListPtr remotes() const { return remotes_.current(); }

    void refreshRemotes();

    /// Fetch/pull/push all route credential prompts through the same
    /// AskpassWatcher -- see credentialRequested/provideCredential/
    /// cancelCredential -- rather than failing outright the moment auth is
    /// needed, which is what would happen without it (GIT_TERMINAL_PROMPT is
    /// always 0; see ProcessRunner).
    void fetchRemote(FetchRequest request);
    void pullChanges(PullRequest request);
    void pushChanges(PushRequest request);

    /// Answers or dismisses the credential prompt currently outstanding, if
    /// any. A no-op if none is.
    void provideCredential(const QString& secret);
    void cancelCredential();

    // --- M4: reset / restore / clean --------------------------------------

    /// `git reset`. Hard also refreshes the working-copy status, since it
    /// rewrites the work tree.
    void resetTo(const ResetRequest& request);
    void restorePaths(const RestoreRequest& request);
    void requestCleanPreview(bool includeIgnored);
    void cleanUntracked(const CleanRequest& request);

    // --- M4: rebase ------------------------------------------------------

    void requestRebasePlan(const std::string& upstream);
    void startInteractiveRebase(const RebaseInteractiveRequest& request);
    void startRebase(const RebaseRequest& request);
    void continueRebase();
    void skipRebase();
    void abortRebase();

    // --- M4: blame ---------------------------------------------------------

    void requestBlame(const std::string& path,
                      const std::string& revision,
                      int startLine,
                      int endLine);

    // --- M4: file and line history -------------------------------------------

    void requestFileHistory(const std::string& path, const std::string& startRevision);
    void requestLineHistory(const std::string& path,
                            int startLine,
                            int endLine,
                            const std::string& startRevision);

    // --- M4: reflog and undo -----------------------------------------------

    void requestReflog(const std::string& ref);

    /// What OperationRunner recorded HEAD as being before each mutating
    /// operation. Cheap; safe to call often (e.g. to decide whether an "Undo"
    /// menu item is enabled).
    const std::vector<OperationRunner::UndoEntry>& undoJournal() const {
        return operations_->undoJournal();
    }

    /// Reverses the most recent journal entry -- see UndoOps.h.
    void undoLastOperation();

    // --- M5: submodules ------------------------------------------------------

    SubmoduleListPtr submodules() const { return submodules_.current(); }

    void refreshSubmodules();

    void addSubmodule(const AddSubmoduleRequest& request);
    void initSubmodules(const SubmodulePathsRequest& request);
    void updateSubmodules(const UpdateSubmodulesRequest& request);
    void syncSubmodules(const SubmodulePathsRequest& request);
    void deinitSubmodules(const DeinitSubmodulesRequest& request);

    // --- M5: bisect ------------------------------------------------------

    BisectStatusPtr bisectStatus() const { return bisectStatus_.current(); }

    void refreshBisectStatus();

    void startBisect(const BisectStartRequest& request);
    void markBisect(const BisectMarkRequest& request);
    void skipBisect(const BisectSkipRequest& request);
    void resetBisect(const BisectResetRequest& request);

    // --- M5: LFS -----------------------------------------------------------

    /// Whether `git-lfs` is on `PATH`, detected once per session on the first
    /// `refreshLfs()` call. `std::nullopt` before that first refresh completes.
    std::optional<LfsInstallation> lfsInstallation() const { return lfsInstallation_; }

    LfsPatternListPtr lfsTrackedPatterns() const { return lfsPatterns_.current(); }

    LfsFileListPtr lfsFiles() const { return lfsFiles_.current(); }

    void refreshLfs();

    void installLfs();
    void trackLfsPattern(const LfsTrackRequest& request);
    void untrackLfsPattern(const LfsUntrackRequest& request);
    void pullLfs(const LfsTransferRequest& request);
    void fetchLfs(const LfsTransferRequest& request);
    void pruneLfs(const LfsPruneRequest& request);

    // --- M5: patch import/export --------------------------------------------

    void exportPatches(const ExportPatchesRequest& request);
    void applyPatchFiles(const ApplyPatchFilesRequest& request);
    void importPatches(const ImportPatchesRequest& request);
    void continueImport();
    void skipImport();
    void abortImport();

signals:
    /// A newer graph snapshot is available (possibly partial).
    void graphUpdated(bool complete);
    void refsUpdated();
    void commitMetadataReady(const std::vector<CommitMeta>& metadata);
    void commitDetailsReady(const ObjectId& commit,
                            std::shared_ptr<const std::vector<ChangedFile>> files,
                            std::shared_ptr<const ParsedDiff> diff);
    void operationFinished(const OperationOutcome& outcome);
    void errorOccurred(const GitError& error);
    void busyChanged(bool busy);

    void workingCopyStatusUpdated();
    void workingCopyDiffReady(QString path, bool staged, std::shared_ptr<const ParsedDiff> diff);
    /// Reply to requestConflictSides, matched back up by path. A stage's
    /// content is empty both when that stage does not exist and when reading
    /// it failed -- the request is best-effort display, not itself an
    /// operation worth failing loudly over.
    void conflictSidesReady(QString path, QString ancestor, QString ours, QString theirs);
    /// Separate from `operationFinished`: MainWindow's checkout-recovery UI
    /// (stash/discard choices) does not apply to staging and commit, so the
    /// working-copy panel gets its own completion signal to react to.
    void workingCopyOperationFinished(OperationOutcome outcome);

    void stashesUpdated();
    void worktreesUpdated();
    void remotesUpdated();
    void submodulesUpdated();
    void bisectStatusUpdated();
    void lfsUpdated();

    /// A `git` subprocess spawned by one of the M3 remote/tag operations is
    /// blocked waiting for `prompt`. The view layer is expected to show it and
    /// call provideCredential()/cancelCredential() in response.
    void credentialRequested(QString prompt);

    // --- M4 ----------------------------------------------------------------

    void cleanPreviewReady(std::vector<CleanEntry> entries);
    void rebasePlanReady(std::vector<RebaseTodoEntry> entries);
    void blameReady(BlameResultPtr result);
    void fileHistoryReady(std::vector<FileHistoryEntry> entries);
    void lineHistoryReady(std::vector<LineHistoryChunk> chunks);
    void reflogReady(std::vector<ReflogEntry> entries);

private:
    void setBusy(bool busy);
    /// Runs a staging/commit Operation and, on success, refreshes whatever it
    /// could have changed. Shared by stageFiles/unstageFiles/applyPatch/commitChanges
    /// so each stays a one-line call.
    void submitWorkingCopyOperation(std::unique_ptr<Operation> operation, bool alsoRefreshHistory);

    /// The general form submitWorkingCopyOperation is built on: runs any
    /// Operation, always emits workingCopyOperationFinished (so the RepoState
    /// banner reacts uniformly regardless of which kind of operation this is),
    /// and hands the outcome to `afterFinished` for the caller to decide what
    /// to refresh.
    void submitAndRefresh(std::unique_ptr<Operation> operation,
                          std::function<void(bool succeeded)> afterFinished);

    GitInstallation installation_;
    RepoPaths paths_;
    ThreadPool& readPool_;

    std::unique_ptr<IProcessRunner> runner_;
    std::unique_ptr<CatFileBatch> catFile_;
    std::unique_ptr<RefStore> refStore_;
    std::unique_ptr<HistoryProvider> history_;
    std::unique_ptr<DiffService> diffs_;
    std::unique_ptr<OperationRunner> operations_;
    std::unique_ptr<WorkingCopyStatusReader> workingCopyStatusReader_;
    std::unique_ptr<StashStore> stashStore_;
    std::unique_ptr<WorktreeStore> worktreeStore_;
    std::unique_ptr<RemoteStore> remoteStore_;
    std::unique_ptr<BlameStore> blameStore_;
    std::unique_ptr<FileHistoryStore> fileHistoryStore_;
    std::unique_ptr<ReflogStore> reflogStore_;
    std::unique_ptr<SubmoduleStore> submoduleStore_;
    std::unique_ptr<BisectStore> bisectStore_;
    std::unique_ptr<LfsStore> lfsStore_;
    AskpassWatcher* askpass_ = nullptr;

    SnapshotHolder<GraphSnapshot> graph_;
    SnapshotHolder<RefSnapshot> refs_;
    SnapshotHolder<WorkingCopyStatus> workingCopyStatus_;
    SnapshotHolder<std::vector<StashEntry>> stashes_;
    SnapshotHolder<std::vector<WorktreeInfo>> worktrees_;
    SnapshotHolder<std::vector<RemoteInfo>> remotes_;
    SnapshotHolder<std::vector<SubmoduleInfo>> submodules_;
    SnapshotHolder<BisectStatus> bisectStatus_;
    SnapshotHolder<std::vector<std::string>> lfsPatterns_;
    SnapshotHolder<std::vector<LfsFileInfo>> lfsFiles_;
    std::optional<LfsInstallation> lfsInstallation_;

    /// Cancels the in-flight history walk when a new one starts.
    CancellationSource historyCancel_;
    /// Cancels viewport-driven reads (metadata, diffs) when the user moves on.
    CancellationSource readCancel_;

    int busyCount_ = 0;
};

}  // namespace gbm
