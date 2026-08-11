// Integration test for the M3 gbm_reset_to() slice against a real repo with
// two commits and uncommitted changes.
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

class ResetApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-reset-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "file.txt") << "v1\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "First commit"}), 0);

        std::ofstream(repo_ / "file.txt") << "v1\nv2\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Second commit"}), 0);

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
#ifdef _WIN32
        command += " >NUL 2>&1";
#else
        command += " >/dev/null 2>&1";
#endif
        return std::system(command.c_str());
    }

    std::string headCommitSubject() {
        const std::string outFile = (repo_ / "..gbm_reset_test_head.txt").string();
        std::string command = "git -C \"" + repo_.string() + "\" log -1 --format=%s > \"" + outFile + "\"";
        [[maybe_unused]] const int rc = std::system(command.c_str());
        std::ifstream in(outFile);
        std::string line;
        std::getline(in, line);
        return line;
    }

    bool waitForOperationFinished() {
        return log_.waitFor([](const auto& events) {
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_OPERATION_FINISHED) return true;
            }
            return false;
        });
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

// ResetMode ordinals: 0 = Soft, 1 = Mixed, 2 = Hard (see ResetOps.h).
TEST_F(ResetApiTest, SoftResetMovesHeadKeepsIndexAndWorkTree) {
    gbm_reset_to(session_, "HEAD~1", /*mode=*/0);
    ASSERT_TRUE(waitForOperationFinished());

    EXPECT_EQ(headCommitSubject(), "First commit");
    // Soft reset leaves the second commit's changes staged.
    const std::string outFile = (repo_ / "..gbm_reset_test_staged.txt").string();
    std::string diffCmd = "git -C \"" + repo_.string() + "\" diff --cached --name-only > \"" + outFile + "\"";
    [[maybe_unused]] const int rc = std::system(diffCmd.c_str());
    std::ifstream in(outFile);
    std::string line;
    std::getline(in, line);
    EXPECT_EQ(line, "file.txt");
}

TEST_F(ResetApiTest, HardResetMovesHeadAndDiscardsWorkTreeChanges) {
    gbm_reset_to(session_, "HEAD~1", /*mode=*/2);
    ASSERT_TRUE(waitForOperationFinished());

    EXPECT_EQ(headCommitSubject(), "First commit");
    std::ifstream file(repo_ / "file.txt");
    std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    EXPECT_EQ(content, "v1\n");

    // Also triggers a history refresh -- the graph should now show 1 commit.
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
    gbm_graph_snapshot_rows(session_, &rowCount, &rowStride);
    EXPECT_EQ(rowCount, 1);
    gbm_graph_snapshot_release(session_);
}

TEST_F(ResetApiTest, RestorePathsStagedUnstagesAFile) {
    ASSERT_EQ(runGit({"add", "file.txt"}), 0);
    std::ofstream(repo_ / "file.txt") << "v1\nv2\nv3\n";
    ASSERT_EQ(runGit({"add", "file.txt"}), 0);

    const char* paths[] = {"file.txt"};
    gbm_restore_paths(session_, paths, 1, /*staged=*/1, "");
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    }));

    const std::string outFile = (repo_ / "..gbm_restore_test_staged.txt").string();
    std::string diffCmd = "git -C \"" + repo_.string() + "\" diff --cached --name-only > \"" + outFile + "\"";
    [[maybe_unused]] const int rc = std::system(diffCmd.c_str());
    std::ifstream in(outFile);
    std::string line;
    std::getline(in, line);
    EXPECT_TRUE(line.empty()) << "expected nothing staged after --staged restore, got: " << line;
}

TEST_F(ResetApiTest, CleanUntrackedRemovesUntrackedFiles) {
    std::ofstream(repo_ / "untracked.txt") << "junk\n";
    ASSERT_TRUE(std::filesystem::exists(repo_ / "untracked.txt"));

    gbm_clean_preview(session_, /*includeIgnored=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_CLEAN_PREVIEW_READY) return true;
        }
        return false;
    }));
    const std::string previewJson = [this]() {
        std::lock_guard<std::mutex> lock(log_.mutex);
        std::string last;
        for (const auto& [type, payload] : log_.events) {
            if (type == GBM_EVENT_CLEAN_PREVIEW_READY) last = payload;
        }
        return last;
    }();
    EXPECT_NE(previewJson.find("untracked.txt"), std::string::npos) << previewJson;

    gbm_clean_untracked(session_, nullptr, 0, /*includeIgnored=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    }));

    EXPECT_FALSE(std::filesystem::exists(repo_ / "untracked.txt"));
}

}  // namespace
}  // namespace gbm::capi
