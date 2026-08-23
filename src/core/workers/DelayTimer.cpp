#include "core/workers/DelayTimer.h"

#include <utility>

namespace gbm {

DelayTimer::DelayTimer(std::function<void()> onFire) : onFire_(std::move(onFire)) {
    thread_ = std::thread([this] { run(); });
}

DelayTimer::~DelayTimer() {
    stop();
}

void DelayTimer::arm(std::chrono::milliseconds delay) {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!running_) {
            return;
        }
        deadline_ = Clock::now() + delay;
        armed_ = true;
    }
    cv_.notify_all();
}

void DelayTimer::stop() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!running_) {
            return;
        }
        running_ = false;
        armed_ = false;
    }
    cv_.notify_all();
    if (thread_.joinable()) {
        thread_.join();
    }
}

void DelayTimer::run() {
    for (;;) {
        std::unique_lock<std::mutex> lock(mutex_);
        cv_.wait(lock, [this] { return !running_ || armed_; });
        if (!running_) {
            return;
        }

        // Re-read deadline_ on every wake: an arm() during the wait moves it,
        // and waiting out the *old* deadline would defeat the restart.
        // wait_until never returns before its deadline, so a wake here means
        // either the deadline arrived or someone changed the state.
        while (running_ && armed_ && Clock::now() < deadline_) {
            cv_.wait_until(lock, deadline_);
        }
        if (!running_) {
            return;
        }
        if (!armed_) {
            continue;
        }

        armed_ = false;
        lock.unlock();
        onFire_();
    }
}

}  // namespace gbm
