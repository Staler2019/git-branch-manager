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

#include "capi/CallbackRegistry.h"
#include "capi/gbm_capi.h"
#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/DiffService.h"
#include "core/git/GitExecutable.h"
#include "core/git/HistoryProvider.h"
#include "core/git/IProcessRunner.h"
#include "core/git/OperationRunner.h"
#include "core/git/RefStore.h"
#include "core/git/RepoPaths.h"
#include "core/git/RepoState.h"
#include "core/git/WorkingCopyStatus.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/git/ops/CommitOps.h"
#include "core/git/ops/ResetOps.h"
#include "core/git/ops/StageOps.h"
#include "core/graph/GraphSnapshot.h"
#include "core/workers/ThreadPool.h"

#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

namespace gbm::capi {

/// Resolves and caches the git installation once per process. Every Session
/// shares it: re-probing `git --version` per open repository would be pure
/// waste, and the installation cannot meaningfully change while the process
/// is running.
GitResult<GitInstallation> sharedGitInstallation();

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

    /// Async: see gbm_history_refresh()'s doc comment in gbm_capi.h.
    void refreshHistory();

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

    /// Async: see gbm_commit_changes()'s doc comment in gbm_capi.h.
    void commitChanges(CommitRequest request);

private:
    Session(GitInstallation installation, RepoPaths paths, std::unique_ptr<IProcessRunner> runner);

    void publishGraph(GraphSnapshotPtr snapshot);

    /// Runs `operation` on operations_, emits
    /// GBM_EVENT_WORKING_COPY_OPERATION_FINISHED with its outcome, and on
    /// success calls `onSuccess` (e.g. to chain a refresh) -- the shared
    /// tail of stageFiles/unstageFiles/commitChanges, mirroring
    /// RepositorySession::submitWorkingCopyOperation.
    void submitWorkingCopyOperation(std::unique_ptr<Operation> operation, std::function<void()> onSuccess);

    GitInstallation installation_;
    RepoPaths paths_;
    std::unique_ptr<IProcessRunner> runner_;
    std::unique_ptr<RefStore> refStore_;
    std::unique_ptr<HistoryProvider> history_;
    std::unique_ptr<OperationRunner> operations_;
    std::unique_ptr<WorkingCopyStatusReader> workingCopyStatusReader_;
    std::unique_ptr<DiffService> diffs_;

    CallbackRegistry callbacks_;

    mutable std::mutex graphMutex_;
    GraphSnapshotPtr graph_;
    RefSnapshotPtr refs_;
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

    /// Cancels the in-flight history walk when a newer refreshHistory() call
    /// supersedes it -- mirrors RepositorySession::historyCancel_.
    CancellationSource historyCancel_;
};

}  // namespace gbm::capi
