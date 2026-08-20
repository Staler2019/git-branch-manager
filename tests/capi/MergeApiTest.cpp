// Integration tests for the M4 merge + conflict-resolution slice of the
// extern "C" surface (gbm_capi.h), against a real repository with two
// diverging branches.
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

    std::string lastPayloadOfType(int32_t type) {
        std::lock_guard<std::mutex> lock(mutex);
        std::string last;
        for (const auto& [eventType, payload] : events) {
            if (eventType == type) last = payload;
        }
        return last;
    }

    void clear() {
        std::lock_guard<std::mutex> lock(mutex);
        events.clear();
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

bool waitForOperationFinished(EventLog& log) {
    return log.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_OPERATION_FINISHED) return true;
        }
        return false;
    });
}

class MergeApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-merge-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "shared.txt") << "base\n";
        std::ofstream(repo_ / "only-on-main.txt") << "main\n";
        ASSERT_EQ(runGit({"add", "."}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Base commit"}), 0);

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

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(MergeApiTest, NoFastForwardMergeCreatesMergeCommit) {
    ASSERT_EQ(runGit({"checkout", "--quiet", "-b", "feature"}), 0);
    std::ofstream(repo_ / "feature.txt") << "feature\n";
    ASSERT_EQ(runGit({"add", "feature.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Feature commit"}), 0);
    ASSERT_EQ(runGit({"checkout", "--quiet", "main"}), 0);

    // mode 1 = NoFastForward.
    gbm_merge_branch(session_, "feature", /*mode=*/1, /*message=*/"", /*stashFirst=*/0);
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_GRAPH_UPDATED && payload.find("\"complete\":true") != std::string::npos) return true;
        }
        return false;
    }));
    int32_t rowCount = -1;
    int32_t rowStride = -1;
    gbm_graph_snapshot_rows(session_, &rowCount, &rowStride);
    EXPECT_EQ(rowCount, 3);  // base + feature commit + merge commit
    gbm_graph_snapshot_release(session_);
}

TEST_F(MergeApiTest, ConflictingMergeReportsConflictThenResolveAndCommitFinishes) {
    ASSERT_EQ(runGit({"checkout", "--quiet", "-b", "feature"}), 0);
    std::ofstream(repo_ / "shared.txt") << "feature change\n";
    ASSERT_EQ(runGit({"add", "shared.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Feature edits shared.txt"}), 0);
    ASSERT_EQ(runGit({"checkout", "--quiet", "main"}), 0);
    std::ofstream(repo_ / "shared.txt") << "main change\n";
    ASSERT_EQ(runGit({"add", "shared.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Main edits shared.txt"}), 0);

    gbm_merge_branch(session_, "feature", /*mode=*/1, "", 0);
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":false"), std::string::npos) << outcome;
    EXPECT_NE(outcome.find("\"code\":3"), std::string::npos) << outcome;  // Conflict

    // Working copy is refreshed regardless -- the conflicted path should show up.
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_STATUS_UPDATED) return true;
        }
        return false;
    }));
    ASSERT_EQ(gbm_working_copy_status_json(session_), 0);
    std::string statusJson(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(statusJson.data()), static_cast<int32_t>(statusJson.size()));
    EXPECT_NE(statusJson.find("\"path\":\"shared.txt\""), std::string::npos) << statusJson;
    EXPECT_NE(statusJson.find("\"isConflicted\":true"), std::string::npos) << statusJson;

    log_.clear();

    // Resolution 2 = MarkResolved: stage the current on-disk content as-is.
    gbm_resolve_conflict(session_, "shared.txt", /*resolution=*/2, 0, 0, "");
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    }));

    gbm_commit_changes(session_, "Merge feature into main", /*amend=*/0, /*signOff=*/0);
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) {
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_GRAPH_UPDATED && payload.find("\"complete\":true") != std::string::npos) return true;
            }
            return false;
        },
        std::chrono::seconds(10)));

    ASSERT_EQ(gbm_repo_state_json(session_), 0);
    std::string repoStateJson(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(repoStateJson.data()), static_cast<int32_t>(repoStateJson.size()));
    EXPECT_NE(repoStateJson.find("\"isClean\":true"), std::string::npos) << repoStateJson;
}

}  // namespace
}  // namespace gbm::capi
