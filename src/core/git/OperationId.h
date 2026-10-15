#pragma once

#include <cstdint>

namespace gbm {

/// The next `OperationRecord::id`, process-wide and never 0. Every producer of
/// operation records draws from this one sequence -- the process runner and
/// the `cat-file --batch` co-process -- so an id names one invocation however
/// many sessions and producers are live.
std::uint64_t nextOperationId();

/// The next id an OperationRunner gives a submitted operation, process-wide and
/// never 0. A separate sequence from nextOperationId(): that one names a git
/// invocation, this one names the queued operation (one capi unit) that may
/// make several. Process-wide because a log row reaches every session open on
/// the same directories, and the id on it is what a user's Cancel names
/// (OperationRunner::cancel) -- two runners counting from 1 would collide.
std::uint64_t nextQueuedOperationId();

/// The queued operation the calling thread is running, or 0. Set only on an
/// OperationRunner's worker thread, by QueuedOperationScope, so every
/// OperationRecord taken while an operation runs can carry its id. Work an
/// operation hands to another thread would see 0.
std::uint64_t currentQueuedOperationId();

/// Marks the calling thread as running queued operation `id` until destroyed.
class QueuedOperationScope {
public:
    explicit QueuedOperationScope(std::uint64_t id);
    ~QueuedOperationScope();

    QueuedOperationScope(const QueuedOperationScope&) = delete;
    QueuedOperationScope& operator=(const QueuedOperationScope&) = delete;
    QueuedOperationScope(QueuedOperationScope&&) = delete;
    QueuedOperationScope& operator=(QueuedOperationScope&&) = delete;
};

}  // namespace gbm
