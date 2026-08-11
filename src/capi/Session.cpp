#include "capi/Session.h"

#include "capi/JsonCodec.h"
#include "capi/JsonWriter.h"
#include "core/git/AskpassHelper.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/workers/ThreadPool.h"

#include <algorithm>
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
    std::call_once(flag, [] { Log::instance().setOperationSink(&Session::dispatchOperationLogRecord); });
}

}  // namespace

GitResult<GitInstallation> sharedGitInstallation() {
    static std::mutex mutex;
    static bool resolved = false;
    static GitResult<GitInstallation> cached = fail(GitError::Code::NotFound, "not yet resolved");

    std::lock_guard<std::mutex> lock(mutex);
    if (!resolved) {
        cached = GitExecutable::detect();
        resolved = true;
    }
    return cached;
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

Session::Session(GitInstallation installation, RepoPaths paths, std::unique_ptr<IProcessRunner> runner)
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
      remoteStore_(std::make_unique<RemoteStore>(*runner_, paths_)) {
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
            query,
            [this](GraphSnapshotPtr chunk) { publishGraph(std::move(chunk)); },
            token);

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

void Session::resetTo(ResetRequest request) {
    submitOperation(makeResetOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::refreshWorkingCopy() {
    sharedReadPool().post([this]() {
        const GitResult<WorkingCopyStatusPtr> result = workingCopyStatusReader_->read(CancellationToken{});
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
    operations_->submit(std::move(operation), [this, onSuccess = std::move(onSuccess), onAlways = std::move(onAlways)](
                                                   OperationOutcome outcome) {
        const bool succeeded = outcome.succeeded;
        callbacks_.emit(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, toJson(outcome));
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

void Session::commitChanges(CommitRequest request) {
    submitWorkingCopyOperation(makeCommitOperation(std::move(request)), [this]() {
        refreshWorkingCopy();
        refreshHistory();
    });
}

void Session::submitOperation(std::unique_ptr<Operation> operation, bool refreshHistoryOnSuccess) {
    operations_->submit(std::move(operation), [this, refreshHistoryOnSuccess](OperationOutcome outcome) {
        const bool succeeded = outcome.succeeded;
        callbacks_.emit(GBM_EVENT_OPERATION_FINISHED, toJson(outcome));
        refreshWorkingCopy();
        if (succeeded && refreshHistoryOnSuccess) {
            refreshHistory();
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
    submitWorkingCopyOperation(makeResolveConflictOperation(std::move(request)), [this]() { refreshWorkingCopy(); });
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
        makeStashApplyOperation(std::move(request)), [this]() { refreshStashes(); }, [this]() { refreshWorkingCopy(); });
}

void Session::dropStash(StashDropRequest request) {
    submitWorkingCopyOperation(makeStashDropOperation(std::move(request)), [this]() { refreshStashes(); });
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
    submitWorkingCopyOperation(makeCreateTagOperation(std::move(request)), [this]() { refreshHistory(); });
}

void Session::deleteTag(DeleteTagRequest request) {
    if (request.alsoRemote) {
        request.askpassDir = beginAskpass();
    }
    submitWorkingCopyOperation(
        makeDeleteTagOperation(std::move(request)), [this]() { refreshHistory(); }, [this]() { endAskpass(); });
}

void Session::pushTag(PushTagRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(makePushTagOperation(std::move(request)), /*onSuccess=*/nullptr, [this]() { endAskpass(); });
}

// --- Worktrees ---------------------------------------------------------

void Session::refreshWorktrees() {
    sharedReadPool().post([this]() {
        const GitResult<std::vector<WorktreeInfo>> result = worktreeStore_->list(CancellationToken{});
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
    submitWorkingCopyOperation(makeAddWorktreeOperation(std::move(request)), [this]() { refreshWorktrees(); });
}

void Session::removeWorktree(RemoveWorktreeRequest request) {
    submitWorkingCopyOperation(makeRemoveWorktreeOperation(std::move(request)), [this]() { refreshWorktrees(); });
}

void Session::pruneWorktrees() {
    submitWorkingCopyOperation(makePruneWorktreesOperation(PruneWorktreesRequest{}), [this]() { refreshWorktrees(); });
}

void Session::lockWorktree(LockWorktreeRequest request) {
    submitWorkingCopyOperation(makeLockWorktreeOperation(std::move(request)), [this]() { refreshWorktrees(); });
}

void Session::unlockWorktree(UnlockWorktreeRequest request) {
    submitWorkingCopyOperation(makeUnlockWorktreeOperation(std::move(request)), [this]() { refreshWorktrees(); });
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
        makeFetchOperation(std::move(request)), [this]() { refreshHistory(); }, [this]() { endAskpass(); });
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
        makePushOperation(std::move(request)), [this]() { refreshHistory(); }, [this]() { endAskpass(); });
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

}  // namespace gbm::capi
