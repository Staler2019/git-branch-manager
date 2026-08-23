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

}  // namespace
}  // namespace gbm::capi
