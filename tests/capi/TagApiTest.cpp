// Integration tests for the M5 tag slice of the extern "C" surface
// (gbm_capi.h). Push/remote-delete exercise against a local bare
// repository reached over the plain filesystem transport, which needs no
// credentials -- git never invokes askpass for it, so these stay fully
// offline like every other capi test.
#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"
#include "support/GitCli.h"

#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
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
    std::vector<std::pair<int32_t, std::string>> events;

    void add(int32_t eventType, std::string payload) {
        std::lock_guard<std::mutex> lock(mutex);
        events.emplace_back(eventType, std::move(payload));
        cv.notify_all();
    }

    bool waitFor(const std::function<bool(const std::vector<std::pair<int32_t, std::string>>&)>& pred,
                std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] { return pred(events); });
    }

    void clear() {
        std::lock_guard<std::mutex> lock(mutex);
        events.clear();
    }

    std::string lastPayloadOfType(int32_t type) {
        std::lock_guard<std::mutex> lock(mutex);
        std::string last;
        for (const auto& [eventType, payload] : events) {
            if (eventType == type) last = payload;
        }
        return last;
    }
};

void logCallback(GbmSessionHandle, int32_t eventType, const uint8_t* payload, int32_t payloadLen, void* userData) {
    auto* log = static_cast<EventLog*>(userData);
    std::string body;
    if (payload != nullptr) {
        body.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        gbm_free_event_payload(payload);
    }
    log->add(eventType, std::move(body));
}

bool waitForWorkingCopyOperationFinished(EventLog& log) {
    return log.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    });
}

class TagApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-tag-" + std::string(info->name()));
        remote_ = std::filesystem::temp_directory_path() / ("gbm-capi-tag-remote-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::remove_all(remote_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runIn(remote_.parent_path(), {"init", "--quiet", "--bare", remote_.string()}), 0);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);
        ASSERT_EQ(runGit({"remote", "add", "origin", remote_.string()}), 0);

        std::ofstream(repo_ / "file.txt") << "content\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Initial commit"}), 0);
        ASSERT_EQ(runGit({"push", "--quiet", "origin", "main"}), 0);

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
        std::filesystem::remove_all(remote_, ec);
    }

    int runGit(std::vector<std::string> args) { return runIn(repo_, std::move(args)); }

    int runIn(const std::filesystem::path& dir, std::vector<std::string> args) {
        return GitCli::run(dir, std::move(args));
    }

    bool remoteHasTag(const std::string& name) {
        return runIn(remote_, {"rev-parse", "--verify", "--quiet", "refs/tags/" + name}) == 0;
    }

    std::filesystem::path repo_;
    std::filesystem::path remote_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(TagApiTest, CreateTagAddsALocalTag) {
    gbm_tag_create(session_, "v1.0.0", "", "Release 1.0.0", /*force=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;

    EXPECT_EQ(runGit({"rev-parse", "--verify", "--quiet", "refs/tags/v1.0.0"}), 0);
}

TEST_F(TagApiTest, DeleteTagRemovesTheLocalTag) {
    ASSERT_EQ(runGit({"tag", "v1.0.0"}), 0);

    gbm_tag_delete(session_, "v1.0.0", /*alsoRemote=*/0, "");
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    EXPECT_NE(runGit({"rev-parse", "--verify", "--quiet", "refs/tags/v1.0.0"}), 0);
}

TEST_F(TagApiTest, PushTagUploadsItToTheRemote) {
    ASSERT_EQ(runGit({"tag", "v1.0.0"}), 0);

    gbm_tag_push(session_, "origin", "v1.0.0");
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    EXPECT_TRUE(remoteHasTag("v1.0.0"));
}

TEST_F(TagApiTest, DeleteTagAlsoRemoteRemovesItFromTheRemote) {
    ASSERT_EQ(runGit({"tag", "v1.0.0"}), 0);
    ASSERT_EQ(runGit({"push", "--quiet", "origin", "v1.0.0"}), 0);
    ASSERT_TRUE(remoteHasTag("v1.0.0"));

    gbm_tag_delete(session_, "v1.0.0", /*alsoRemote=*/1, "origin");
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    EXPECT_FALSE(remoteHasTag("v1.0.0"));
}

}  // namespace
}  // namespace gbm::capi
