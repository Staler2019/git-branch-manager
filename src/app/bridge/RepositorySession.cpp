#include "app/bridge/RepositorySession.h"

#include "core/base/Logging.h"

#include <QMetaObject>
#include <QMetaType>

#include <utility>

namespace gbm {

RepositorySession::RepositorySession(GitInstallation installation,
                                     RepoPaths paths,
                                     ThreadPool& readPool,
                                     QObject* parent)
    : QObject(parent),
      installation_(std::move(installation)),
      paths_(std::move(paths)),
      readPool_(readPool) {
    runner_ = makeProcessRunner(installation_.executable);
    catFile_ = std::make_unique<CatFileBatch>(installation_.executable, paths_);
    refStore_ = std::make_unique<RefStore>(*runner_, paths_);
    history_ = std::make_unique<HistoryProvider>(*runner_, paths_);
    diffs_ = std::make_unique<DiffService>(*runner_, paths_);
    operations_ = std::make_unique<OperationRunner>(*runner_, paths_);
}

RepositorySession::~RepositorySession() {
    // Cancel first, then let the members go: a worker still holding a reference to
    // this session's services must not outlive them.
    historyCancel_.cancel();
    readCancel_.cancel();
    if (catFile_) {
        catFile_->stop();
    }
}

QString RepositorySession::displayName() const {
    return QString::fromStdString(paths_.displayName());
}

RepoState RepositorySession::state() const {
    return RepoState::read(paths_);
}

void RepositorySession::setBusy(bool busy) {
    // Reference-counted: several reads may be in flight, and the indicator should
    // only clear when the last one finishes.
    const bool wasBusy = busyCount_ > 0;
    busyCount_ += busy ? 1 : -1;
    if (busyCount_ < 0) {
        busyCount_ = 0;
    }
    const bool isBusy = busyCount_ > 0;
    if (isBusy != wasBusy) {
        emit busyChanged(isBusy);
    }
}

void RepositorySession::refreshHistory(HistoryQuery query) {
    // Supersede rather than queue: the previous walk's results are no longer what
    // the user is looking at.
    historyCancel_.cancel();
    historyCancel_ = CancellationSource();
    const CancellationToken token = historyCancel_.token();

    setBusy(true);

    readPool_.post([this, query = std::move(query), token]() mutable {
        // If no explicit tips were given, seed from the refs we already have so the
        // trunk lands in lane 0.
        if (query.includeRefs.empty()) {
            if (auto refs = refs_.current()) {
                query.includeRefs = RefStore::historySeedRefs(*refs);
            }
        }

        auto result = history_->walk(
            query,
            [this, token](GraphSnapshotPtr chunk) {
                if (token.isCancelled()) {
                    return;
                }
                const bool complete = chunk->complete;
                graph_.publish(std::move(chunk));
                // Queued, so the UI thread picks it up in its own event loop.
                QMetaObject::invokeMethod(
                    this, [this, complete] { emit graphUpdated(complete); }, Qt::QueuedConnection);
            },
            token);

        if (!result && result.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(result).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::refreshRefs() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto snapshot = refStore_->load(token);
        if (snapshot) {
            refs_.publish(*snapshot);
            QMetaObject::invokeMethod(this, [this] { emit refsUpdated(); }, Qt::QueuedConnection);
        } else if (snapshot.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(snapshot).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::requestCommitMetadata(std::vector<ObjectId> oids) {
    if (oids.empty()) {
        return;
    }
    const CancellationToken token = readCancel_.token();

    // postFront: the newest request reflects where the user is actually looking,
    // so it must jump ahead of stale viewport requests still in the queue.
    readPool_.postFront([this, oids = std::move(oids), token] {
        if (token.isCancelled()) {
            return;
        }
        if (auto started = catFile_->start(); !started) {
            GitError error = std::move(started).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
            return;
        }
        std::vector<CommitMeta> metadata = catFile_->readCommits(oids);
        if (token.isCancelled() || metadata.empty()) {
            return;
        }
        QMetaObject::invokeMethod(
            this,
            [this, metadata = std::move(metadata)] { emit commitMetadataReady(metadata); },
            Qt::QueuedConnection);
    });
}

void RepositorySession::requestCommitDetails(const ObjectId& commit) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, commit, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }

        const DiffOptions options;
        auto files = diffs_->changedFiles(commit, options, token);
        auto diff = diffs_->commitDiff(commit, options, token);

        if (!token.isCancelled() && files && diff) {
            auto filesPtr = *files;
            auto diffPtr = *diff;
            QMetaObject::invokeMethod(
                this,
                [this, commit, filesPtr, diffPtr] {
                    emit commitDetailsReady(commit, filesPtr, diffPtr);
                },
                Qt::QueuedConnection);
        } else if (files && !files->get()) {
            // Nothing to show; not an error worth a dialog.
        } else if (!files && files.error().code != GitError::Code::Cancelled) {
            GitError error = files.error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }

        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::checkout(const CheckoutRequest& request) {
    setBusy(true);
    operations_->submit(makeCheckoutOperation(request), [this](OperationOutcome outcome) {
        // Runs on the operation runner's serial thread; hop to the UI thread and
        // refresh what the checkout changed.
        QMetaObject::invokeMethod(
            this,
            [this, outcome = std::move(outcome)] {
                setBusy(false);
                emit operationFinished(outcome);
                if (outcome.succeeded) {
                    refreshRefs();
                    refreshHistory();
                }
            },
            Qt::QueuedConnection);
    });
}

void RepositorySession::cancelPendingReads() {
    readCancel_.cancel();
    readCancel_ = CancellationSource();
}

}  // namespace gbm
