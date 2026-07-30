#pragma once

#include <atomic>
#include <functional>
#include <memory>
#include <mutex>
#include <utility>
#include <vector>

namespace gbm {

namespace detail {

struct CancellationState {
    std::atomic_bool cancelled{false};
    std::mutex mutex;
    std::vector<std::function<void()>> callbacks;
};

}  // namespace detail

/// Read side of a cancellation signal. Copyable and cheap; every worker task
/// carries one. Superseded work (the user scrolled away, switched repository,
/// changed a filter) is cancelled rather than awaited.
class CancellationToken {
public:
    CancellationToken() = default;

    explicit CancellationToken(std::shared_ptr<detail::CancellationState> state)
        : state_(std::move(state)) {}

    bool isCancelled() const noexcept {
        return state_ && state_->cancelled.load(std::memory_order_acquire);
    }

    /// Registers a callback fired on cancellation, used to tear down a child
    /// process's pipes. If cancellation already happened, runs immediately so
    /// there is no race between registration and the cancel call.
    void onCancel(std::function<void()> callback) const {
        if (!state_) {
            return;
        }
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            if (!state_->cancelled.load(std::memory_order_acquire)) {
                state_->callbacks.push_back(std::move(callback));
                return;
            }
        }
        callback();
    }

private:
    std::shared_ptr<detail::CancellationState> state_;
};

/// Write side. Owned by whoever scheduled the work.
class CancellationSource {
public:
    CancellationSource() : state_(std::make_shared<detail::CancellationState>()) {}

    CancellationToken token() const { return CancellationToken(state_); }

    /// Idempotent and thread-safe. Callbacks run on the calling thread exactly
    /// once, outside the lock so a callback may re-enter safely.
    void cancel() {
        std::vector<std::function<void()>> toRun;
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            if (state_->cancelled.exchange(true, std::memory_order_acq_rel)) {
                return;
            }
            toRun.swap(state_->callbacks);
        }
        for (auto& callback : toRun) {
            callback();
        }
    }

    bool isCancelled() const noexcept { return state_->cancelled.load(std::memory_order_acquire); }

private:
    std::shared_ptr<detail::CancellationState> state_;
};

}  // namespace gbm
