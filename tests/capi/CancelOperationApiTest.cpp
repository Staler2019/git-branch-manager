// gbm_cancel_operation()'s registration, against a real repo.
//
// The entry point exists with **no Dart or UI caller** (使用者裁定:
// 「開 capi cancellation token 然後先不接線」), so these tests are the only
// thing standing between it and [CULT-orphan-wiring]'s producer-side rot.
//
// What they can and cannot pin, stated rather than implied:
//
//   * They pin the **bookkeeping** -- that every operation is registered
//     while it runs and deregistered when it finishes. That is the half this
//     round wrote, and the half a later edit can silently break.
//   * They do **not** pin that cancelling a *running* `git` kills it. There
//     is no operation at this tier that runs long enough to be caught
//     mid-flight without racing the assertion, and a test that has to win a
//     race is a test that will go red on a loaded CI runner for no reason.
//     That claim rests on cancellation coverage one layer down, which cancels
//     *before* the work starts and is therefore deterministic:
//     ProcessRunnerTest's `source.cancel()` case and GitIntegrationTest's
//     `CancelsAReadOnlyWalkPromptly` / `CommitMetaStoreStopsIssuingRequestsOnceCancelled`.
#include "capi/gbm_capi.h"
#include "support/GitCli.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <gtest/gtest.h>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

namespace gbm::capi {
namespace {

using ::gbm::testing::GitCli;

struct EventLog {
    std::mutex mutex;
    std::condition_variable cv;
    std::vector<std::pair<int32_t, std::string>> events;

    void add(int32_t eventType, std::string payload) {
        std::lock_guard<std::mutex> lock(mutex);
        events.emplace_back(eventType, std::move(payload));
        cv.notify_all();
    }

    bool waitFor(
        const std::function<bool(const std::vector<std::pair<int32_t, std::string>>&)>& pred,
        std::chrono::milliseconds timeout = std::chrono::seconds(30)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] { return pred(events); });
    }

    /// Called after each event is recorded, on the emitting thread.
    ///
    /// Guarded by `mutex`, and that is not belt-and-braces: `gbm_session_open`
    /// kicks off refreshes whose graph/refs/status events are emitted from
    /// pool threads, so a test assigning this hook after open really does race
    /// a concurrent reader. Concurrent read/assign of a `std::function` is UB,
    /// not merely a stale read. Use `setHook()`/`takeHook()` rather than
    /// touching it directly.
    std::function<void(int32_t)> onEvent;

    void setHook(std::function<void(int32_t)> hook) {
        std::lock_guard<std::mutex> lock(mutex);
        onEvent = std::move(hook);
    }

    /// Copied out under the lock and invoked by the caller *outside* it: the
    /// hook reaches back into the capi, and anything it triggers that emits an
    /// event would re-enter `add()` and deadlock on this same mutex.
    std::function<void(int32_t)> takeHook() {
        std::lock_guard<std::mutex> lock(mutex);
        return onEvent;
    }
};

void logCallback(GbmSessionHandle,
                 int32_t eventType,
                 const uint8_t* payload,
                 int32_t payloadLen,
                 void* userData) {
    auto* log = static_cast<EventLog*>(userData);
    std::string body;
    if (payload != nullptr) {
        body.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        gbm_free_event_payload(payload);
    }
    log->add(eventType, std::move(body));
    // Runs on whichever thread emitted -- for GBM_EVENT_OPERATION_FINISHED
    // that is OperationRunner's serial worker, inside its onDone call, which
    // is what the third test needs (see there).
    if (auto hook = log->takeHook()) {
        hook(eventType);
    }
}

class CancelOperationApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() /
                ("gbm-capi-cancel-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "file.txt") << "v1\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "First commit"}), 0);

        session_ = gbm_session_open(repo_.string().c_str(), (repo_ / ".git").string().c_str(), "");
        ASSERT_NE(session_, nullptr);
        gbm_register_callback(session_, &logCallback, &log_);
    }

    void TearDown() override {
        if (session_ != nullptr) {
            gbm_session_close(session_);
        }
        std::error_code ec;
        std::filesystem::remove_all(repo_, ec);
    }

    int runGit(std::vector<std::string> args) { return GitCli::run(repo_, std::move(args)); }

    bool waitForOperationsFinished(std::size_t count) {
        return log_.waitFor([count](const auto& events) {
            std::size_t seen = 0;
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_OPERATION_FINISHED) ++seen;
            }
            return seen >= count;
        });
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(CancelOperationApiTest, CancelOnAnIdleSessionSignalsNothing) {
    // Nothing submitted, so nothing to trip. The value matters: a caller reads
    // this as "how many operations did I just stop", and a session that has
    // never run one must not claim it stopped any.
    EXPECT_EQ(gbm_cancel_operation(session_, 0), 0);
    EXPECT_EQ(gbm_cancel_operation(session_, 1), 0);
}

// A `reset --mixed HEAD` is chosen because it is real (a genuine git process
// through the genuine operation queue), idempotent, and leaves the repository
// exactly as it found it -- so ten of them in a row assert nothing about
// reset and everything about the bookkeeping around it.
TEST_F(CancelOperationApiTest, EveryFinishedOperationIsDeregistered) {
    constexpr int kOperations = 10;
    for (int i = 0; i < kOperations; ++i) {
        gbm_reset_to(session_, "HEAD", /*mode=*/1);
    }
    ASSERT_TRUE(waitForOperationsFinished(kOperations));

    // OperationRunner is serial, so all but the first of these were still
    // queued when they were registered -- their completion callback provably
    // ran after the insert, which is what makes the erase, and not the
    // insert's own ordering, the thing under test here.
    EXPECT_EQ(gbm_cancel_operation(session_, 0), 0)
        << "an operation that has finished must leave nothing behind for a "
           "later cancel to trip";
}

// The one test that can see the *insert*. The other two assert a zero, which
// deleting the registration entirely also produces -- so on their own they
// pin an erase and a no-op equally well ([TEST-fixture-cannot-disagree]).
//
// It is deterministic rather than a race because of two facts that hold
// together: OperationRunner's worker is serial and calls onDone itself
// (OperationRunner.cpp's workerLoop), and CallbackRegistry::emit invokes the
// registered callback synchronously on the emitting thread. So while this
// callback runs, the worker is *inside* operation #1's completion and cannot
// have started #2 -- ops #2..#10 are queued and registered, and #1 has
// already been erased, because submitOperation()'s callback erases before it
// emits. Nine is therefore an exact number, not a floor.
TEST_F(CancelOperationApiTest, OperationsStillQueuedAreRegisteredAndCancellable) {
    constexpr int kOperations = 10;
    std::atomic<int> trippedOnFirstFinish{-1};
    std::atomic<int> finishes{0};

    log_.setHook([&](int32_t eventType) {
        if (eventType != GBM_EVENT_OPERATION_FINISHED) {
            return;
        }
        if (finishes.fetch_add(1) == 0) {
            trippedOnFirstFinish.store(gbm_cancel_operation(session_, 0));
        }
    });

    for (int i = 0; i < kOperations; ++i) {
        gbm_reset_to(session_, "HEAD", /*mode=*/1);
    }
    ASSERT_TRUE(waitForOperationsFinished(kOperations));

    EXPECT_EQ(trippedOnFirstFinish.load(), kOperations - 1)
        << "every queued operation must be registered, and the one that just "
           "finished must already be gone";

    // Cancelling a queued operation is not silent: workerLoop() checks the
    // token before it starts and completes the operation as a failure. Without
    // this, "tripped 9 tokens" could be true of nine tokens attached to
    // nothing.
    int failures = 0;
    {
        std::lock_guard<std::mutex> lock(log_.mutex);
        for (const auto& [type, payload] : log_.events) {
            if (type == GBM_EVENT_OPERATION_FINISHED &&
                payload.find("\"succeeded\":false") != std::string::npos) {
                ++failures;
            }
        }
    }
    EXPECT_EQ(failures, kOperations - 1);
}

}  // namespace
}  // namespace gbm::capi
