#pragma once

#include "app/bridge/SnapshotHolder.h"
#include "core/base/CancellationToken.h"
#include "core/git/CatFileBatch.h"
#include "core/git/DiffService.h"
#include "core/git/GitExecutable.h"
#include "core/git/HistoryProvider.h"
#include "core/git/OperationRunner.h"
#include "core/git/RefStore.h"
#include "core/git/RepoState.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/graph/GraphSnapshot.h"
#include "core/workers/ThreadPool.h"

#include <QObject>
#include <QString>

#include <memory>
#include <vector>

namespace gbm {

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

private:
    void setBusy(bool busy);

    GitInstallation installation_;
    RepoPaths paths_;
    ThreadPool& readPool_;

    std::unique_ptr<IProcessRunner> runner_;
    std::unique_ptr<CatFileBatch> catFile_;
    std::unique_ptr<RefStore> refStore_;
    std::unique_ptr<HistoryProvider> history_;
    std::unique_ptr<DiffService> diffs_;
    std::unique_ptr<OperationRunner> operations_;

    SnapshotHolder<GraphSnapshot> graph_;
    SnapshotHolder<RefSnapshot> refs_;

    /// Cancels the in-flight history walk when a new one starts.
    CancellationSource historyCancel_;
    /// Cancels viewport-driven reads (metadata, diffs) when the user moves on.
    CancellationSource readCancel_;

    int busyCount_ = 0;
};

}  // namespace gbm
