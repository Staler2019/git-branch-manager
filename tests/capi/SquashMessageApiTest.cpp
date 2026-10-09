// gbm_request_squash_message() / GBM_EVENT_SQUASH_MESSAGE_READY: the Merge
// dialog's squash preview (ruling ⑨). The payload echoes the source and both
// oids the text was built from, so a caller can tell a stale reply from a
// current one -- SquashMessageStore's own tests pin the text itself.
#include "capi/gbm_capi.h"
#include "support/GitCli.h"

#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <mutex>
#include <string>
#include <vector>

namespace gbm::capi {
namespace {

using ::gbm::testing::GitCli;

struct EventLog {
    std::mutex mutex;
    std::condition_variable cv;
    std::vector<std::string> squashPayloads;

    bool waitForSquash(std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] { return !squashPayloads.empty(); });
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
    if (eventType != GBM_EVENT_SQUASH_MESSAGE_READY) return;
    std::lock_guard<std::mutex> lock(log->mutex);
    log->squashPayloads.push_back(std::move(body));
    log->cv.notify_all();
}

class SquashMessageApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() /
                ("gbm-capi-squash-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);
        ASSERT_EQ(git({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(git({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(git({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(git({"config", "commit.gpgsign", "false"}), 0);
        std::ofstream(repo_ / "f.txt") << "base\n";
        ASSERT_EQ(git({"add", "f.txt"}), 0);
        ASSERT_EQ(git({"commit", "--quiet", "-m", "base"}), 0);
        ASSERT_EQ(git({"checkout", "--quiet", "-b", "feature"}), 0);
        std::ofstream(repo_ / "g.txt") << "g\n";
        ASSERT_EQ(git({"add", "g.txt"}), 0);
        ASSERT_EQ(git({"commit", "--quiet", "-m", "Add g"}), 0);
        ASSERT_EQ(git({"checkout", "--quiet", "main"}), 0);

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

    std::string oid(const std::string& rev) {
        return GitCli::capture(repo_, {"rev-parse", rev}).firstLine();
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(SquashMessageApiTest, EchoesTheSourceAndBothOidsWithGitsMessage) {
    gbm_request_squash_message(session_, "feature");
    ASSERT_TRUE(log_.waitForSquash());
    const std::string payload = log_.squashPayloads.front();

    EXPECT_NE(payload.find("\"source\":\"feature\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"headOid\":\"" + oid("main") + "\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"sourceOid\":\"" + oid("feature") + "\""), std::string::npos)
        << payload;
    EXPECT_NE(payload.find("\"message\":\"Squashed commit of the following:\\n\\ncommit "),
              std::string::npos)
        << payload;
    EXPECT_EQ(payload.find("\"error\""), std::string::npos) << payload;
}

TEST_F(SquashMessageApiTest, AnUnknownSourceRepliesWithAnErrorAndNoMessage) {
    // Still a SQUASH_MESSAGE_READY, not GBM_EVENT_ERROR_OCCURRED: a preview
    // that cannot be built is the dialog's business (it leaves the box
    // empty), not a failure banner over the whole window.
    gbm_request_squash_message(session_, "no-such-branch");
    ASSERT_TRUE(log_.waitForSquash());
    const std::string payload = log_.squashPayloads.front();

    EXPECT_NE(payload.find("\"source\":\"no-such-branch\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"message\":\"\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"error\":"), std::string::npos) << payload;
}

}  // namespace
}  // namespace gbm::capi
