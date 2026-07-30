#pragma once

#include <atomic>
#include <condition_variable>
#include <cstddef>
#include <deque>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace gbm {

/// A fixed-size worker pool for read-only git work: history walks, diffs,
/// metadata batches, blame.
///
/// The discovery scanner gets its own separate pool. Sharing one would let a
/// long directory walk starve the diff that the user is waiting to see, which is
/// exactly the kind of stall that reads as "the app is slow".
class ThreadPool {
public:
    /// `name` is only used for diagnostics. `threads` of 0 picks a sensible size.
    explicit ThreadPool(std::string name, std::size_t threads = 0);

    ~ThreadPool();

    ThreadPool(const ThreadPool&) = delete;
    ThreadPool& operator=(const ThreadPool&) = delete;

    void post(std::function<void()> task);

    /// Runs before anything already queued. Used for viewport-driven work, where
    /// the newest request reflects where the user is actually looking.
    void postFront(std::function<void()> task);

    std::size_t threadCount() const noexcept { return workers_.size(); }

    std::size_t queueDepth() const;

    /// Blocks until the queue drains. For tests and shutdown only — never call
    /// this from the UI thread.
    void drain();

    void shutdown();

    /// Default pool size: leave one core for the UI thread, clamp to [2, 6].
    /// Beyond ~6 concurrent git readers the disk, not the CPU, is the limit.
    static std::size_t defaultThreadCount();

private:
    void workerLoop();

    const std::string name_;
    mutable std::mutex mutex_;
    std::condition_variable taskAvailable_;
    std::condition_variable idle_;
    std::deque<std::function<void()>> tasks_;
    std::vector<std::thread> workers_;
    std::size_t activeTasks_ = 0;
    bool stopping_ = false;
};

}  // namespace gbm
