#include "core/git/OperationRunner.h"

#include "core/base/FsUtil.h"
#include "core/base/Logging.h"
#include "core/git/OperationId.h"
#include "core/git/RefStore.h"

#include <chrono>
#include <utility>

namespace gbm {

OperationRunner::OperationRunner(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {
    worker_ = std::thread([this] { workerLoop(); });
}

OperationRunner::~OperationRunner() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        stopping_ = true;
    }
    work_.notify_all();
    if (worker_.joinable()) {
        worker_.join();
    }
}

RepoState OperationRunner::state() const {
    return RepoState::read(paths_);
}

const std::vector<OperationRunner::UndoEntry>& OperationRunner::undoJournal() const {
    return undoJournal_;
}

OperationRunner::Handle OperationRunner::submit(std::unique_ptr<Operation> operation,
                                                CompletionCallback onDone) {
    Handle handle;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        handle.id = nextQueuedOperationId();
        QueuedOperation queued{handle.id, std::move(operation), std::move(onDone), handle.cancel};
        queue_.push_back(std::move(queued));
    }
    work_.notify_one();
    return handle;
}

bool OperationRunner::runs(std::uint64_t id) const {
    if (id == 0) {
        return false;
    }
    std::lock_guard<std::mutex> lock(mutex_);
    if (id == runningId_) {
        return true;
    }
    for (const auto& queued : queue_) {
        if (queued.id == id) {
            return true;
        }
    }
    return false;
}

OperationRunner::CancelResult OperationRunner::cancel(std::uint64_t id, std::string* description) {
    CancellationSource running;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        for (auto& queued : queue_) {
            if (queued.id == id) {
                // Invariant 2: tripped before the lock is released.
                queued.source.cancel();
                return CancelResult::Cancelled;
            }
        }
        if (id == 0 || id != runningId_) {
            return CancelResult::NotFound;
        }
        if (!runningKillable_) {
            if (description != nullptr) {
                *description = runningDescription_;
            }
            return CancelResult::NotCancellable;
        }
        running = runningSource_;
    }
    // Outside the lock: this runs ProcessRunner's kill callback.
    running.cancel();
    return CancelResult::Cancelled;
}

bool OperationRunner::removeStaleIndexLock() {
    const RepoState current = RepoState::read(paths_);
    if (!current.indexLocked) {
        return true;
    }
    if (!current.indexLockAgeSeconds || *current.indexLockAgeSeconds <= kStaleLockSeconds) {
        return false;
    }
    std::error_code ec;
    std::filesystem::remove(paths_.indexLockFile(), ec);
    return !ec;
}

std::optional<OperationOutcome> OperationRunner::preflight(const Operation& operation) {
    const RepoState current = RepoState::read(paths_);

    if (current.indexLocked) {
        OperationOutcome outcome;
        outcome.succeeded = false;
        outcome.summary = "Another Git process appears to be running in this repository";
        GitError error(GitError::Code::LockHeld,
                       outcome.summary,
                       "Lock file: " + fsutil::utf8FromPath(paths_.indexLockFile()));
        outcome.error = error;
        outcome.choices.push_back({OperationChoice::Kind::Retry, false});
        // Removal is only ever offered for a demonstrably stale lock, and never
        // performed automatically: deleting a live lock corrupts the index.
        if (current.indexLockAgeSeconds && *current.indexLockAgeSeconds > kStaleLockSeconds) {
            outcome.choices.push_back({OperationChoice::Kind::RemoveLock, true});
        }
        return outcome;
    }

    if (current.isSequencerOperation() && !operation.allowedDuringSequencerOperation()) {
        OperationOutcome outcome;
        outcome.succeeded = false;
        outcome.summary = current.describe();
        outcome.error = GitError(GitError::Code::Conflict,
                                 "Finish or abort the operation in progress first",
                                 current.describe());
        // The *sole* choice on this path -- unlike CheckoutOp.cpp/BranchOps.cpp's
        // own Abort entries (deleted below), this one is load-bearing: it is
        // what makes `choices` non-empty at all, which is what
        // WorkspaceScreen reads to auto-push the checkout/delete-branch
        // recovery dialog. Deleting it would silently stop that dialog from
        // opening for a sequencer-busy refusal.
        outcome.choices.push_back({OperationChoice::Kind::Abort, true});
        return outcome;
    }

    return std::nullopt;
}

void OperationRunner::recordUndoPoint(const Operation& operation) {
    // ORIG_HEAD is written by git for some operations but not all, so we record
    // our own point. Without this, offering "undo" for a destructive action would
    // be a promise we could not keep.
    RefStore refStore(runner_, paths_);
    auto head = refStore.readHead(CancellationToken{});

    UndoEntry entry;
    entry.id = undoJournal_.size() + 1;
    entry.description = operation.describe();
    entry.timestamp = std::chrono::duration_cast<std::chrono::seconds>(
                          std::chrono::system_clock::now().time_since_epoch())
                          .count();
    if (head) {
        entry.headBefore = head->target;
        entry.branchBefore = head->branchName;
    }
    undoJournal_.push_back(std::move(entry));

    constexpr std::size_t kMaxUndoEntries = 200;
    if (undoJournal_.size() > kMaxUndoEntries) {
        undoJournal_.erase(undoJournal_.begin());
    }
}

void OperationRunner::workerLoop() {
    for (;;) {
        QueuedOperation queued{0, nullptr, nullptr, CancellationSource{}};
        {
            std::unique_lock<std::mutex> lock(mutex_);
            work_.wait(lock, [this] { return stopping_ || !queue_.empty(); });
            if (stopping_ && queue_.empty()) {
                return;
            }
            queued = std::move(queue_.front());
            queue_.pop_front();
            busy_ = true;
            // cancel()'s invariant 1: running from the instant it left the queue.
            runningId_ = queued.id;
            runningKillable_ = queued.operation->killableMidFlight();
            runningDescription_ = queued.operation->describe();
            runningSource_ = queued.source;
        }

        OperationOutcome outcome;
        if (queued.source.isCancelled()) {
            outcome.succeeded = false;
            outcome.error = GitError(GitError::Code::Cancelled, "Operation cancelled");
        } else if (auto blocked = preflight(*queued.operation)) {
            outcome = std::move(*blocked);
        } else {
            recordUndoPoint(*queued.operation);
            logMessage(LogLevel::Info, "Starting: " + queued.operation->describe());
            try {
                const QueuedOperationScope scope(queued.id);
                outcome = queued.operation->run(runner_, paths_, queued.source.token());
            } catch (const std::exception& ex) {
                // A throwing operation must not take the process down while the
                // user has uncommitted work open.
                outcome.succeeded = false;
                outcome.error = GitError(
                    GitError::Code::Unknown, "The operation failed unexpectedly", ex.what());
            }
        }

        // Stamped here, on the single path every completion (normal, preflight-
        // blocked, or cancelled) funnels through, so it's impossible for an
        // outcome to reach onDone unstamped.
        outcome.kind = queued.operation->kind();

        if (queued.onDone) {
            queued.onDone(std::move(outcome));
        }

        {
            std::lock_guard<std::mutex> lock(mutex_);
            busy_ = false;
            runningId_ = 0;
            runningKillable_ = false;
            if (queue_.empty()) {
                idle_.notify_all();
            }
        }
    }
}

void OperationRunner::drain() {
    std::unique_lock<std::mutex> lock(mutex_);
    idle_.wait(lock, [this] { return queue_.empty() && !busy_; });
}

}  // namespace gbm
