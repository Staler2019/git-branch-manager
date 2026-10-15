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
#include "capi/Session.h"
#include "capi/gbm_capi.h"
#include "core/workers/ThreadPool.h"
#include "support/GitCli.h"
#include "support/PoolBlockade.h"

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
#include <thread>
#include <utility>
#include <vector>

namespace gbm::capi {
namespace {

using ::gbm::testing::GitCli;
using ::gbm::testing::PoolBlockade;

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
        // Before gbm_session_close(), and that ordering is the whole of it.
        //
        // A test body's hook captures that body's own locals by reference
        // (`finishes`, `trippedOnFirstFinish`). Those die the moment
        // TestBody() returns -- but `log_` is a fixture member, so the hook
        // outlives them, and gbm_session_close() below cancels every
        // still-queued operation, each of which emits
        // GBM_EVENT_OPERATION_FINISHED straight back into logCallback().
        // Without this line the hook writes to a dead stack frame.
        //
        // Measured, not theorised: ASan reports `stack-use-after-return` on
        // `finishes.fetch_add(1)`, with logCallback -> CallbackRegistry::emit
        // -> OperationRunner::workerLoop above it. Worse than the write
        // itself, the hook *reads* that dead `finishes` to decide whether to
        // call gbm_cancel_operation(session_, 0) -- so a garbage read
        // re-enters a Session already inside its own destructor, which is
        // where the glibc `mutex->__data.__owner == 0` abort and the SEGV in
        // ~Session() both came from.
        //
        // An unsanitised build hides it: the dead frame usually still holds
        // the old value, the branch is not taken, and nothing re-enters.
        // Measured over 100 runs of OperationsStillQueued...: 0/100 plain,
        // 20/100 gcc TSan, 17/100 gcc ASan, 13/100 clang ASan.
        log_.setHook(nullptr);

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

// Session::~Session() used to only drain (wait for every queued operation to
// run to completion naturally) -- closing a session with a backlog of queued
// writes blocked for as long as the backlog took to finish, unbounded for
// the network commands GitCommand runs with no deadline. It now cancels
// (Session::cancelOperations(0)) *before* draining, so a queued-but-not-yet-
// -started operation is skipped rather than awaited -- OperationRunner's
// worker checks the token before starting, same as
// OperationsStillQueuedAreRegisteredAndCancellable above.
//
// Deterministic for the same reason as that test: the worker is serial and
// calls onDone synchronously from inside workerLoop(), so at most the one
// operation already running when gbm_session_close() is called can finish
// normally -- the rest are still queued and provably cancellable.
TEST_F(CancelOperationApiTest, SessionCloseCancelsQueuedOperationsInsteadOfDraining) {
    constexpr int kOperations = 20;
    for (int i = 0; i < kOperations; ++i) {
        gbm_reset_to(session_, "HEAD", /*mode=*/1);
    }

    // Close immediately -- do not wait for completion first. TearDown() must
    // not close a second time.
    gbm_session_close(session_);
    session_ = nullptr;

    int succeeded = 0;
    int cancelled = 0;
    {
        std::lock_guard<std::mutex> lock(log_.mutex);
        for (const auto& [type, payload] : log_.events) {
            if (type != GBM_EVENT_OPERATION_FINISHED) {
                continue;
            }
            if (payload.find("\"succeeded\":false") != std::string::npos) {
                ++cancelled;
            } else {
                ++succeeded;
            }
        }
    }
    EXPECT_LE(succeeded, 1) << "at most the operation already running when "
                                "gbm_session_close() was called should "
                                "complete normally";
    EXPECT_GE(cancelled, kOperations - 1)
        << "every other queued operation must be cancelled, not drained";
}

// ~Session() must drain operations_ *before* the shared read pool. An
// operation's completion callback runs on OperationRunner's worker and, after
// emitting GBM_EVENT_OPERATION_FINISHED, posts refreshWorkingCopy() onto
// sharedReadPool(). Drain the pool first and that post lands after the drain,
// so the task runs once the Session is gone -- the ASan-confirmed
// use-after-free the comment in ~Session() describes.
//
// Made deterministic by holding the callback inside onDone (the hook runs on
// the worker, before the post) while gbm_session_close() starts, then filling
// the pool so the post can only queue. In the right order close() is still in
// operations_->drain() at that point, and the later cancelQueuedAndDrain()
// discards the queued task; in the wrong order the pool was drained long
// before, close() returns, and the task runs when the blockade lifts --
// an event after close() returned.
TEST_F(CancelOperationApiTest, SessionCloseDrainsOperationsBeforeTheReadPool) {
    using namespace std::chrono_literals;
    ThreadPool& pool = sharedReadPool();
    pool.drain();  // open()'s own refreshes, so the blockade below gets every worker

    PoolBlockade blockade(pool.threadCount());
    std::atomic_bool inOnDone{false};
    std::atomic_bool held{false};
    log_.setHook([&](int32_t type) {
        if (type != GBM_EVENT_OPERATION_FINISHED || held.exchange(true)) {
            return;
        }
        inOnDone.store(true);
        std::this_thread::sleep_for(300ms);  // let gbm_session_close() get going
        blockade.fill(pool);
    });

    gbm_reset_to(session_, "HEAD", /*mode=*/1);
    while (!inOnDone.load()) {
        std::this_thread::sleep_for(1ms);
    }
    std::thread releaser([&blockade] {
        std::this_thread::sleep_for(600ms);
        blockade.releaseOne();
        blockade.releaseRest();
    });

    gbm_session_close(session_);
    session_ = nullptr;
    std::size_t eventsAtClose = 0;
    {
        std::lock_guard<std::mutex> lock(log_.mutex);
        eventsAtClose = log_.events.size();
    }

    releaser.join();
    pool.drain();
    log_.setHook(nullptr);  // the hook captures this body's locals

    std::lock_guard<std::mutex> lock(log_.mutex);
    EXPECT_EQ(log_.events.size(), eventsAtClose)
        << "a task this session posted ran after gbm_session_close() returned";
}

// --- A user's Cancel (id != 0), decided per capi unit -----------------------
//
// 使用者裁定 (2026-10-15): a unit that takes a git lock is not cancellable, and
// a refused cancel 「會拋錯」 to Flutter. `git push` updates the remote-tracking
// ref in the same invocation, so PushOperation keeps killableMidFlight() false.
//
// The push is held mid-flight by the remote's pre-receive hook, which waits
// for a file the test creates -- so "running" is a state the test holds, not a
// race it has to win.

/// The queued-operation id of the first running record whose argv holds
/// `token`, or 0 when none has arrived yet.
std::uint64_t runningQueuedIdFor(EventLog& log, const std::string& token) {
    std::lock_guard<std::mutex> lock(log.mutex);
    for (const auto& [type, payload] : log.events) {
        if (type != GBM_EVENT_OPERATION_LOG_RECORD ||
            payload.find("\"running\":true") == std::string::npos ||
            payload.find("\"" + token + "\"") == std::string::npos) {
            continue;
        }
        const std::string key = "\"queuedOperationId\":";
        const auto at = payload.find(key);
        if (at == std::string::npos) return 0;
        return std::stoull(payload.substr(at + key.size()));
    }
    return 0;
}

class HeldPushTest : public CancelOperationApiTest {
protected:
    void SetUp() override {
        CancelOperationApiTest::SetUp();
        if (HasFatalFailure() || IsSkipped()) return;
        remote_ = std::filesystem::path(repo_.string() + "-remote.git");
        release_ = std::filesystem::path(repo_.string() + "-release");
        std::filesystem::remove_all(remote_);
        std::filesystem::remove(release_);
        ASSERT_EQ(GitCli::run(repo_, {"init", "--quiet", "--bare", remote_.string()}), 0);
        {
            std::ofstream hook(remote_ / "hooks" / "pre-receive", std::ios::binary);
            hook << "#!/bin/sh\n"
                 << "while [ ! -f '" << release_.generic_string() << "' ]; do sleep 0.05; done\n"
                 << "cat >/dev/null\n";
        }
        std::filesystem::permissions(remote_ / "hooks" / "pre-receive",
                                     std::filesystem::perms::owner_all,
                                     std::filesystem::perm_options::add);
        ASSERT_EQ(runGit({"remote", "add", "origin", remote_.string()}), 0);
    }

    void TearDown() override {
        releasePush();
        CancelOperationApiTest::TearDown();
        std::error_code ec;
        std::filesystem::remove_all(remote_, ec);
        std::filesystem::remove(release_, ec);
    }

    void releasePush() { std::ofstream(release_) << "go\n"; }

    void startHeldPush() {
        const char* branches[] = {"main"};
        gbm_push(session_, "origin", branches, 1, /*setUpstream=*/1, 0, 0);
    }

    /// Waits for the push's running record and returns its queued id.
    std::uint64_t waitForRunningPush(EventLog& log) {
        std::uint64_t id = 0;
        for (int i = 0; i < 600 && id == 0; ++i) {
            id = runningQueuedIdFor(log, "push");
            if (id == 0) std::this_thread::sleep_for(std::chrono::milliseconds(50));
        }
        return id;
    }

    bool pushFinished(bool& succeeded) {
        const bool done = log_.waitFor([](const auto& events) {
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
            }
            return false;
        });
        std::lock_guard<std::mutex> lock(log_.mutex);
        for (const auto& [type, payload] : log_.events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) {
                succeeded = payload.find("\"succeeded\":true") != std::string::npos;
            }
        }
        return done;
    }

    std::filesystem::path remote_;
    std::filesystem::path release_;
};

TEST_F(HeldPushTest, ARunningPushRefusesCancelAndRaisesAnError) {
    startHeldPush();
    const std::uint64_t id = waitForRunningPush(log_);
    ASSERT_NE(id, 0U) << "the running push record must carry its queued id";

    EXPECT_EQ(gbm_cancel_operation(session_, id), -1) << "-1: running and not cancellable";
    EXPECT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_ERROR_OCCURRED &&
                payload.find("\"codeName\":\"NotCancellable\"") != std::string::npos) {
                return true;
            }
        }
        return false;
    })) << "a refused cancel is raised, not swallowed";

    releasePush();
    bool succeeded = false;
    ASSERT_TRUE(pushFinished(succeeded));
    EXPECT_TRUE(succeeded) << "the push must run to completion untouched";
}

// A record reaches every session open on the same directories; only the one
// whose queue runs the operation may name it for a Cancel.
TEST_F(HeldPushTest, AnotherSessionSeesTheRecordButCannotCancelIt) {
    const std::filesystem::path linked(repo_.string() + "-linked");
    std::filesystem::remove_all(linked);
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "linked", linked.string()}), 0);
    GbmSessionHandle other = gbm_session_open(
        linked.string().c_str(),
        (repo_ / ".git" / "worktrees" / linked.filename()).string().c_str(),
        (repo_ / ".git").string().c_str());
    ASSERT_NE(other, nullptr);
    EventLog otherLog;
    gbm_register_callback(other, &logCallback, &otherLog);
    gbm_worktree_refresh(other);
    ASSERT_TRUE(otherLog.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKTREES_UPDATED) return true;
        }
        return false;
    }));

    startHeldPush();
    const std::uint64_t id = waitForRunningPush(log_);
    ASSERT_NE(id, 0U);

    bool otherSawIt = false;
    for (int i = 0; i < 200 && !otherSawIt; ++i) {
        std::lock_guard<std::mutex> lock(otherLog.mutex);
        for (const auto& [type, payload] : otherLog.events) {
            if (type == GBM_EVENT_OPERATION_LOG_RECORD &&
                payload.find("\"push\"") != std::string::npos &&
                payload.find("\"running\":true") != std::string::npos) {
                otherSawIt = true;
                EXPECT_NE(payload.find("\"queuedOperationId\":0"), std::string::npos)
                    << "not this session's operation: " << payload;
            }
        }
        if (!otherSawIt) std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    EXPECT_TRUE(otherSawIt) << "the linked worktree's session receives the record";
    EXPECT_EQ(gbm_cancel_operation(other, id), 0) << "0: not this session's operation";

    releasePush();
    bool succeeded = false;
    ASSERT_TRUE(pushFinished(succeeded));
    EXPECT_TRUE(succeeded);

    gbm_session_close(other);
    std::error_code ec;
    std::filesystem::remove_all(linked, ec);
}

}  // namespace
}  // namespace gbm::capi
