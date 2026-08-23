#pragma once

#include <chrono>
#include <condition_variable>
#include <functional>
#include <mutex>
#include <thread>

namespace gbm {

/// A restartable one-shot delay timer running on its own thread.
///
/// This is the driver RefreshCoalescer's doc comment assumes and that this
/// tree does not otherwise have. That comment names "one single-shot QTimer,
/// restarted (`QTimer::start(kDelay)`, which Qt restarts if already running)
/// on every request() call that returns Arm" -- but the Qt RepositorySession
/// that owned the timer is gone, capi has no event loop of its own (the same
/// reason AskpassPoller runs its own thread), and ThreadPool has no delayed
/// post. So the delay needs a thread, and `arm()` deliberately reproduces
/// QTimer::start()'s restart-if-running semantics rather than inventing new
/// ones.
///
/// The callback runs on the timer thread, holding none of this class's
/// locks -- so it may call arm() again, and a re-arm from inside the callback
/// is honoured as the next deadline rather than being lost.
class DelayTimer {
public:
    using Clock = std::chrono::steady_clock;

    /// Starts the timer thread immediately; the thread stays parked until the
    /// first arm().
    explicit DelayTimer(std::function<void()> onFire);

    /// Calls stop().
    ~DelayTimer();

    DelayTimer(const DelayTimer&) = delete;
    DelayTimer& operator=(const DelayTimer&) = delete;
    DelayTimer(DelayTimer&&) = delete;
    DelayTimer& operator=(DelayTimer&&) = delete;

    /// (Re)starts the delay: an arm() before the current deadline *moves*
    /// that deadline rather than queueing a second fire. A zero delay fires
    /// as soon as the timer thread is scheduled, which is what
    /// RefreshCoalescer::onFinished() returning true asks for -- Debouncer's
    /// own "fire immediately, no second wait".
    ///
    /// A no-op after stop(): a session tearing down must not be able to
    /// resurrect the timer from a completion callback that is still
    /// unwinding.
    void arm(std::chrono::milliseconds delay);

    /// Stops the thread and joins it. Any armed-but-unfired deadline is
    /// dropped. Idempotent.
    ///
    /// Must not be called from the fire callback -- it joins the very thread
    /// that callback runs on. No caller here needs to: the callback's job is
    /// to dispatch work, and teardown is owned by whoever owns this object.
    void stop();

private:
    void run();

    std::function<void()> onFire_;

    std::mutex mutex_;
    std::condition_variable cv_;
    bool running_ = true;
    bool armed_ = false;
    Clock::time_point deadline_{};

    std::thread thread_;
};

}  // namespace gbm
