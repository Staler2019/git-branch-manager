#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/ObjectId.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"
#include "core/git/RepoState.h"

#include <atomic>
#include <condition_variable>
#include <cstdint>
#include <deque>
#include <functional>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace gbm {

/// A choice the user must make before an operation can proceed. The runner never
/// picks for them: silently stashing or force-discarding someone's uncommitted
/// work is not a decision software should take on its own.
struct OperationChoice {
    enum class Kind { StashAndRetry, ForceDiscard, Abort, Retry, RemoveLock };
    Kind kind;
    std::string label;
    std::string explanation;
    bool destructive = false;
};

struct OperationOutcome {
    bool succeeded = false;
    std::optional<GitError> error;
    /// Populated when the failure is recoverable by choosing one of these.
    std::vector<OperationChoice> choices;
    std::string summary;
    /// Stamped from the operation's Operation::kind() by OperationRunner just
    /// before this outcome is handed to its onDone callback. Empty for any
    /// operation that does not override kind() -- JsonCodec omits the "kind"
    /// key entirely in that case rather than emitting an empty string.
    std::string kind;
};

/// A single mutating git operation.
class Operation {
public:
    virtual ~Operation() = default;

    /// Human description, used in the undo journal and the progress dialog.
    virtual std::string describe() const = 0;

    /// A stable, machine-readable slug identifying this operation's kind (e.g.
    /// "checkout", "delete-branch"), or empty if the operation doesn't need
    /// one. Unlike describe(), this is not for display -- it lets a caller on
    /// the other side of the event bus (Dart's PendingOperationTracker) match
    /// a GBM_EVENT_OPERATION_FINISHED outcome back to the request that
    /// produced it, since OperationRunner's queue can hold more than one
    /// operation at a time and completion events arrive one at a time in FIFO
    /// order but with nothing else identifying which request they answer.
    virtual std::string kind() const { return {}; }

    /// Whether killing the child process mid-flight is safe.
    ///
    /// Almost always false. Terminating `git merge` or `git rebase` part-way can
    /// leave a repository in a state neither we nor the user expects, so "Cancel"
    /// for those means running the operation's own --abort afterwards, not a kill.
    virtual bool killableMidFlight() const { return false; }

    /// Runs the operation. Called on the repository's serial queue.
    virtual OperationOutcome run(IProcessRunner& runner,
                                 const RepoPaths& paths,
                                 CancellationToken token) = 0;

    /// Operations that are themselves recovery steps (continue/skip/abort) are
    /// allowed to start while a sequencer operation is in progress; everything
    /// else is refused with an explanation.
    virtual bool allowedDuringSequencerOperation() const { return false; }
};

/// Serialises every mutating operation for one repository.
///
/// One queue per repository means we can never race ourselves for `index.lock`.
/// Cross-process races (the user's terminal, an IDE, a hook) remain possible, so
/// each operation still checks for the lock and reports it rather than stomping.
class OperationRunner {
public:
    /// A lock younger than this is assumed live: offering to delete it would
    /// invite users to break a running operation.
    static constexpr std::int64_t kStaleLockSeconds = 600;

    OperationRunner(IProcessRunner& runner, RepoPaths paths);
    ~OperationRunner();

    OperationRunner(const OperationRunner&) = delete;
    OperationRunner& operator=(const OperationRunner&) = delete;

    struct Handle {
        std::uint64_t id = 0;
        CancellationSource cancel;
    };

    using CompletionCallback = std::function<void(OperationOutcome)>;

    /// Queues an operation. The callback runs on the serial thread; the app layer
    /// marshals it back to the UI thread.
    Handle submit(std::unique_ptr<Operation> operation, CompletionCallback onDone);

    /// Current on-disk state. Cheap; safe to call often.
    RepoState state() const;

    /// Deletes `.git/index.lock`, but only after re-validating server-side
    /// that it is still older than kStaleLockSeconds -- never trusts a
    /// caller's "the user already confirmed this". Runs directly on the
    /// calling thread rather than through submit(): preflight() refuses
    /// every *queued* operation while indexLocked is true, so modelling
    /// this as an Operation would make it refuse itself before it ever ran.
    ///
    /// Returns true when the lock is gone afterwards -- whether because this
    /// call removed it or because it was already gone (the other process
    /// finished on its own between the offer and the click; nothing left to
    /// refuse). Returns false only when a lock is present and not yet stale,
    /// the same threshold preflight() itself uses to decide whether to offer
    /// removal in the first place.
    bool removeStaleIndexLock();

    /// Records what an operation is about to change, so it can be offered as an
    /// undo afterwards. Returns the journal entry id.
    struct UndoEntry {
        std::uint64_t id = 0;
        std::string description;
        ObjectId headBefore;
        std::string branchBefore;
        std::int64_t timestamp = 0;
    };

    const std::vector<UndoEntry>& undoJournal() const;

    /// Blocks until the queue is empty. Tests and shutdown only.
    void drain();

private:
    void workerLoop();
    /// Refuses to start when a lock is held or an incompatible operation is in
    /// progress, returning the choices that would unblock it.
    std::optional<OperationOutcome> preflight(const Operation& operation);
    void recordUndoPoint(const Operation& operation);

    IProcessRunner& runner_;
    RepoPaths paths_;

    struct QueuedOperation {
        std::uint64_t id;
        std::unique_ptr<Operation> operation;
        CompletionCallback onDone;
        CancellationToken token;
    };

    mutable std::mutex mutex_;
    std::condition_variable work_;
    std::condition_variable idle_;
    std::deque<QueuedOperation> queue_;
    std::thread worker_;
    std::vector<UndoEntry> undoJournal_;
    std::uint64_t nextId_ = 1;
    bool busy_ = false;
    bool stopping_ = false;
};

}  // namespace gbm
