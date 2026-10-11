// gbm_request_prepared_message() / GBM_EVENT_PREPARED_MESSAGE_READY: the
// message the Working Copy box is prefilled with during a merge or squash
// (prepared-commit-message-spec.html). PreparedMessageStore's own tests pin
// the text; this pins the seam -- the reply arrives, and a failure also
// reaches the ordinary error event, first.
#include "capi/gbm_capi.h"
#include "support/GitCli.h"

#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <fstream>
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
    /// Both kinds, in arrival order, so the error-before-reply order is checkable.
    std::vector<std::pair<int32_t, std::string>> events;

    bool waitForReady(std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] {
            for (const auto& [type, body] : events) {
                if (type == GBM_EVENT_PREPARED_MESSAGE_READY) return true;
            }
            return false;
        });
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
    if (eventType != GBM_EVENT_ERROR_OCCURRED && eventType != GBM_EVENT_PREPARED_MESSAGE_READY) {
        return;
    }
    std::lock_guard<std::mutex> lock(log->mutex);
    log->events.emplace_back(eventType, std::move(body));
    log->cv.notify_all();
}

class PreparedMessageApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() /
                ("gbm-capi-prepared-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);
        ASSERT_EQ(git({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(git({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(git({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(git({"config", "commit.gpgsign", "false"}), 0);
        std::ofstream(repo_ / "f.txt") << "base\n";
        ASSERT_EQ(git({"add", "f.txt"}), 0);
        ASSERT_EQ(git({"commit", "--quiet", "-m", "base"}), 0);
        ASSERT_EQ(git({"checkout", "--quiet", "-b", "topic"}), 0);
        std::ofstream(repo_ / "f.txt") << "topic\n";
        ASSERT_EQ(git({"commit", "--quiet", "-am", "topic change"}), 0);
        ASSERT_EQ(git({"checkout", "--quiet", "main"}), 0);
        std::ofstream(repo_ / "f.txt") << "main\n";
        ASSERT_EQ(git({"commit", "--quiet", "-am", "main change"}), 0);
        ASSERT_NE(git({"merge", "--no-ff", "-m", "Merge branch 'topic'", "topic"}), 0);

        session_ = gbm_session_open(repo_.string().c_str(), (repo_ / ".git").string().c_str(), "");
        ASSERT_NE(session_, nullptr);
        gbm_register_callback(session_, &logCallback, &log_);
    }

    void TearDown() override {
        if (session_ != nullptr) gbm_session_close(session_);
        std::error_code ec;
        std::filesystem::remove_all(repo_, ec);
    }

    int git(std::vector<std::string> args) { return GitCli::run(repo_, std::move(args)); }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(PreparedMessageApiTest, RepliesWithTheStrippedMergeMessageAndNoError) {
    gbm_request_prepared_message(session_);
    ASSERT_TRUE(log_.waitForReady());

    std::lock_guard<std::mutex> lock(log_.mutex);
    ASSERT_EQ(log_.events.size(), 1u) << "a message that was read is no error";
    EXPECT_EQ(log_.events[0].first, GBM_EVENT_PREPARED_MESSAGE_READY);
    EXPECT_EQ(log_.events[0].second, "{\"message\":\"Merge branch 'topic'\"}");
}

TEST_F(PreparedMessageApiTest, AFailedStripRepliesWithAnErrorAfterTheErrorEvent) {
    // M10 (git 2.56.0): an empty core.commentChar makes `git stripspace
    // --strip-comments` exit 128.
    ASSERT_EQ(git({"config", "core.commentChar", ""}), 0);

    gbm_request_prepared_message(session_);
    ASSERT_TRUE(log_.waitForReady());

    std::lock_guard<std::mutex> lock(log_.mutex);
    ASSERT_EQ(log_.events.size(), 2u);
    EXPECT_EQ(log_.events[0].first, GBM_EVENT_ERROR_OCCURRED);
    EXPECT_EQ(log_.events[1].first, GBM_EVENT_PREPARED_MESSAGE_READY);
    EXPECT_NE(log_.events[1].second.find("\"message\":\"\""), std::string::npos)
        << log_.events[1].second;
    EXPECT_NE(log_.events[1].second.find("\"error\":"), std::string::npos)
        << log_.events[1].second;
}

}  // namespace
}  // namespace gbm::capi
