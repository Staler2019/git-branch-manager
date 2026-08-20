// Integration tests for the M5 stash slice of the extern "C" surface
// (gbm_capi.h), against a real repository with uncommitted changes.
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
};

bool anyEventOfType(const std::vector<std::pair<int32_t, std::string>>& events, int32_t type) {
    for (const auto& [eventType, payload] : events) {
        if (eventType == type) return true;
    }
    return false;
}

void logCallback(GbmSessionHandle, int32_t eventType, const uint8_t* payload, int32_t payloadLen, void* userData) {
    auto* log = static_cast<EventLog*>(userData);
    std::string body;
    if (payload != nullptr) {
        body.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        gbm_free_event_payload(payload);
    }
    log->add(eventType, std::move(body));
}

class StashApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-stash-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "tracked.txt") << "line1\n";
        ASSERT_EQ(runGit({"add", "tracked.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Initial commit"}), 0);

        std::ofstream(repo_ / "tracked.txt") << "line1\nline2\n";

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

    /// Fixture git, without a shell in the middle -- see tests/support/GitCli.h
    /// for why that matters (one process instead of two, and no per-platform
    /// quoting hazard).
    int runGit(std::vector<std::string> args) {
        return ::gbm::testing::GitCli::run(repo_, std::move(args));
    }

    std::string stashesJson() {
        [[maybe_unused]] const int32_t rc = gbm_stashes_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(StashApiTest, SaveStashRemovesChangesAndAddsAnEntry) {
    gbm_stash_save(session_, "WIP", /*includeUntracked=*/0, /*keepIndex=*/0, nullptr, 0);

    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_STASHES_UPDATED); }));

    const std::string json = stashesJson();
    EXPECT_NE(json.find("\"message\""), std::string::npos) << json;
    EXPECT_NE(json.find("WIP"), std::string::npos) << json;

    std::ifstream trackedFile(repo_ / "tracked.txt");
    std::string content((std::istreambuf_iterator<char>(trackedFile)), std::istreambuf_iterator<char>());
    EXPECT_EQ(content, "line1\n") << "stash save should have restored the file to HEAD's content";
}

TEST_F(StashApiTest, ApplyRestoresChanges) {
    gbm_stash_save(session_, "WIP", 0, 0, nullptr, 0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_STASHES_UPDATED); }));
    log_.clear();

    gbm_stash_apply(session_, /*index=*/0, /*pop=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    }));

    std::ifstream trackedFile(repo_ / "tracked.txt");
    std::string content((std::istreambuf_iterator<char>(trackedFile)), std::istreambuf_iterator<char>());
    EXPECT_EQ(content, "line1\nline2\n");

    // apply (not pop) leaves the entry in the list.
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_STASHES_UPDATED); }));
    const std::string json = stashesJson();
    EXPECT_NE(json.find("\"index\":0"), std::string::npos) << json;
}

TEST_F(StashApiTest, DropRemovesTheEntry) {
    gbm_stash_save(session_, "WIP", 0, 0, nullptr, 0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_STASHES_UPDATED); }));
    log_.clear();

    gbm_stash_drop(session_, 0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_STASHES_UPDATED); }));

    const std::string json = stashesJson();
    EXPECT_EQ(json, "[]") << json;
}

TEST_F(StashApiTest, RequestDiffReportsTheStashedChange) {
    gbm_stash_save(session_, "WIP", 0, 0, nullptr, 0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_STASHES_UPDATED); }));
    log_.clear();

    gbm_stash_request_diff(session_, 0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_STASH_DIFF_READY); }));

    std::string diffPayload;
    {
        std::lock_guard<std::mutex> lock(log_.mutex);
        for (const auto& [type, payload] : log_.events) {
            if (type == GBM_EVENT_STASH_DIFF_READY) diffPayload = payload;
        }
    }
    EXPECT_NE(diffPayload.find("\"index\":0"), std::string::npos) << diffPayload;
    EXPECT_NE(diffPayload.find("\"text\":\"line2\""), std::string::npos) << diffPayload;
}

}  // namespace
}  // namespace gbm::capi
