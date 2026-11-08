// A read that throws on the shared read pool still answers. Without postRead()'s catch the
// pool's own one only logs (ThreadPool.cpp's workerLoop), and the Dart caller waiting on the
// reply -- History's isRefreshing, a dialog's Completer -- waits for good.
//
// The failures are injected with gbm_test_fail_read(), which arms one postRead() `where` name:
// only the read posted under that name throws, so the reads a session posts on its own cannot
// use it up.
#include "capi/Session.h"
#include "capi/gbm_capi.h"
#include "core/base/Error.h"
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
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

GBM_API void gbm_test_fail_read(const char* where);

namespace gbm::capi {
namespace {

using ::gbm::testing::GitCli;
using Events = std::vector<std::pair<int32_t, std::string>>;

struct EventLog {
    std::mutex mutex;
    std::condition_variable cv;
    Events events;

    void add(int32_t eventType, std::string payload) {
        std::lock_guard<std::mutex> lock(mutex);
        events.emplace_back(eventType, std::move(payload));
        cv.notify_all();
    }

    bool waitFor(const std::function<bool(const Events&)>& pred,
                 std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] { return pred(events); });
    }

    Events snapshot() {
        std::lock_guard<std::mutex> lock(mutex);
        return events;
    }
};

void logCallback(GbmSessionHandle,
                 int32_t eventType,
                 const uint8_t* payload,
                 int32_t payloadLen,
                 void* userData) {
    std::string body;
    if (payload != nullptr) {
        body.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        gbm_free_event_payload(payload);
    }
    static_cast<EventLog*>(userData)->add(eventType, std::move(body));
}

void recordNativeError(const uint8_t* payload, int32_t payloadLen, void* userData) {
    auto* reports = static_cast<std::pair<std::mutex, std::vector<std::string>>*>(userData);
    std::lock_guard<std::mutex> lock(reports->first);
    reports->second.emplace_back(reinterpret_cast<const char*>(payload),
                                 static_cast<std::size_t>(payloadLen));
    gbm_free_event_payload(payload);
}

std::size_t countOf(const Events& events, int32_t type) {
    std::size_t n = 0;
    for (const auto& [eventType, payload] : events) {
        if (eventType == type) ++n;
    }
    return n;
}

const std::string* firstOf(const Events& events, int32_t type) {
    for (const auto& [eventType, payload] : events) {
        if (eventType == type) return &payload;
    }
    return nullptr;
}

bool contains(const std::string& haystack, const std::string& needle) {
    return haystack.find(needle) != std::string::npos;
}

class ReadFailureApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ =
            std::filesystem::temp_directory_path() / ("gbm-readfail-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);
        ASSERT_EQ(git({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(git({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(git({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(git({"config", "commit.gpgsign", "false"}), 0);
        std::ofstream(repo_ / "file.txt") << "hello\n";
        ASSERT_EQ(git({"add", "file.txt"}), 0);
        ASSERT_EQ(git({"commit", "--quiet", "-m", "Initial commit"}), 0);

        gbm_set_native_error_callback(&recordNativeError, &nativeErrors_);
        session_ = gbm_session_open(repo_.string().c_str(), (repo_ / ".git").string().c_str(), "");
        ASSERT_NE(session_, nullptr);
        gbm_register_callback(session_, &logCallback, &log_);
    }

    void TearDown() override {
        if (session_ != nullptr) {
            gbm_session_close(session_);
        }
        gbm_set_native_error_callback(nullptr, nullptr);
        gbm_test_fail_read("");
        std::error_code ec;
        std::filesystem::remove_all(repo_, ec);
    }

    int git(const std::vector<std::string>& args) { return GitCli::run(repo_, args); }

    std::vector<std::string> nativeErrors() {
        std::lock_guard<std::mutex> lock(nativeErrors_.first);
        return nativeErrors_.second;
    }

    bool waitForEvent(int32_t type) {
        return log_.waitFor([type](const Events& events) { return countOf(events, type) > 0; });
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
    std::pair<std::mutex, std::vector<std::string>> nativeErrors_;
};

TEST_F(ReadFailureApiTest, AHistoryRefreshThatThrowsRepliesWithAnUnknownErrorAndIsStillLogged) {
    gbm_test_fail_read("Session::dispatchRefresh");
    gbm_history_refresh(session_);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));
    const std::string error = *firstOf(log_.snapshot(), GBM_EVENT_ERROR_OCCURRED);
    EXPECT_TRUE(contains(error, "\"codeName\":\"Unknown\"")) << error;
    EXPECT_TRUE(contains(error, "\"message\":\"The read failed unexpectedly\"")) << error;

    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"Session::dispatchRefresh\"")) << reports[0];
}

// The refresh's own terminal-path guard must run on the injected throw too, which fires
// before the body: otherwise RefreshCoalescer stays running and history never refreshes again.
TEST_F(ReadFailureApiTest, HistoryStillRefreshesAfterARefreshThatThrew) {
    gbm_test_fail_read("Session::dispatchRefresh");
    gbm_history_refresh(session_);
    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));

    const uint64_t second = gbm_history_refresh(session_);
    ASSERT_NE(second, 0u);
    const std::string covers = "\"coversRequest\":" + std::to_string(second);
    EXPECT_TRUE(log_.waitFor([&](const Events& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_REFS_UPDATED && contains(payload, covers)) return true;
        }
        return false;
    }));
}

TEST_F(ReadFailureApiTest, ABlameThatThrowsRepliesWithAnError) {
    gbm_test_fail_read("Session::requestBlame");
    gbm_request_blame(session_, "file.txt", "", 0, 0);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_BLAME_READY), 0u);
}

// Dart keeps a fetch-triggered preview's failure out of the banner by matching this argv
// (repo_session_repository.dart's _isSuppressedAutoPrunePreviewError); an error without it
// would surface as a banner and leave that remote's in-flight marker behind.
TEST_F(ReadFailureApiTest, APrunePreviewThatThrowsCarriesItsDryRunArgv) {
    gbm_test_fail_read("Session::requestRemotePrunePreview");
    gbm_request_remote_prune_preview(session_, "origin");

    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));
    const std::string error = *firstOf(log_.snapshot(), GBM_EVENT_ERROR_OCCURRED);
    EXPECT_TRUE(contains(error, "\"argv\":[\"git\",\"remote\",\"prune\",\"origin\",\"--dry-run\"]"))
        << error;
}

TEST_F(ReadFailureApiTest, AnArmedNameIsNotUsedUpByAnotherRead) {
    gbm_test_fail_read("Session::requestBlame");
    const uint64_t refresh = gbm_history_refresh(session_);
    const std::string covers = "\"coversRequest\":" + std::to_string(refresh);
    ASSERT_TRUE(log_.waitFor([&](const Events& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_REFS_UPDATED && contains(payload, covers)) return true;
        }
        return false;
    }));
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_ERROR_OCCURRED), 0u);

    gbm_request_blame(session_, "file.txt", "", 0, 0);
    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));
}

TEST_F(ReadFailureApiTest, AnArmedNameFailsOneReadOnly) {
    gbm_test_fail_read("Session::requestBlame");
    gbm_request_blame(session_, "file.txt", "", 0, 0);
    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));

    gbm_request_blame(session_, "file.txt", "", 0, 0);
    ASSERT_TRUE(waitForEvent(GBM_EVENT_BLAME_READY));
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_ERROR_OCCURRED), 1u);
}

struct PostReadProbe {
    std::mutex mutex;
    std::condition_variable cv;
    int always = 0;
    int failures = 0;

    void bump(int& counter) {
        std::lock_guard<std::mutex> lock(mutex);
        ++counter;
        cv.notify_all();
    }

    bool waitForAlways(int n) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, std::chrono::seconds(10), [&] { return always >= n; });
    }
};

TEST(PostRead, RunsOnAlwaysOnceOnEveryPath) {
    PostReadProbe probe;
    const auto onFailure = [&](const GitError&) { probe.bump(probe.failures); };
    const auto onAlways = [&] { probe.bump(probe.always); };

    postRead(ReadLane::Back, "PostReadTest::succeeds", [] {}, onFailure, onAlways);
    postRead(
        ReadLane::Back,
        "PostReadTest::throws",
        [] { throw std::runtime_error("body"); },
        onFailure,
        onAlways);
    gbm_test_fail_read("PostReadTest::injected");
    postRead(ReadLane::Front, "PostReadTest::injected", [] {}, onFailure, onAlways);

    ASSERT_TRUE(probe.waitForAlways(3));
    sharedReadPool().drain();
    std::lock_guard<std::mutex> lock(probe.mutex);
    EXPECT_EQ(probe.always, 3);
    EXPECT_EQ(probe.failures, 2);
}

TEST(PostRead, AFailureReplyThatThrowsIsLoggedAndGoesNoFurther) {
    std::pair<std::mutex, std::vector<std::string>> reports;
    gbm_set_native_error_callback(&recordNativeError, &reports);
    std::atomic<bool> nextRan{false};

    postRead(
        ReadLane::Back,
        "PostReadTest::body",
        [] { throw std::runtime_error("body"); },
        [](const GitError&) { throw std::runtime_error("reply"); });
    postRead(ReadLane::Back, "PostReadTest::next", [&] { nextRan = true; }, [](const GitError&) {});
    sharedReadPool().drain();
    gbm_set_native_error_callback(nullptr, nullptr);

    EXPECT_TRUE(nextRan);
    std::lock_guard<std::mutex> lock(reports.first);
    ASSERT_EQ(reports.second.size(), 2u);
    EXPECT_TRUE(contains(reports.second[0], "\"where\":\"PostReadTest::body\""))
        << reports.second[0];
    EXPECT_TRUE(contains(reports.second[1], "\"where\":\"postRead failure reply\""))
        << reports.second[1];
}

}  // namespace
}  // namespace gbm::capi
