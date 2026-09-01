// Concurrency and scheduling tests for gbm_history_refresh().
//
// Unlike the rest of tests/capi, the first case here is meaningful only under
// a sanitizer build: it exercises gbm_history_refresh() from several threads
// at once, which is what the real app does (Dart's FFI thread calls it, and
// so does OperationRunner's worker thread from every operation's onSuccess
// callback). Without -fsanitize=thread it is a liveness check; with it, it is
// the falsifiable test for the unguarded CancellationSource assignment inside
// Session::refreshHistory().
//
//     cmake --build build/tsan --target gbm_capi_tests
//     ./build/tsan/tests/gbm_capi_tests --gtest_filter=HistoryRefreshApiTest.*
#include "capi/gbm_capi.h"
#include "support/GitCli.h"

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

    std::size_t completedWalksLocked() const {
        std::size_t count = 0;
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_GRAPH_UPDATED &&
                payload.find("\"complete\":true") != std::string::npos) {
                ++count;
            }
        }
        return count;
    }

    bool waitForCompletedWalks(std::size_t target,
                               std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] { return completedWalksLocked() >= target; });
    }

    /// Blocks until no new event has arrived for `quiet`, or `timeout`
    /// elapses. A refresh burst has a tail -- the walk that the coalescing
    /// window eventually dispatches, plus its log records -- and asserting
    /// on the absence of something requires waiting for that tail rather
    /// than for the first arrival.
    void waitUntilQuiet(std::chrono::milliseconds quiet = std::chrono::milliseconds(600),
                        std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        const auto deadline = std::chrono::steady_clock::now() + timeout;
        std::unique_lock<std::mutex> lock(mutex);
        for (;;) {
            const std::size_t before = events.size();
            if (cv.wait_for(lock, quiet, [&] { return events.size() != before; })) {
                if (std::chrono::steady_clock::now() >= deadline) return;
                continue;
            }
            return;
        }
    }

    /// Operation-log records (event 12) whose payload says the git
    /// invocation was cancelled.
    std::vector<std::string> cancelledRecords() {
        std::lock_guard<std::mutex> lock(mutex);
        std::vector<std::string> out;
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_OPERATION_LOG_RECORD &&
                payload.find("\"cancelled\":true") != std::string::npos) {
                out.push_back(payload);
            }
        }
        return out;
    }

    /// Waits until a predicate over the accumulated events is true, or fails
    /// to meet it before `timeout`.
    bool waitFor(const std::function<bool(const std::vector<std::pair<int32_t, std::string>>&)>& pred,
                std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] { return pred(events); });
    }

    /// Operation-log records (event 12) for the combined HEAD-resolving
    /// invocation (`rev-parse --revs-only HEAD --symbolic-full-name HEAD`) --
    /// RefStore::readHead()'s doc comment explains why that's one process,
    /// not two. Caller must hold `mutex`, matching completedWalksLocked().
    std::size_t headReadInvocationCountLocked() const {
        std::size_t count = 0;
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_OPERATION_LOG_RECORD &&
                payload.find("\"rev-parse\"") != std::string::npos &&
                payload.find("\"--symbolic-full-name\"") != std::string::npos) {
                ++count;
            }
        }
        return count;
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
}

class HistoryRefreshApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() /
                ("gbm-capi-histrefresh-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);
        for (int i = 0; i < 5; ++i) {
            commit("f.txt", "body " + std::to_string(i), "c" + std::to_string(i));
        }

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

    void commit(const std::string& file, const std::string& body, const std::string& message) {
        std::ofstream(repo_ / file) << body << "\n";
        ASSERT_EQ(runGit({"add", file}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", message}), 0);
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

// Session::refreshHistory() cancels and replaces historyCancel_ -- a plain
// shared_ptr assignment -- and is reached from at least two threads in the
// shipping app: gbm_history_refresh() on Dart's FFI thread, and the
// refreshHistory() call inside submitOperation()'s completion callback, which
// runs on OperationRunner's worker thread. Nothing serialised the two.
//
// Green without a sanitizer proves only that nothing crashed; the assertion
// that matters is ThreadSanitizer staying quiet, which is why this test names
// the tsan build in the file header. Kept in the default suite anyway so the
// concurrent path is at least exercised on every run.
TEST_F(HistoryRefreshApiTest, ConcurrentRefreshesDoNotRaceOnTheCancellationSource) {
    constexpr int kThreads = 4;
    constexpr int kCallsPerThread = 25;

    std::vector<std::thread> threads;
    threads.reserve(kThreads);
    for (int t = 0; t < kThreads; ++t) {
        threads.emplace_back([this] {
            for (int i = 0; i < kCallsPerThread; ++i) {
                gbm_history_refresh(session_);
            }
        });
    }
    for (std::thread& thread : threads) {
        thread.join();
    }

    EXPECT_TRUE(log_.waitForCompletedWalks(1))
        << "no walk ever completed after " << (kThreads * kCallsPerThread)
        << " concurrent refreshes";
}

// The defect the user actually reported: a `for-each-ref` line in the log
// drawer carrying exit 143 (= 128 + SIGTERM). refreshHistory() used to cancel
// whatever walk was in flight before posting its own, so every refresh that
// landed on a busy session terminated a perfectly healthy git process and
// left a record behind saying so.
//
// The calls are spaced rather than fired in a tight loop on purpose: each one
// needs a chance to actually start its `for-each-ref` child before the next
// arrives, which is what the shipping app does (an operation finishes, then
// another, then the user hits Refresh) and is what makes the cancelled
// records appear at all.
TEST_F(HistoryRefreshApiTest, ABurstOfRefreshesTerminatesNoGitProcess) {
    for (int i = 0; i < 8; ++i) {
        gbm_history_refresh(session_);
        std::this_thread::sleep_for(std::chrono::milliseconds(15));
    }

    ASSERT_TRUE(log_.waitForCompletedWalks(1)) << "the burst produced no refresh at all";
    log_.waitUntilQuiet();

    const std::vector<std::string> cancelled = log_.cancelledRecords();
    std::string detail;
    for (const std::string& payload : cancelled) {
        detail += "\n  " + payload;
    }
    EXPECT_TRUE(cancelled.empty())
        << cancelled.size()
        << " git invocation(s) were terminated by a superseding refresh:" << detail;
}

// The coalescing claim itself, stated positively. Fired in a tight loop with
// no spacing so the whole burst is inside RefreshCoalescer::kDelay (150 ms)
// by construction rather than by the scheduler's goodwill -- the spaced
// variant above is deliberately shaped for the cancellation question, not
// this one.
TEST_F(HistoryRefreshApiTest, ABurstOfRefreshesYieldsOneWalkNotOnePerCall) {
    for (int i = 0; i < 8; ++i) {
        gbm_history_refresh(session_);
    }

    ASSERT_TRUE(log_.waitForCompletedWalks(1)) << "the burst produced no refresh at all";
    log_.waitUntilQuiet();

    std::lock_guard<std::mutex> lock(log_.mutex);
    EXPECT_EQ(log_.completedWalksLocked(), 1u) << "the burst was not collapsed into one walk";
}

// The failure mode this whole mechanism can produce that the old code could
// not: miss a single terminal path in dispatchRefresh() and the coalescer
// stays running_ forever, so every later request folds into a batch nothing
// will ever drive and refreshes stop happening at all -- silently, with no
// error anywhere. Deleting dispatchRefresh()'s ScopeExit turns this red by
// timeout; the two tests above stay green.
TEST_F(HistoryRefreshApiTest, RefreshesStillWorkAfterABurstHasSettled) {
    for (int i = 0; i < 8; ++i) {
        gbm_history_refresh(session_);
    }
    ASSERT_TRUE(log_.waitForCompletedWalks(1));
    log_.waitUntilQuiet();

    const std::size_t before = [this] {
        std::lock_guard<std::mutex> lock(log_.mutex);
        return log_.completedWalksLocked();
    }();

    gbm_history_refresh(session_);

    EXPECT_TRUE(log_.waitForCompletedWalks(before + 1))
        << "a refresh after a settled burst never ran -- the coalescer is wedged";
}

// The History uncommitted-row connector never drew on Windows: dispatchRefresh()
// used to reuse the HEAD oid captured by refStore_->load() (itself already one
// combined rev-parse process) for the graph walk's lane-0 reservation, even
// though that snapshot predates load()'s own for-each-ref call and the walk
// spawns a third, independent process that re-resolves HEAD's branch name
// fresh. Anything that moved the branch tip in that window -- another tool
// touching the repository, e.g. -- left the reservation permanently unclaimed.
// The fix re-reads HEAD a second time, immediately before the walk. This
// counts the combined rev-parse invocation in the operation log rather than
// trying to force the actual race: a revert of the fix turns this red at 1.
TEST_F(HistoryRefreshApiTest, RefreshReReadsHeadFreshImmediatelyBeforeTheWalk) {
    gbm_history_refresh(session_);

    ASSERT_TRUE(log_.waitForCompletedWalks(1));
    log_.waitUntilQuiet();

    std::lock_guard<std::mutex> lock(log_.mutex);
    EXPECT_EQ(log_.headReadInvocationCountLocked(), 2u)
        << "expected one rev-parse from refStore_->load() plus one fresh "
           "re-read immediately before the history walk";
}

// A dispatchRefresh() that bails out early on a refStore_->load() failure
// must not wedge the session: it should surface as GBM_EVENT_ERROR_OCCURRED,
// and the *next* refresh should recover normally rather than folding into a
// coalescer batch nothing drives.
//
// This is *not* a test of RefStore::readHead()'s specific failure-vs-Unborn
// conflation fix -- that needs isolating rev-parse's failure while
// for-each-ref keeps succeeding, and a real repository can't be put in that
// state: git treats a broken HEAD as "not a git repository" uniformly, so
// rev-parse, for-each-ref and symbolic-ref all fail identically once HEAD is
// gone (confirmed by hand against a real repo). Mutation-tested: this case
// already produced an error under the old readHead() too, via for-each-ref's
// own independent failure -- reverting the readHead() fix alone leaves this
// green. The fix's own coverage is RefStoreHeadTest.cpp's
// AFailedRevParsePropagatesAsAFailureRatherThanUnborn and
// ATimedOutRevParsePropagatesAsAFailure, against a FakeProcessRunner that can
// script rev-parse's response independently of for-each-ref's.
TEST_F(HistoryRefreshApiTest, ALoadFailureDuringRefreshEmitsAnErrorAndRecoversNextCycle) {
    const std::filesystem::path headFile = repo_ / ".git" / "HEAD";
    const std::filesystem::path movedAside = repo_ / ".git" / "HEAD.moved-for-test";
    ASSERT_TRUE(std::filesystem::exists(headFile));
    std::filesystem::rename(headFile, movedAside);

    gbm_history_refresh(session_);

    const bool errored = log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_ERROR_OCCURRED) {
                return true;
            }
        }
        return false;
    });
    EXPECT_TRUE(errored) << "a refStore_->load() failure during refresh produced no error event";

    std::filesystem::rename(movedAside, headFile);

    const std::size_t before = [this] {
        std::lock_guard<std::mutex> lock(log_.mutex);
        return log_.completedWalksLocked();
    }();

    gbm_history_refresh(session_);

    EXPECT_TRUE(log_.waitForCompletedWalks(before + 1))
        << "a refresh after a load() failure never recovered";
}

}  // namespace
}  // namespace gbm::capi
