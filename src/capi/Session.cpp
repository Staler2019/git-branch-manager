#include "capi/Session.h"

#include "capi/JsonCodec.h"
#include "capi/JsonWriter.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/workers/ThreadPool.h"

#include <mutex>
#include <utility>

namespace gbm::capi {

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
      diffs_(std::make_unique<DiffService>(*runner_, paths_)) {}

Session::~Session() {
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
    operations_->drain();
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
    operations_->submit(makeCheckoutOperation(std::move(request)), [this](OperationOutcome outcome) {
        const bool succeeded = outcome.succeeded;
        callbacks_.emit(GBM_EVENT_OPERATION_FINISHED, toJson(outcome));
        if (succeeded) {
            refreshHistory();
        }
    });
}

void Session::resetTo(ResetRequest request) {
    operations_->submit(makeResetOperation(std::move(request)), [this](OperationOutcome outcome) {
        const bool succeeded = outcome.succeeded;
        callbacks_.emit(GBM_EVENT_OPERATION_FINISHED, toJson(outcome));
        if (succeeded) {
            refreshHistory();
            refreshWorkingCopy();
        }
    });
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

void Session::submitWorkingCopyOperation(std::unique_ptr<Operation> operation, std::function<void()> onSuccess) {
    operations_->submit(std::move(operation), [this, onSuccess = std::move(onSuccess)](OperationOutcome outcome) {
        const bool succeeded = outcome.succeeded;
        callbacks_.emit(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, toJson(outcome));
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

}  // namespace gbm::capi
