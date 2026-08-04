#pragma once

#include <algorithm>
#include <atomic>
#include <cstdint>
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
    std::vector<std::pair<std::uint64_t, std::function<void()>>> callbacks;
    std::uint64_t nextCallbackId = 0;
};

inline void removeCallback(CancellationState& state, std::uint64_t id) {
    std::lock_guard<std::mutex> lock(state.mutex);
    auto& callbacks = state.callbacks;
    callbacks.erase(std::remove_if(callbacks.begin(),
                                   callbacks.end(),
                                   [id](const auto& entry) { return entry.first == id; }),
                    callbacks.end());
}

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

    /// RAII handle for one onCancel() registration: unregisters the callback
    /// on destruction (or an explicit reset()). Move-only, so exactly one
    /// owner decides when the callback's captures stop being valid --
    /// whoever calls onCancel() must keep the returned Registration alive
    /// for at least as long as anything the callback closes over. This is
    /// what ProcessRunner::execute() uses to stop a callback capturing a
    /// stack local from outliving the stack frame that registered it: every
    /// return path destroys the local Registration first.
    ///
    /// A callback that is mid-fire (CancellationSource::cancel() already
    /// swapped it out of the callback list) and a concurrent reset() are
    /// both safe -- they never touch the same list entry at once, since
    /// cancel() removes every callback from the list before invoking any of
    /// them.
    class Registration {
    public:
        Registration() = default;
        Registration(const Registration&) = delete;
        Registration& operator=(const Registration&) = delete;

        Registration(Registration&& other) noexcept { *this = std::move(other); }

        Registration& operator=(Registration&& other) noexcept {
            if (this != &other) {
                reset();
                state_ = std::move(other.state_);
                id_ = other.id_;
                other.state_.reset();
            }
            return *this;
        }

        ~Registration() { reset(); }

        /// Unregisters early, if still registered. Idempotent.
        void reset() {
            if (state_) {
                detail::removeCallback(*state_, id_);
                state_.reset();
            }
        }

    private:
        friend class CancellationToken;

        Registration(std::shared_ptr<detail::CancellationState> state, std::uint64_t id)
            : state_(std::move(state)), id_(id) {}

        std::shared_ptr<detail::CancellationState> state_;
        std::uint64_t id_ = 0;
    };

    /// Registers a callback fired on cancellation, used to tear down a child
    /// process's pipes. If cancellation already happened, runs immediately so
    /// there is no race between registration and the cancel call -- in that
    /// case the returned Registration is already empty, since there is
    /// nothing left to unregister. The caller owns the returned Registration
    /// and must keep it alive for exactly as long as the callback's captures
    /// are valid.
    [[nodiscard]] Registration onCancel(std::function<void()> callback) const {
        if (!state_) {
            return Registration{};
        }
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            if (!state_->cancelled.load(std::memory_order_acquire)) {
                const std::uint64_t id = state_->nextCallbackId++;
                state_->callbacks.emplace_back(id, std::move(callback));
                return Registration(state_, id);
            }
        }
        callback();
        return Registration{};
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
        std::vector<std::pair<std::uint64_t, std::function<void()>>> toRun;
        {
            std::lock_guard<std::mutex> lock(state_->mutex);
            if (state_->cancelled.exchange(true, std::memory_order_acq_rel)) {
                return;
            }
            toRun.swap(state_->callbacks);
        }
        for (auto& [id, callback] : toRun) {
            callback();
        }
    }

    bool isCancelled() const noexcept { return state_->cancelled.load(std::memory_order_acquire); }

private:
    std::shared_ptr<detail::CancellationState> state_;
};

}  // namespace gbm
