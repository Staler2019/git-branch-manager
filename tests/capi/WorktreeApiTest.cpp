// Integration tests for the M5 worktree slice of the extern "C" surface
// (gbm_capi.h).
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

class WorktreeApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        // GitCli detects git once per test binary and caches it; this used to
        // be a GitExecutable::detect() per suite, i.e. one `git --version`
        // process each -- 29 of them across this binary.
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-wt-" + std::string(info->name()));
        extra_ = std::filesystem::temp_directory_path() / ("gbm-capi-wt-extra-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::remove_all(extra_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "file.txt") << "content\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Initial commit"}), 0);

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
        std::filesystem::remove_all(extra_, ec);
    }

    /// Fixture git, without a shell in the middle -- see tests/support/GitCli.h
    /// for why that matters (one process instead of two, and no per-platform
    /// quoting hazard).
    int runGit(std::vector<std::string> args) {
        return GitCli::run(repo_, std::move(args));
    }

    std::string worktreesJson() {
        [[maybe_unused]] const int32_t rc = gbm_worktrees_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    std::filesystem::path repo_;
    std::filesystem::path extra_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(WorktreeApiTest, AddWorktreeCreatesANewCheckout) {
    gbm_worktree_add(
        session_, extra_.string().c_str(), "", /*createBranch=*/1, "feature", /*detach=*/0, /*force=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));

    EXPECT_TRUE(std::filesystem::exists(extra_ / "file.txt"));
    const std::string json = worktreesJson();
    EXPECT_NE(json.find("\"branch\":\"feature\""), std::string::npos) << json;
}

TEST_F(WorktreeApiTest, RemoveWorktreeDeletesTheCheckout) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);

    gbm_worktree_remove(session_, extra_.string().c_str(), /*force=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));

    EXPECT_FALSE(std::filesystem::exists(extra_));
}

TEST_F(WorktreeApiTest, LockThenUnlockClearsTheLockedFlag) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);

    gbm_worktree_lock(session_, extra_.string().c_str(), "testing");
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));
    EXPECT_NE(worktreesJson().find("\"isLocked\":true"), std::string::npos);

    log_.clear();
    gbm_worktree_unlock(session_, extra_.string().c_str());
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));
    EXPECT_NE(worktreesJson().find("\"isLocked\":false"), std::string::npos);
}

TEST_F(WorktreeApiTest, PruneRemovesAdministrativeMetadataForADeletedWorktree) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);
    std::filesystem::remove_all(extra_);

    gbm_worktree_prune(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));

    const std::string json = worktreesJson();
    EXPECT_EQ(json.find("feature"), std::string::npos) << json;
}

}  // namespace
}  // namespace gbm::capi
