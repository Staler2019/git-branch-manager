// Integration tests for the M2 working-copy/diff/commit slice of the
// extern "C" surface (gbm_capi.h), against a real repository with
// uncommitted changes -- the working-copy analog of SessionApiTest.cpp.
#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"

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

    /// Every payload seen for `type`, in arrival order.
    std::vector<std::string> payloadsOfType(int32_t type) {
        std::lock_guard<std::mutex> lock(mutex);
        std::vector<std::string> out;
        for (const auto& [eventType, payload] : events) {
            if (eventType == type) out.push_back(payload);
        }
        return out;
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

class WorkingCopyApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-wc-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "committed.txt") << "line1\n";
        ASSERT_EQ(runGit({"add", "committed.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Initial commit"}), 0);

        // Uncommitted state the tests exercise: a modified tracked file plus
        // a new untracked one, so status() has both a staged-candidate and
        // an untracked entry from the very first refresh.
        std::ofstream(repo_ / "committed.txt") << "line1\nline2\n";
        std::ofstream(repo_ / "untracked.txt") << "new file\n";

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

    int runGit(std::vector<std::string> args) {
        std::string command = "git -C \"" + repo_.string() + "\"";
        for (const auto& arg : args) {
            command += " \"" + arg + "\"";
        }
        command += " >/dev/null 2>&1";
        return std::system(command.c_str());
    }

    std::string statusJson() {
        [[maybe_unused]] const int32_t rc = gbm_working_copy_status_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(WorkingCopyApiTest, RefreshReportsModifiedAndUntrackedFiles) {
    gbm_working_copy_refresh(session_);
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) { return !events.empty() && events.back().first == GBM_EVENT_WORKING_COPY_STATUS_UPDATED; }));

    const std::string json = statusJson();
    EXPECT_NE(json.find("\"path\":\"committed.txt\""), std::string::npos) << json;
    EXPECT_NE(json.find("\"path\":\"untracked.txt\""), std::string::npos) << json;
    EXPECT_NE(json.find("\"untracked\":true"), std::string::npos) << json;
}

TEST_F(WorkingCopyApiTest, WorkingCopyDiffReportsAddedLine) {
    gbm_working_copy_diff(session_, "committed.txt", /*staged=*/0);

    ASSERT_TRUE(log_.waitFor([](const auto& events) { return !events.empty(); }));
    const std::vector<std::string> diffs = log_.payloadsOfType(GBM_EVENT_WORKING_COPY_DIFF_READY);
    ASSERT_EQ(diffs.size(), 1u);
    EXPECT_NE(diffs[0].find("\"path\":\"committed.txt\""), std::string::npos) << diffs[0];
    EXPECT_NE(diffs[0].find("\"staged\":false"), std::string::npos) << diffs[0];
    EXPECT_NE(diffs[0].find("\"text\":\"line2\""), std::string::npos) << diffs[0];
}

TEST_F(WorkingCopyApiTest, StageFilesMovesFileIntoStagedState) {
    const char* paths[] = {"committed.txt"};
    gbm_stage_files(session_, paths, 1);

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    }));
    // stageFiles() chains a refresh on success -- wait for that too before
    // reading status.
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_STATUS_UPDATED) return true;
        }
        return false;
    }));

    const std::string json = statusJson();
    EXPECT_NE(json.find("\"path\":\"committed.txt\""), std::string::npos) << json;
    EXPECT_NE(json.find("\"staged\":true"), std::string::npos) << json;
}

TEST_F(WorkingCopyApiTest, CommitChangesCreatesCommitAndRefreshesGraph) {
    const char* paths[] = {"committed.txt"};
    gbm_stage_files(session_, paths, 1);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    }));

    gbm_commit_changes(session_, "Second commit", /*amend=*/0, /*signOff=*/0);

    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) {
            int32_t operationFinishedCount = 0;
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) ++operationFinishedCount;
            }
            return operationFinishedCount >= 2;  // stage + commit
        },
        std::chrono::seconds(10)));

    // commitChanges() chains both a working-copy refresh and a history
    // refresh on success -- the new commit should show up in the graph.
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) {
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_GRAPH_UPDATED && payload.find("\"complete\":true") != std::string::npos) {
                    return true;
                }
            }
            return false;
        },
        std::chrono::seconds(10)));

    int32_t rowCount = -1;
    int32_t rowStride = -1;
    const uint8_t* rows = gbm_graph_snapshot_rows(session_, &rowCount, &rowStride);
    EXPECT_NE(rows, nullptr);
    EXPECT_EQ(rowCount, 2);  // initial commit + the new one
    gbm_graph_snapshot_release(session_);
}

}  // namespace
}  // namespace gbm::capi
