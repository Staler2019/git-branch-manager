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
#include "core/git/ops/BranchOps.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/git/ops/CherryPickOps.h"
#include "core/git/ops/CommitOps.h"
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
#include "core/workers/ThreadPool.h"

#include <QObject>
#include <QString>

#include <chrono>
#include <cstdint>
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
using LocalIdentityPtr = std::shared_ptr<const LocalIdentity>;
using EffectiveIdentityPtr = std::shared_ptr<const EffectiveIdentity>;

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
    /// switching repositories feel immediate. Re-reads refs itself (see the
    /// comment inside), so a caller that just changed something ref-related
    /// and wants both refreshed should call refreshRefsAndHistory() instead
    /// -- this alone is for the cases with no accompanying refreshRefs()
    /// call, e.g. setHistoryFilter().
    void refreshHistory(HistoryQuery query = {});

    /// Sets the branch/ref filter the graph should show from now on (empty
    /// `query.includeRefs` means "show everything", the default) and
    /// refreshes immediately. Unlike a one-off refreshHistory(query) call,
    /// this selection sticks: every bare refreshHistory() afterwards (the
    /// Refresh button, a checkout, a fetch, ...) reapplies it instead of
    /// silently reverting to "show everything".
    void setHistoryFilter(HistoryQuery query);

    /// The filter set by the last setHistoryFilter() call (default-
    /// constructed, i.e. "show everything", if none has been set).
    const HistoryQuery& historyFilter() const { return activeHistoryQuery_; }

    void refreshRefs();

    /// refreshRefs() + refreshHistory() sharing a single `for-each-ref` load
    /// instead of each independently re-running it. Every current call site
    /// that calls both back-to-back should call this instead: measured on a
    /// synthetic repository with ~3.8k refs, the second for-each-ref alone
    /// cost more than the entire rev-list walk that followed it (~750ms vs
    /// ~450ms for 50k commits with a commit-graph) -- see docs/PERFORMANCE.md.
    void refreshRefsAndHistory(HistoryQuery query = {});

    /// Queues metadata for rows the user can actually see. Called by the model on
    /// a cache miss; never blocks the caller.
    void requestCommitMetadata(std::vector<ObjectId> oids);

    /// Requests the changed-file list and diff for a commit.
    void requestCommitDetails(const ObjectId& commit);

    /// Switches branches. `onFinished` runs on the UI thread.
    void checkout(const CheckoutRequest& request);

    // --- Sidebar (Phase 2): branch mutation ---------------------------------
    // BranchOps.h has had these factories since M2; nothing in the app wired
    // them to a UI until the sidebar's branch context menu needed them.

    void createBranch(const CreateBranchRequest& request);
    void renameBranch(const RenameBranchRequest& request);

    /// `git branch -d/-D`, or `git push <remote> --delete <name>` when
    /// `request.isRemote` -- the latter is a network operation and routes
    /// through the same askpass dance as `deleteTag`'s `alsoRemote` path.
    void deleteBranch(const DeleteBranchRequest& request);

    /// Cancels every in-flight read this session may have posted to the
    /// shared read pool -- both readCancel_ (refs, metadata, diffs, working
    /// copy status, ...) and historyCancel_ (the history walk, which
    /// supersedes itself independently on every refreshHistory() call, so it
    /// needs its own explicit cancel here too). Called before destroying this
    /// session (MainWindow::closeRepository) so no queued or in-flight
    /// worker task is still touching it -- see ThreadPool::cancelQueuedAndDrain,
    /// which the caller uses right after this to actually wait for whatever
    /// was already running to notice and stop.
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

    /// Diff of an arbitrary past commit against the current work tree --
    /// "Compare with working copy" on the commit context menu.
    void requestCompareWithWorkingCopy(const ObjectId& commit);

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

    /// `git revert`, for a single commit or several. One-shot only: unlike
    /// cherry-pick, there is no continue/skip/abort entry point yet -- see
    /// RevertOps.h.
    void revertCommit(const RevertRequest& request);

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

    /// Reads one file's content at `revision` (e.g. `"HEAD"` for the last
    /// commit, `""` for the index), for the Working Copy view's read-only
    /// "Original" tab. Mirrors requestConflictSides's threading: a co-process
    /// read on the read pool, hopped back to the UI thread. A path that does
    /// not exist at that revision (a brand-new untracked file has no `HEAD`
    /// side) is reported via `exists = false` on the reply rather than as an
    /// error -- this is a display query, not an operation.
    void requestFileContent(const std::string& path, const std::string& revision);

    // --- M3: stashes -----------------------------------------------------

    StashListPtr stashes() const { return stashes_.current(); }

    void refreshStashes();

    void saveStash(const StashSaveRequest& request);
    void applyStash(const StashApplyRequest& request);
    void dropStash(const StashDropRequest& request);
    void branchFromStash(const StashBranchRequest& request);

    /// Requests `git stash show -p --include-untracked stash@{index}`. Reply
    /// on stashDiffReady. `--include-untracked` is passed unconditionally --
    /// StashEntry does not record whether the stash was created with it, and
    /// asking for it on a stash that has no untracked-files parent is a
    /// documented no-op rather than an error, so this is safe either way.
    void requestStashDiff(int index);

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

    /// Fetches every remote with no credential prompt wired up: if
    /// authentication is needed, the fetch fails immediately (see
    /// FetchRequest::askpassDir's doc comment) instead of surfacing the
    /// askpass dialog. Also skips runWithFeedback's modal-on-failure path --
    /// callers get workingCopyOperationFinished like any other operation, but
    /// nothing shows it unless they wire something up themselves.
    void fetchRemoteSilently();

    /// Calls fetchRemoteSilently() if the "Sync" repository setting
    /// (Repository Settings > Automatically fetch when opening this
    /// repository) is on, debounced so calling this on every repo-open and
    /// every History-tab visit does not hammer the remote.
    void maybeAutoFetch();

    // --- Commit-graph maintenance -------------------------------------------

    /// Filesystem check only, no subprocess -- see hasCommitGraph(RepoPaths)
    /// in core/git/ops/MaintenanceOps.h. Safe to call on the UI thread, unlike
    /// nearly everything else on this class.
    bool hasCommitGraph() const;

    /// The user's saved answer to the commit-graph advice banner/settings
    /// checkbox for this repository. Mirrors RepositoryPage's checkbox state --
    /// see the key-format note on commitGraphPreferenceSetting() in the .cpp.
    CommitGraphPreference commitGraphPreference() const;

    /// `git commit-graph write`, run through the same operation queue as every
    /// other mutation. Unlike fetchRemoteSilently(), this is always something
    /// the user explicitly asked for (the perf banner's "Optimize" button or
    /// the settings card's "Optimize now"), so it drives the busy indicator
    /// like a normal operation instead of running invisibly.
    void writeCommitGraph();

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

    // --- Phase 6: per-repository Git identity override ---------------------

    LocalIdentityPtr localIdentity() const { return localIdentity_.current(); }

    void refreshLocalIdentity();

    /// Whichever `user.name`/`user.email` git itself would attribute a new
    /// commit to here (local override falling back to global/system config).
    /// Used to decide whether a commit in the graph is "mine" -- see
    /// CommitListModel::IsMineRole.
    EffectiveIdentityPtr effectiveIdentity() const { return effectiveIdentity_.current(); }

    void refreshEffectiveIdentity();

    /// Sets `user.name`/`user.email` scoped `--local` to this repository only.
    void setLocalIdentityOverride(const SetLocalIdentityRequest& request);

    /// Unsets both keys locally, so the repository falls back to whatever
    /// global identity `git` finds (`~/.gitconfig` or the environment).
    void clearLocalIdentityOverride();

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
    /// Reply to requestCompareWithWorkingCopy.
    void compareWithWorkingCopyReady(const ObjectId& commit,
                                     std::shared_ptr<const ParsedDiff> diff);
    /// Reply to requestConflictSides, matched back up by path. A stage's
    /// content is empty both when that stage does not exist and when reading
    /// it failed -- the request is best-effort display, not itself an
    /// operation worth failing loudly over.
    void conflictSidesReady(QString path, QString ancestor, QString ours, QString theirs);
    /// Reply to requestFileContent. `exists` is false when `revision:path`
    /// does not resolve to an object (new untracked file, or a path renamed
    /// away by `revision`) -- distinct from an existing-but-empty file, which
    /// reports `exists = true` with an empty `content`.
    void fileContentReady(QString path, QString revision, QString content, bool exists);
    /// Separate from `operationFinished`: MainWindow's checkout-recovery UI
    /// (stash/discard choices) does not apply to staging and commit, so the
    /// working-copy panel gets its own completion signal to react to.
    void workingCopyOperationFinished(OperationOutcome outcome);

    /// Reply to writeCommitGraph(). Separate from workingCopyOperationFinished
    /// so MainWindow's perf banner can react to exactly this operation instead
    /// of filtering every operation outcome for one it happens to recognise.
    void commitGraphWriteFinished(bool succeeded);

    void stashesUpdated();
    /// Reply to requestStashDiff.
    void stashDiffReady(int index, std::shared_ptr<const ParsedDiff> diff);
    void worktreesUpdated();
    void remotesUpdated();
    void submodulesUpdated();
    void bisectStatusUpdated();
    void lfsUpdated();
    void localIdentityUpdated();
    void effectiveIdentityUpdated();

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
    ///
    /// `drivesBusy`: false for background work the user didn't ask for and
    /// shouldn't have to watch (currently just fetchRemoteSilently) -- the UI
    /// should not read as stalled for a network operation nobody triggered.
    /// Every user-initiated caller leaves this at the default.
    void submitAndRefresh(std::unique_ptr<Operation> operation,
                          std::function<void(bool succeeded)> afterFinished,
                          bool drivesBusy = true);

    /// The seed/filter/fingerprint/walk portion shared by refreshHistory()'s
    /// and refreshRefsAndHistory()'s posted tasks -- everything after "I now
    /// have a RefSnapshotPtr". Runs on a worker thread. `refsForSeed` may be
    /// null (refs unreadable, e.g. a repository with no commits yet); the
    /// walk still runs with no seed, matching refreshHistory()'s prior
    /// behaviour. Handles its own busy/error/graphUpdated signalling, so
    /// callers only need to have called setBusy(true) beforehand.
    void walkHistoryWithRefs(HistoryQuery query,
                             RefSnapshotPtr refsForSeed,
                             CancellationToken token);

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
    std::unique_ptr<LocalIdentityStore> localIdentityStore_;
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
    SnapshotHolder<LocalIdentity> localIdentity_;
    SnapshotHolder<EffectiveIdentity> effectiveIdentity_;

    /// Cancels the in-flight history walk when a new one starts.
    CancellationSource historyCancel_;
    /// Cancels viewport-driven reads (metadata, diffs) when the user moves on.
    CancellationSource readCancel_;

    /// State from the last *completed* history walk, used by refreshHistory()
    /// to skip re-running `git rev-list` when nothing that could change its
    /// result (refs, query filters) has happened since. See fingerprintRefs()
    /// in RepositorySession.cpp.
    bool hasLastWalk_ = false;
    std::uint64_t lastWalkFingerprint_ = 0;
    HistoryQuery lastWalkQuery_;

    /// The user's current branch/ref filter -- see setHistoryFilter().
    HistoryQuery activeHistoryQuery_;

    /// Debounce state for maybeAutoFetch(); nullopt before the first call.
    std::optional<std::chrono::steady_clock::time_point> lastAutoFetchAt_;
    /// 30s was tuned for "every History tab visit", which this no longer
    /// runs on (see MainWindow::onShowHistory) -- the remaining triggers are
    /// repo-open and window re-activation (MainWindow::onWindowActivated),
    /// both far less frequent, so a silent `git fetch` no longer needs to be
    /// this eager. Still short enough that opening the app after a while
    /// away, or alt-tabbing back after a long break, picks up new commits.
    static constexpr std::chrono::minutes kAutoFetchMinInterval{5};

    int busyCount_ = 0;
};

}  // namespace gbm
