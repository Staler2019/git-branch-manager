#include "capi/Session.h"

#include "capi/JsonCodec.h"
#include "capi/JsonWriter.h"
#include "core/base/FsUtil.h"
#include "core/git/AskpassHelper.h"
#include "core/git/TextTraits.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/workers/ThreadPool.h"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <mutex>
#include <utility>
#include <vector>

namespace gbm::capi {

namespace {

// The process-wide registry of open Sessions, keyed implicitly by work tree
// (Session::paths().workDir()) -- see Session::dispatchOperationLogRecord()'s
// doc comment for why this exists: gbm::Log's operation sink is a single
// process-wide callback with no notion of which session a given git
// invocation belongs to, so the sink has to fan the record back out itself.
std::mutex& liveSessionsMutex() {
    static std::mutex mutex;
    return mutex;
}

std::vector<Session*>& liveSessions() {
    static std::vector<Session*> sessions;
    return sessions;
}

void registerLiveSession(Session* session) {
    std::lock_guard<std::mutex> lock(liveSessionsMutex());
    liveSessions().push_back(session);
}

void unregisterLiveSession(Session* session) {
    std::lock_guard<std::mutex> lock(liveSessionsMutex());
    auto& sessions = liveSessions();
    sessions.erase(std::remove(sessions.begin(), sessions.end(), session), sessions.end());
}

void ensureOperationLogSinkInstalled() {
    static std::once_flag flag;
    std::call_once(flag,
                   [] { Log::instance().setOperationSink(&Session::dispatchOperationLogRecord); });
}

std::mutex& gitInstallationMutex() {
    static std::mutex mutex;
    return mutex;
}

bool& gitInstallationResolved() {
    static bool resolved = false;
    return resolved;
}

GitResult<GitInstallation>& cachedGitInstallation() {
    static GitResult<GitInstallation> cached = fail(GitError::Code::NotFound, "not yet resolved");
    return cached;
}

}  // namespace

GitResult<GitInstallation> sharedGitInstallation() {
    std::lock_guard<std::mutex> lock(gitInstallationMutex());
    if (!gitInstallationResolved()) {
        // GBM_GIT_PATH lets someone with several gits installed (or one
        // blocked from running by an OS policy the app cannot see around, e.g.
        // macOS sandboxing) pin the exact executable rather than depend on
        // GitExecutable::detect()'s PATH/fallback search order.
        const char* overridePath = std::getenv("GBM_GIT_PATH");
        cachedGitInstallation() = GitExecutable::detect(
            overridePath != nullptr ? std::filesystem::path(overridePath) : std::filesystem::path{});
        // Only a *successful* detection is cached. Detection failing once (git
        // not yet installed, a permission problem not yet fixed) must not lock
        // that failure in for the rest of the process's lifetime -- the app has
        // no way to prompt a restart, so every later Session::open() would
        // otherwise keep failing even after the user fixes the underlying
        // problem.
        gitInstallationResolved() = cachedGitInstallation().hasValue();
    }
    return cachedGitInstallation();
}

void resetSharedGitInstallationForTest() {
    std::lock_guard<std::mutex> lock(gitInstallationMutex());
    gitInstallationResolved() = false;
}

ThreadPool& sharedReadPool() {
    static ThreadPool pool("gbm_capi_read", ThreadPool::defaultThreadCount());
    return pool;
}

std::unique_ptr<Session> Session::open(std::string workDir,
                                       std::string gitDir,
                                       std::string commonDir,
                                       GitError* outError) {
    const GitResult<GitInstallation> installation = sharedGitInstallation();
    if (!installation) {
        if (outError != nullptr) {
            *outError = installation.error();
        }
        return nullptr;
    }

    RepoPaths paths(std::move(workDir), std::move(gitDir), std::move(commonDir));
    if (!paths.isValid()) {
        if (outError != nullptr) {
            *outError = GitError(GitError::Code::InvalidArgument, "gitDir must not be empty");
        }
        return nullptr;
    }

    std::unique_ptr<IProcessRunner> runner = makeProcessRunner(installation.value().executable);
    return std::unique_ptr<Session>(
        new Session(installation.value(), std::move(paths), std::move(runner)));
}

Session::Session(GitInstallation installation,
                 RepoPaths paths,
                 std::unique_ptr<IProcessRunner> runner)
    : installation_(std::move(installation)),
      paths_(std::move(paths)),
      runner_(std::move(runner)),
      refStore_(std::make_unique<RefStore>(*runner_, paths_)),
      history_(std::make_unique<HistoryProvider>(*runner_, paths_)),
      operations_(std::make_unique<OperationRunner>(*runner_, paths_)),
      workingCopyStatusReader_(std::make_unique<WorkingCopyStatusReader>(*runner_, paths_)),
      diffs_(std::make_unique<DiffService>(*runner_, paths_)),
      stashStore_(std::make_unique<StashStore>(*runner_, paths_)),
      worktreeStore_(std::make_unique<WorktreeStore>(*runner_, paths_)),
      remoteStore_(std::make_unique<RemoteStore>(*runner_, paths_)),
      blameStore_(std::make_unique<BlameStore>(*runner_, paths_)),
      fileHistoryStore_(std::make_unique<FileHistoryStore>(*runner_, paths_)),
      reflogStore_(std::make_unique<ReflogStore>(*runner_, paths_)),
      submoduleStore_(std::make_unique<SubmoduleStore>(*runner_, paths_)),
      bisectStore_(std::make_unique<BisectStore>(*runner_, paths_)),
      lfsStore_(std::make_unique<LfsStore>(*runner_, paths_)),
      localIdentityStore_(std::make_unique<LocalIdentityStore>(*runner_, paths_)) {
    ensureOperationLogSinkInstalled();
    registerLiveSession(this);
}

Session::~Session() {
    // unregisterLiveSession() first, so gbm::Log's sink (which can fire from
    // any thread doing a git invocation) can never look this Session up
    // again once its teardown has started.
    unregisterLiveSession(this);

    // operations_->drain() MUST run before historyCancel_/sharedReadPool()
    // below, not after: OperationRunner::drain() only returns once its
    // worker thread is idle, and that thread runs a submitted operation's
    // completion callback (OperationRunner.cpp's queued.onDone(...)) to
    // completion -- including everything the callback does -- before it
    // clears the busy flag drain() waits on. Several of those callbacks
    // (e.g. pullChanges()'s/fetchRemote()'s onSuccess, which calls
    // refreshHistory()) themselves post a *new* task to sharedReadPool().
    // Draining the shared pool first, as this used to, could run right
    // before that post() call rather than after it: the new task would
    // still be posted afterwards, live on unseen by that drain, and only
    // get to run once this destructor has gone on to free refStore_ and
    // friends below -- a real, ASan-confirmed use-after-free reachable from
    // any caller that closes a session immediately after an operation that
    // chains a refresh finishes (not merely a test-timing artifact: the
    // Flutter side's dispose lifecycle can race the same way). Draining
    // operations_ first guarantees any such post() has already happened,
    // so the sharedReadPool() drain below actually catches it.
    operations_->drain();

    // sharedReadPool() is process-wide (see its doc comment), so this is
    // coarser than RepositorySession::cancelPendingReads() +
    // ThreadPool::cancelQueuedAndDrain(), which safely assume a pool
    // dedicated to the one session being closed: cancelQueuedAndDrain() here
    // also discards any *other* session's not-yet-started work. Acceptable
    // for M0/M1 (repositories are opened and closed one at a time -- see the
    // workspace route's lazy-open/on-dispose lifecycle in the plan), but a
    // real multi-session-concurrently-open story needs a per-session
    // cancellation scope instead of a pool-wide drain. Still required here:
    // without it, a task queued or running on the shared pool could call
    // back into this Session after its destructor returns.
    historyCancel_.cancel();
    sharedReadPool().cancelQueuedAndDrain();

    askpass_.stop();
}

void Session::registerCallback(GbmEventCallback callback, void* userData) {
    callbacks_.set(static_cast<GbmSessionHandle>(this), callback, userData);
}

RepoState Session::repoState() const {
    return RepoState::read(paths_);
}

void Session::refreshHistory() {
    historyCancel_.cancel();
    historyCancel_ = CancellationSource();
    const CancellationToken token = historyCancel_.token();

    sharedReadPool().post([this, token]() {
        const GitResult<RefSnapshotPtr> refsResult = refStore_->load(token);
        if (!refsResult) {
            if (!token.isCancelled()) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(refsResult.error()));
            }
            return;
        }
        {
            std::lock_guard<std::mutex> lock(graphMutex_);
            refs_ = refsResult.value();
        }
        callbacks_.emitEmpty(GBM_EVENT_REFS_UPDATED);

        HistoryQuery query;
        query.seedRefs = RefStore::historySeedRefs(*refsResult.value());

        const GitResult<GraphSnapshotPtr> walkResult = history_->walk(
            query, [this](GraphSnapshotPtr chunk) { publishGraph(std::move(chunk)); }, token);

        if (!walkResult && !token.isCancelled()) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(walkResult.error()));
        }
    });
}

GraphSnapshotPtr Session::currentGraph() const {
    std::lock_guard<std::mutex> lock(graphMutex_);
    return graph_;
}

RefSnapshotPtr Session::currentRefs() const {
    std::lock_guard<std::mutex> lock(graphMutex_);
    return refs_;
}

GraphSnapshotPtr Session::exportGraph() {
    exportedGraph_ = currentGraph();
    return exportedGraph_;
}

void Session::releaseExportedGraph() {
    exportedGraph_.reset();
}

void Session::publishGraph(GraphSnapshotPtr snapshot) {
    const bool complete = snapshot && snapshot->complete;
    {
        std::lock_guard<std::mutex> lock(graphMutex_);
        graph_ = std::move(snapshot);
    }
    std::string payload = "{\"complete\":";
    payload += complete ? "true" : "false";
    payload += '}';
    callbacks_.emit(GBM_EVENT_GRAPH_UPDATED, payload);
}

void Session::checkout(CheckoutRequest request) {
    submitOperation(makeCheckoutOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::createBranch(CreateBranchRequest request) {
    submitOperation(makeCreateBranchOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true);
}

void Session::renameBranch(RenameBranchRequest request) {
    submitOperation(makeRenameBranchOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true);
}

void Session::deleteBranch(DeleteBranchRequest request) {
    submitOperation(makeDeleteBranchOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true);
}

void Session::resetTo(ResetRequest request) {
    submitOperation(makeResetOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::refreshWorkingCopy() {
    sharedReadPool().post([this]() {
        const GitResult<WorkingCopyStatusPtr> result =
            workingCopyStatusReader_->read(CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        {
            std::lock_guard<std::mutex> lock(workingCopyMutex_);
            workingCopyStatus_ = result.value();
        }
        callbacks_.emitEmpty(GBM_EVENT_WORKING_COPY_STATUS_UPDATED);
    });
}

WorkingCopyStatusPtr Session::currentWorkingCopyStatus() const {
    std::lock_guard<std::mutex> lock(workingCopyMutex_);
    return workingCopyStatus_;
}

void Session::requestWorkingCopyDiff(std::string path, bool staged) {
    sharedReadPool().post([this, path = std::move(path), staged]() {
        const DiffOptions options;
        const GitResult<DiffService::ParsedDiffPtr> result =
            diffs_->workingTreeDiff(staged, {path}, options, CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        std::string payload = "{\"path\":";
        jsonAppendEscaped(payload, path);
        payload += ",\"staged\":";
        jsonAppendBool(payload, staged);
        payload += ",\"diff\":";
        payload += toJson(*result.value());
        payload += '}';
        callbacks_.emit(GBM_EVENT_WORKING_COPY_DIFF_READY, payload);
    });
}

void Session::submitWorkingCopyOperation(std::unique_ptr<Operation> operation,
                                         std::function<void()> onSuccess,
                                         std::function<void()> onAlways) {
    operations_->submit(std::move(operation),
                        [this, onSuccess = std::move(onSuccess), onAlways = std::move(onAlways)](
                            OperationOutcome outcome) {
                            const bool succeeded = outcome.succeeded;
                            refreshUndoJournalCache();
                            callbacks_.emit(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED,
                                            toJson(outcome));
                            if (onAlways) {
                                onAlways();
                            }
                            if (succeeded && onSuccess) {
                                onSuccess();
                            }
                        });
}

void Session::stageFiles(std::vector<std::string> paths) {
    submitWorkingCopyOperation(makeStageFilesOperation(StageFilesRequest{std::move(paths)}),
                               [this]() { refreshWorkingCopy(); });
}

void Session::unstageFiles(std::vector<std::string> paths) {
    submitWorkingCopyOperation(makeUnstageFilesOperation(UnstageFilesRequest{std::move(paths)}),
                               [this]() { refreshWorkingCopy(); });
}

void Session::stageHunk(std::string path, std::size_t hunkIndex) {
    PartialStageRequest request;
    request.path = std::move(path);
    request.staged = false;
    request.hunkIndex = hunkIndex;
    submitWorkingCopyOperation(makePartialStageOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::unstageHunk(std::string path, std::size_t hunkIndex) {
    PartialStageRequest request;
    request.path = std::move(path);
    request.staged = true;
    request.hunkIndex = hunkIndex;
    submitWorkingCopyOperation(makePartialStageOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::stageLines(std::string path,
                         std::size_t hunkIndex,
                         std::vector<std::size_t> lineIndices) {
    PartialStageRequest request;
    request.path = std::move(path);
    request.staged = false;
    request.hunkIndex = hunkIndex;
    request.lineIndices = std::move(lineIndices);
    submitWorkingCopyOperation(makePartialStageOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::unstageLines(std::string path,
                           std::size_t hunkIndex,
                           std::vector<std::size_t> lineIndices) {
    PartialStageRequest request;
    request.path = std::move(path);
    request.staged = true;
    request.hunkIndex = hunkIndex;
    request.lineIndices = std::move(lineIndices);
    submitWorkingCopyOperation(makePartialStageOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::commitChanges(CommitRequest request) {
    submitWorkingCopyOperation(makeCommitOperation(std::move(request)), [this]() {
        refreshWorkingCopy();
        refreshHistory();
    });
}

void Session::submitOperation(std::unique_ptr<Operation> operation,
                              bool refreshHistoryOnSuccess,
                              std::function<void()> onSuccess) {
    operations_->submit(std::move(operation),
                        [this, refreshHistoryOnSuccess, onSuccess = std::move(onSuccess)](
                            OperationOutcome outcome) {
                            const bool succeeded = outcome.succeeded;
                            refreshUndoJournalCache();
                            callbacks_.emit(GBM_EVENT_OPERATION_FINISHED, toJson(outcome));
                            refreshWorkingCopy();
                            if (succeeded && refreshHistoryOnSuccess) {
                                refreshHistory();
                            }
                            if (succeeded && onSuccess) {
                                onSuccess();
                            }
                        });
}

void Session::mergeBranch(MergeRequest request) {
    submitOperation(makeMergeOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::abortMerge() {
    submitOperation(makeMergeAbortOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::cherryPick(CherryPickRequest request) {
    submitOperation(makeCherryPickOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::continueCherryPick() {
    submitOperation(makeCherryPickContinueOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::skipCherryPick() {
    submitOperation(makeCherryPickSkipOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::abortCherryPick() {
    submitOperation(makeCherryPickAbortOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::revertCommit(RevertRequest request) {
    submitOperation(makeRevertOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::resolveConflict(ResolveConflictRequest request) {
    submitWorkingCopyOperation(makeResolveConflictOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::requestWorkingTreeContent(std::string path) {
    sharedReadPool().post([this, path = std::move(path)]() {
        // Above this, a conflicted file is treated the same as binary: shown
        // as "not editable" rather than loaded whole into the resolve
        // editor -- mirrors RepositorySession::requestWorkingTreeContent's
        // own cap exactly.
        constexpr std::size_t kMaxEditableWorkingTreeBytes = 8u * 1024u * 1024u;
        const std::filesystem::path target = paths_.workDir() / path;
        const std::optional<std::string> raw =
            fsutil::readSmallFile(target, kMaxEditableWorkingTreeBytes);

        bool editable = false;
        std::string content;
        if (raw.has_value()) {
            const TextTraits traits = detectTextTraits(*raw);
            // A conflicted path that fails this is shown read-only instead
            // of risking silent corruption from a lossy UTF-8 decode --
            // detectTextTraits already folds an embedded NUL into
            // EncodingKind::Binary, matching RepositorySession's own check.
            editable =
                traits.encoding == EncodingKind::Utf8 || traits.encoding == EncodingKind::Utf8Bom;
            if (editable) {
                content = *raw;
            }
        }

        std::string payload = "{\"path\":";
        jsonAppendEscaped(payload, path);
        payload += ",\"content\":";
        jsonAppendEscaped(payload, content);
        payload += ",\"editable\":";
        jsonAppendBool(payload, editable);
        payload += '}';
        callbacks_.emit(GBM_EVENT_WORKING_TREE_CONTENT_READY, payload);
    });
}

// --- Stashes -------------------------------------------------------------

void Session::refreshStashes() {
    sharedReadPool().post([this]() {
        const GitResult<std::vector<StashEntry>> result = stashStore_->list(CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        {
            std::lock_guard<std::mutex> lock(auxMutex_);
            stashes_ = std::make_shared<const std::vector<StashEntry>>(result.value());
        }
        callbacks_.emitEmpty(GBM_EVENT_STASHES_UPDATED);
    });
}

StashListPtr Session::currentStashes() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return stashes_;
}

void Session::saveStash(StashSaveRequest request) {
    submitWorkingCopyOperation(makeStashSaveOperation(std::move(request)), [this]() {
        refreshWorkingCopy();
        refreshStashes();
    });
}

void Session::applyStash(StashApplyRequest request) {
    // Even a conflicting apply/pop leaves the working tree changed -- refresh
    // it unconditionally, matching RepositorySession::applyStash. The stash
    // list is refreshed only on success: pop does not drop its entry on
    // conflict, exactly as plain `git stash pop` does not.
    submitWorkingCopyOperation(
        makeStashApplyOperation(std::move(request)),
        [this]() { refreshStashes(); },
        [this]() { refreshWorkingCopy(); });
}

void Session::dropStash(StashDropRequest request) {
    submitWorkingCopyOperation(makeStashDropOperation(std::move(request)),
                               [this]() { refreshStashes(); });
}

void Session::branchFromStash(StashBranchRequest request) {
    submitWorkingCopyOperation(makeStashBranchOperation(std::move(request)), [this]() {
        refreshWorkingCopy();
        refreshStashes();
        refreshHistory();
    });
}

void Session::requestStashDiff(int index) {
    sharedReadPool().post([this, index]() {
        const GitResult<DiffService::ParsedDiffPtr> result =
            diffs_->stashDiff(index, /*includeUntracked=*/true, DiffOptions{}, CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        std::string payload = "{\"index\":";
        jsonAppendInt(payload, index);
        payload += ",\"diff\":";
        payload += toJson(*result.value());
        payload += '}';
        callbacks_.emit(GBM_EVENT_STASH_DIFF_READY, payload);
    });
}

// --- Tags ------------------------------------------------------------------

void Session::createTag(CreateTagRequest request) {
    submitWorkingCopyOperation(makeCreateTagOperation(std::move(request)),
                               [this]() { refreshHistory(); });
}

void Session::deleteTag(DeleteTagRequest request) {
    if (request.alsoRemote) {
        request.askpassDir = beginAskpass();
    }
    submitWorkingCopyOperation(
        makeDeleteTagOperation(std::move(request)),
        [this]() { refreshHistory(); },
        [this]() { endAskpass(); });
}

void Session::pushTag(PushTagRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(makePushTagOperation(std::move(request)),
                               /*onSuccess=*/nullptr,
                               [this]() { endAskpass(); });
}

// --- Worktrees ---------------------------------------------------------

void Session::refreshWorktrees() {
    sharedReadPool().post([this]() {
        const GitResult<std::vector<WorktreeInfo>> result =
            worktreeStore_->list(CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        {
            std::lock_guard<std::mutex> lock(auxMutex_);
            worktrees_ = std::make_shared<const std::vector<WorktreeInfo>>(result.value());
        }
        callbacks_.emitEmpty(GBM_EVENT_WORKTREES_UPDATED);
    });
}

WorktreeListPtr Session::currentWorktrees() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return worktrees_;
}

void Session::addWorktree(AddWorktreeRequest request) {
    submitWorkingCopyOperation(makeAddWorktreeOperation(std::move(request)),
                               [this]() { refreshWorktrees(); });
}

void Session::removeWorktree(RemoveWorktreeRequest request) {
    submitWorkingCopyOperation(makeRemoveWorktreeOperation(std::move(request)),
                               [this]() { refreshWorktrees(); });
}

void Session::pruneWorktrees() {
    submitWorkingCopyOperation(makePruneWorktreesOperation(PruneWorktreesRequest{}),
                               [this]() { refreshWorktrees(); });
}

void Session::lockWorktree(LockWorktreeRequest request) {
    submitWorkingCopyOperation(makeLockWorktreeOperation(std::move(request)),
                               [this]() { refreshWorktrees(); });
}

void Session::unlockWorktree(UnlockWorktreeRequest request) {
    submitWorkingCopyOperation(makeUnlockWorktreeOperation(std::move(request)),
                               [this]() { refreshWorktrees(); });
}

// --- Remotes -----------------------------------------------------------

void Session::refreshRemotes() {
    sharedReadPool().post([this]() {
        const GitResult<std::vector<RemoteInfo>> result = remoteStore_->list(CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        {
            std::lock_guard<std::mutex> lock(auxMutex_);
            remotes_ = std::make_shared<const std::vector<RemoteInfo>>(result.value());
        }
        callbacks_.emitEmpty(GBM_EVENT_REMOTES_UPDATED);
    });
}

RemoteListPtr Session::currentRemotes() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return remotes_;
}

void Session::fetchRemote(FetchRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makeFetchOperation(std::move(request)),
        [this]() { refreshHistory(); },
        [this]() { endAskpass(); });
}

void Session::pullChanges(PullRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makePullOperation(std::move(request)),
        [this]() { refreshHistory(); },
        [this]() {
            endAskpass();
            refreshWorkingCopy();
        });
}

void Session::pushChanges(PushRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makePushOperation(std::move(request)),
        [this]() { refreshHistory(); },
        [this]() { endAskpass(); });
}

void Session::provideCredential(std::string secret) {
    askpass_.answer(secret);
}

void Session::cancelCredential() {
    askpass_.cancelPrompt();
}

std::filesystem::path Session::beginAskpass() {
    std::filesystem::path dir = askpass::makeRequestDir();
    if (dir.empty()) {
        return dir;
    }
    askpass_.start(dir, [this](std::string prompt) {
        std::string payload = "{\"prompt\":";
        jsonAppendEscaped(payload, prompt);
        payload += '}';
        callbacks_.emit(GBM_EVENT_CREDENTIAL_REQUESTED, payload);
    });
    return dir;
}

void Session::endAskpass() {
    askpass_.stop();
}

void Session::publishOperationLogRecord(const OperationRecord& record) {
    callbacks_.emit(GBM_EVENT_OPERATION_LOG_RECORD, toJson(record));
}

void Session::dispatchOperationLogRecord(const OperationRecord& record) {
    std::lock_guard<std::mutex> lock(liveSessionsMutex());
    for (Session* session : liveSessions()) {
        if (session->paths_.workDir().string() == record.repoDir) {
            session->publishOperationLogRecord(record);
        }
    }
}

// --- Blame / file history / line history / reflog / undo -----------------

void Session::requestBlame(std::string path, std::string revision, int startLine, int endLine) {
    // postFront, not post: a newer blame/file-history/line-history request
    // supersedes an older, still-queued one in interactive priority --
    // matches RepositorySession::requestBlame()'s use of readPool_.postFront.
    sharedReadPool().postFront(
        [this, path = std::move(path), revision = std::move(revision), startLine, endLine]() {
            const GitResult<BlameResultPtr> result =
                blameStore_->blame(path, revision, startLine, endLine, CancellationToken{});
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            callbacks_.emit(GBM_EVENT_BLAME_READY, toJson(*result.value()));
        });
}

void Session::requestFileHistory(std::string path, std::string startRevision) {
    sharedReadPool().postFront(
        [this, path = std::move(path), startRevision = std::move(startRevision)]() {
            const GitResult<std::vector<FileHistoryEntry>> result =
                fileHistoryStore_->fileHistory(path, startRevision, CancellationToken{});
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            callbacks_.emit(GBM_EVENT_FILE_HISTORY_READY, toJson(result.value()));
        });
}

void Session::requestLineHistory(std::string path,
                                 int startLine,
                                 int endLine,
                                 std::string startRevision) {
    sharedReadPool().postFront([this,
                                path = std::move(path),
                                startLine,
                                endLine,
                                startRevision = std::move(startRevision)]() {
        const GitResult<std::vector<LineHistoryChunk>> result = fileHistoryStore_->lineHistory(
            path, startLine, endLine, startRevision, CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        callbacks_.emit(GBM_EVENT_LINE_HISTORY_READY, toJson(result.value()));
    });
}

void Session::requestReflog(std::string ref) {
    // post, not postFront: matches RepositorySession::requestReflog(), the
    // one read-store request among these four that is not treated as
    // preempting other queued reads (see the M6 capi research notes on why
    // the Qt original draws that line here).
    sharedReadPool().post([this, ref = std::move(ref)]() {
        const GitResult<std::vector<ReflogEntry>> result =
            reflogStore_->list(ref, CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        callbacks_.emit(GBM_EVENT_REFLOG_READY, toJson(result.value()));
    });
}

void Session::refreshUndoJournalCache() {
    std::lock_guard<std::mutex> lock(undoMutex_);
    undoJournalCache_ = operations_->undoJournal();
}

std::vector<OperationRunner::UndoEntry> Session::undoJournal() const {
    std::lock_guard<std::mutex> lock(undoMutex_);
    return undoJournalCache_;
}

void Session::undoLastOperation() {
    std::vector<OperationRunner::UndoEntry> journal;
    {
        std::lock_guard<std::mutex> lock(undoMutex_);
        journal = undoJournalCache_;
    }
    if (journal.empty()) {
        return;
    }
    const OperationRunner::UndoEntry& last = journal.back();
    UndoRequest request;
    request.headBefore = last.headBefore;
    request.branchBefore = last.branchBefore;
    submitWorkingCopyOperation(makeUndoOperation(std::move(request)), [this]() {
        refreshWorkingCopy();
        refreshHistory();
    });
}

// --- Restore / clean -------------------------------------------------------

void Session::restorePaths(RestoreRequest request) {
    submitWorkingCopyOperation(makeRestoreOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::requestCleanPreview(bool includeIgnored) {
    sharedReadPool().post([this, includeIgnored]() {
        CleanPreviewer previewer(*runner_, paths_);
        const GitResult<std::vector<CleanEntry>> result =
            previewer.preview(includeIgnored, CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        callbacks_.emit(GBM_EVENT_CLEAN_PREVIEW_READY, toJson(result.value()));
    });
}

void Session::cleanUntracked(CleanRequest request) {
    submitWorkingCopyOperation(makeCleanOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

// --- Rebase ------------------------------------------------------------

void Session::requestRebasePlan(std::string upstream) {
    sharedReadPool().post([this, upstream = std::move(upstream)]() {
        RebasePlanner planner(*runner_, paths_);
        const GitResult<std::vector<RebaseTodoEntry>> result =
            planner.plan(upstream, CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        callbacks_.emit(GBM_EVENT_REBASE_PLAN_READY, toJson(result.value()));
    });
}

void Session::startInteractiveRebase(RebaseInteractiveRequest request) {
    submitOperation(makeRebaseInteractiveOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true);
}

void Session::startRebase(RebaseRequest request) {
    submitOperation(makeRebaseOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::continueRebase() {
    submitOperation(makeRebaseContinueOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::skipRebase() {
    submitOperation(makeRebaseSkipOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::abortRebase() {
    submitOperation(makeRebaseAbortOperation(), /*refreshHistoryOnSuccess=*/true);
}

// --- Submodules ------------------------------------------------------------

void Session::refreshSubmodules() {
    sharedReadPool().post([this]() {
        const GitResult<std::vector<SubmoduleInfo>> result =
            submoduleStore_->list(CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        {
            std::lock_guard<std::mutex> lock(auxMutex_);
            submodules_ = std::make_shared<const std::vector<SubmoduleInfo>>(result.value());
        }
        callbacks_.emitEmpty(GBM_EVENT_SUBMODULES_UPDATED);
    });
}

SubmoduleListPtr Session::currentSubmodules() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return submodules_;
}

void Session::addSubmodule(AddSubmoduleRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makeAddSubmoduleOperation(std::move(request)),
        [this]() {
            refreshWorkingCopy();
            refreshSubmodules();
        },
        [this]() { endAskpass(); });
}

void Session::initSubmodules(SubmodulePathsRequest request) {
    submitWorkingCopyOperation(makeInitSubmodulesOperation(std::move(request)),
                               [this]() { refreshSubmodules(); });
}

void Session::updateSubmodules(UpdateSubmodulesRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makeUpdateSubmodulesOperation(std::move(request)),
        [this]() {
            refreshWorkingCopy();
            refreshSubmodules();
        },
        [this]() { endAskpass(); });
}

void Session::syncSubmodules(SubmodulePathsRequest request) {
    submitWorkingCopyOperation(makeSyncSubmodulesOperation(std::move(request)),
                               [this]() { refreshSubmodules(); });
}

void Session::deinitSubmodules(DeinitSubmodulesRequest request) {
    submitWorkingCopyOperation(makeDeinitSubmodulesOperation(std::move(request)),
                               [this]() { refreshSubmodules(); });
}

// --- Bisect ------------------------------------------------------------

void Session::refreshBisectStatus() {
    sharedReadPool().post([this]() {
        const GitResult<BisectStatus> result = bisectStore_->status(CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        {
            std::lock_guard<std::mutex> lock(auxMutex_);
            bisectStatus_ = std::make_shared<const BisectStatus>(result.value());
        }
        callbacks_.emitEmpty(GBM_EVENT_BISECT_STATUS_UPDATED);
    });
}

BisectStatusPtr Session::currentBisectStatus() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return bisectStatus_;
}

void Session::startBisect(BisectStartRequest request) {
    submitOperation(makeBisectStartOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true,
                    [this]() { refreshBisectStatus(); });
}

void Session::markBisect(BisectMarkRequest request) {
    submitOperation(makeBisectMarkOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true,
                    [this]() { refreshBisectStatus(); });
}

void Session::skipBisect(BisectSkipRequest request) {
    submitOperation(makeBisectSkipOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true,
                    [this]() { refreshBisectStatus(); });
}

void Session::resetBisect(BisectResetRequest request) {
    submitOperation(makeBisectResetOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true,
                    [this]() { refreshBisectStatus(); });
}

// --- LFS ---------------------------------------------------------------

void Session::refreshLfs() {
    const bool needsInstallationProbe = [this]() {
        std::lock_guard<std::mutex> lock(auxMutex_);
        return !lfsInstallation_.has_value();
    }();
    sharedReadPool().post([this, needsInstallationProbe]() {
        bool available;
        if (needsInstallationProbe) {
            // detectLfs() never fails (a missing `git-lfs` is a normal
            // result, not an error -- see its doc comment), so there is no
            // error branch to handle here.
            const LfsInstallation installation =
                detectLfs(*runner_, paths_, CancellationToken{}).value();
            std::lock_guard<std::mutex> lock(auxMutex_);
            lfsInstallation_ = installation;
            available = installation.available;
        } else {
            std::lock_guard<std::mutex> lock(auxMutex_);
            available = lfsInstallation_->available;
        }

        if (!available) {
            // Matches RepositorySession::refreshLfs(): with no `git-lfs` on
            // PATH, `git lfs track`/`git lfs ls-files` would themselves fail
            // (git does not recognise the subcommand), so skip them rather
            // than surfacing that as an error -- there is nothing to list.
            callbacks_.emitEmpty(GBM_EVENT_LFS_UPDATED);
            return;
        }

        // Matches RepositorySession::refreshLfs(): an individual read
        // failing here is not fatal to the refresh as a whole -- whichever
        // of patterns/files succeeded is still published.
        const GitResult<std::vector<std::string>> patterns =
            lfsStore_->trackedPatterns(CancellationToken{});
        const GitResult<std::vector<LfsFileInfo>> files = lfsStore_->listFiles(CancellationToken{});
        {
            std::lock_guard<std::mutex> lock(auxMutex_);
            if (patterns) {
                lfsPatterns_ = std::make_shared<const std::vector<std::string>>(patterns.value());
            }
            if (files) {
                lfsFiles_ = std::make_shared<const std::vector<LfsFileInfo>>(files.value());
            }
        }
        callbacks_.emitEmpty(GBM_EVENT_LFS_UPDATED);
    });
}

std::optional<LfsInstallation> Session::currentLfsInstallation() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return lfsInstallation_;
}

LfsPatternListPtr Session::currentLfsPatterns() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return lfsPatterns_;
}

LfsFileListPtr Session::currentLfsFiles() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return lfsFiles_;
}

void Session::installLfs() {
    submitWorkingCopyOperation(makeLfsInstallOperation(), [this]() { refreshLfs(); });
}

void Session::trackLfsPattern(LfsTrackRequest request) {
    submitWorkingCopyOperation(makeLfsTrackOperation(std::move(request)),
                               [this]() { refreshLfs(); });
}

void Session::untrackLfsPattern(LfsUntrackRequest request) {
    submitWorkingCopyOperation(makeLfsUntrackOperation(std::move(request)),
                               [this]() { refreshLfs(); });
}

void Session::pullLfs(LfsTransferRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makeLfsPullOperation(std::move(request)),
        [this]() {
            refreshWorkingCopy();
            refreshLfs();
        },
        [this]() { endAskpass(); });
}

void Session::fetchLfs(LfsTransferRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makeLfsFetchOperation(std::move(request)),
        [this]() { refreshLfs(); },
        [this]() { endAskpass(); });
}

void Session::pruneLfs(LfsPruneRequest request) {
    submitWorkingCopyOperation(makeLfsPruneOperation(std::move(request)),
                               [this]() { refreshLfs(); });
}

// --- Patch import/export -------------------------------------------------

void Session::exportPatches(ExportPatchesRequest request) {
    submitWorkingCopyOperation(makeExportPatchesOperation(std::move(request)),
                               /*onSuccess=*/nullptr);
}

void Session::applyPatchFiles(ApplyPatchFilesRequest request) {
    submitWorkingCopyOperation(makeApplyPatchFilesOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::importPatches(ImportPatchesRequest request) {
    submitOperation(makeImportPatchesOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true);
}

void Session::continueImport() {
    submitOperation(makeAmContinueOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::skipImport() {
    submitOperation(makeAmSkipOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::abortImport() {
    submitOperation(makeAmAbortOperation(), /*refreshHistoryOnSuccess=*/true);
}

// --- Local Git identity / commit-graph maintenance ------------------------

void Session::refreshLocalIdentity() {
    sharedReadPool().post([this]() {
        const GitResult<LocalIdentity> result = localIdentityStore_->read(CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        {
            std::lock_guard<std::mutex> lock(auxMutex_);
            localIdentity_ = std::make_shared<const LocalIdentity>(result.value());
        }
        callbacks_.emitEmpty(GBM_EVENT_LOCAL_IDENTITY_UPDATED);
    });
}

LocalIdentityPtr Session::currentLocalIdentity() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return localIdentity_;
}

void Session::refreshEffectiveIdentity() {
    sharedReadPool().post([this]() {
        const GitResult<EffectiveIdentity> result =
            localIdentityStore_->readEffective(CancellationToken{});
        if (!result) {
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
            return;
        }
        {
            std::lock_guard<std::mutex> lock(auxMutex_);
            effectiveIdentity_ = std::make_shared<const EffectiveIdentity>(result.value());
        }
        callbacks_.emitEmpty(GBM_EVENT_EFFECTIVE_IDENTITY_UPDATED);
    });
}

EffectiveIdentityPtr Session::currentEffectiveIdentity() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return effectiveIdentity_;
}

void Session::setLocalIdentityOverride(SetLocalIdentityRequest request) {
    submitWorkingCopyOperation(makeSetLocalIdentityOperation(std::move(request)), [this]() {
        refreshLocalIdentity();
        refreshEffectiveIdentity();
    });
}

void Session::clearLocalIdentityOverride() {
    submitWorkingCopyOperation(makeClearLocalIdentityOperation(), [this]() {
        refreshLocalIdentity();
        refreshEffectiveIdentity();
    });
}

bool Session::hasCommitGraph() const {
    return gbm::hasCommitGraph(paths_);
}

void Session::writeCommitGraph() {
    WriteCommitGraphRequest request;
    request.split = installation_.capabilities.commitGraphSplit;
    request.changedPaths = installation_.capabilities.changedPathBloom;
    operations_->submit(makeWriteCommitGraphOperation(request), [this](OperationOutcome outcome) {
        // Keeps undoJournalCache_ in sync with operations_->undoJournal(),
        // exactly like submitOperation()/submitWorkingCopyOperation() do --
        // this bypasses both helpers (it needs its own event, see
        // GBM_EVENT_COMMIT_GRAPH_WRITE_FINISHED's doc comment), but still
        // goes through operations_->submit(), so OperationRunner::
        // recordUndoPoint() still ran and appended an entry.
        refreshUndoJournalCache();
        std::string payload = "{\"succeeded\":";
        jsonAppendBool(payload, outcome.succeeded);
        payload += '}';
        callbacks_.emit(GBM_EVENT_COMMIT_GRAPH_WRITE_FINISHED, payload);
    });
}

}  // namespace gbm::capi
