#pragma once

#include <chrono>
#include <cstdint>

namespace gbm {

/// Collapses a burst of events into one action, and coalesces requests that
/// arrive while an action is already running.
///
/// Both halves matter for filesystem events. A single `git checkout` on a large
/// tree produces thousands of notifications; without debouncing that becomes
/// thousands of `git status` runs. And because a status run on a 500 MB tree takes
/// hundreds of milliseconds, requests *will* arrive mid-flight — so rather than
/// queueing them, a dirty bit is set and exactly one more run follows.
class Debouncer {
public:
    /// Ordinary work-tree events settle quickly.
    static constexpr std::chrono::milliseconds kWorkTreeDelay{250};
    /// `.git` events get longer: git writes several files in quick succession
    /// during an operation, and reacting to the first one reads a half-written state.
    static constexpr std::chrono::milliseconds kGitDirDelay{750};

    using Clock = std::chrono::steady_clock;

    explicit Debouncer(std::chrono::milliseconds delay = kWorkTreeDelay) : delay_(delay) {}

    /// Records an event. Resets the settle timer.
    void notifyEvent(Clock::time_point now = Clock::now()) {
        lastEvent_ = now;
        pending_ = true;
    }

    /// True when the quiet period has elapsed and work should start. Marks the
    /// action as running, so further events set the dirty bit instead.
    bool shouldFire(Clock::time_point now = Clock::now()) {
        if (running_) {
            if (pending_) {
                dirty_ = true;
            }
            return false;
        }
        if (!pending_) {
            return false;
        }
        if (now - lastEvent_ < delay_) {
            return false;
        }
        pending_ = false;
        running_ = true;
        return true;
    }

    /// Call when the action finishes. Returns true when it must run again because
    /// events arrived while it was in flight.
    bool finish() {
        running_ = false;
        if (dirty_) {
            dirty_ = false;
            pending_ = true;
            lastEvent_ = Clock::time_point{};  // Fire immediately, no second wait.
            return true;
        }
        return false;
    }

    bool isRunning() const noexcept { return running_; }

    bool hasPending() const noexcept { return pending_ || dirty_; }

    void setDelay(std::chrono::milliseconds delay) { delay_ = delay; }

private:
    std::chrono::milliseconds delay_;
    Clock::time_point lastEvent_{};
    bool pending_ = false;
    bool running_ = false;
    bool dirty_ = false;
};

}  // namespace gbm
