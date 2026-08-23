// DelayTimer is the driver RefreshCoalescer's doc comment assumes and this
// tree does not otherwise have (see the class comment for why capi needs a
// thread rather than an event loop).
//
// The timing assertions are one-directional on purpose: "has not fired yet"
// can only break if the timer fires *early*, which wait_until forbids, so a
// loaded machine makes those cases more true rather than less. The only
// assertions with a real timeout are the "eventually fires" ones, and they
// wait far longer than the delay they are checking.
#include "core/workers/DelayTimer.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <gtest/gtest.h>
#include <mutex>
#include <thread>
#include <vector>

namespace gbm {
namespace {

using namespace std::chrono_literals;

/// Records when each fire happened, so a test can assert *which* deadline a
/// fire belongs to rather than only how many there were.
class FireLog {
public:
    void record() {
        std::lock_guard<std::mutex> lock(mutex_);
        times_.push_back(DelayTimer::Clock::now());
        cv_.notify_all();
    }

    std::size_t count() {
        std::lock_guard<std::mutex> lock(mutex_);
        return times_.size();
    }

    bool waitForCount(std::size_t target, std::chrono::milliseconds timeout = 5s) {
        std::unique_lock<std::mutex> lock(mutex_);
        return cv_.wait_for(lock, timeout, [&] { return times_.size() >= target; });
    }

    DelayTimer::Clock::time_point at(std::size_t index) {
        std::lock_guard<std::mutex> lock(mutex_);
        return times_.at(index);
    }

private:
    std::mutex mutex_;
    std::condition_variable cv_;
    std::vector<DelayTimer::Clock::time_point> times_;
};

TEST(DelayTimer, DoesNotFireUntilArmed) {
    FireLog log;
    DelayTimer timer([&log] { log.record(); });

    std::this_thread::sleep_for(80ms);

    EXPECT_EQ(log.count(), 0u);
}

TEST(DelayTimer, FiresOnceAfterTheDelayHasElapsed) {
    FireLog log;
    DelayTimer timer([&log] { log.record(); });

    const DelayTimer::Clock::time_point armedAt = DelayTimer::Clock::now();
    timer.arm(120ms);

    ASSERT_TRUE(log.waitForCount(1)) << "the armed deadline never fired";
    EXPECT_GE(log.at(0) - armedAt, 115ms) << "fired before its deadline";
    std::this_thread::sleep_for(150ms);
    EXPECT_EQ(log.count(), 1u) << "one arm() produced more than one fire";
}

// The behaviour RefreshCoalescer::RefreshAction::Arm depends on: a second
// request inside the window must move the deadline, not queue a second run.
// The first delay is long enough (400ms) that the 50ms sleep below would have
// to overrun by 350ms for this to misreport -- the assertion is on *when* the
// fire happened relative to the second arm(), not on a sleep landing on time.
TEST(DelayTimer, ReArmingMovesTheDeadlineInsteadOfQueueingASecondFire) {
    FireLog log;
    DelayTimer timer([&log] { log.record(); });

    timer.arm(400ms);
    std::this_thread::sleep_for(50ms);
    const DelayTimer::Clock::time_point reArmedAt = DelayTimer::Clock::now();
    timer.arm(400ms);

    ASSERT_TRUE(log.waitForCount(1));
    EXPECT_GE(log.at(0) - reArmedAt, 390ms)
        << "fired on the first deadline -- arm() queued rather than restarted";
    std::this_thread::sleep_for(200ms);
    EXPECT_EQ(log.count(), 1u) << "two arm() calls inside one window produced two fires";
}

// What RefreshCoalescer::onFinished() returning true asks for: "fire
// immediately, no second wait" (Debouncer::finish()'s own wording).
TEST(DelayTimer, ArmingWithNoDelayFiresWithoutWaiting) {
    FireLog log;
    DelayTimer timer([&log] { log.record(); });

    timer.arm(0ms);

    EXPECT_TRUE(log.waitForCount(1, 2s));
}

TEST(DelayTimer, StopDropsAnArmedButUnfiredDeadline) {
    FireLog log;
    DelayTimer timer([&log] { log.record(); });

    timer.arm(200ms);
    timer.stop();
    std::this_thread::sleep_for(400ms);

    EXPECT_EQ(log.count(), 0u);
}

// Session's teardown ordering relies on this: an in-flight walk's completion
// path can call arm() while the destructor is already unwinding, and that
// must not resurrect the timer thread.
TEST(DelayTimer, ArmAfterStopIsANoOp) {
    FireLog log;
    DelayTimer timer([&log] { log.record(); });

    timer.stop();
    timer.arm(0ms);
    std::this_thread::sleep_for(200ms);

    EXPECT_EQ(log.count(), 0u);
}

TEST(DelayTimer, StopIsIdempotentAndTheDestructorStopsToo) {
    FireLog log;
    {
        DelayTimer timer([&log] { log.record(); });
        timer.arm(300ms);
        timer.stop();
        timer.stop();
    }
    std::this_thread::sleep_for(400ms);

    EXPECT_EQ(log.count(), 0u);
}

}  // namespace
}  // namespace gbm
