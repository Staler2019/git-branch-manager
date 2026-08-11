// Integration test for gbm_branch_create/_rename/_delete against a real
// repo with two commits and a couple of extra local branches.
#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"

#include <algorithm>
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

class BranchApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-branch-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "file.txt") << "v1\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "First commit"}), 0);

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

    std::vector<std::string> localBranches() {
        const std::string outFile = (repo_ / "..gbm_branch_test_list.txt").string();
        std::string command =
            "git -C \"" + repo_.string() + "\" branch --format='%(refname:short)' > \"" + outFile + "\"";
        [[maybe_unused]] const int rc = std::system(command.c_str());
        std::ifstream in(outFile);
        std::vector<std::string> names;
        std::string line;
        while (std::getline(in, line)) {
            if (!line.empty()) names.push_back(line);
        }
        return names;
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

TEST_F(BranchApiTest, CreateBranchAddsALocalBranchWithoutMovingHead) {
    gbm_branch_create(session_, "feature-1", "", /*checkoutAfter=*/0, /*setUpstream=*/0, "");
    ASSERT_TRUE(waitForOperationFinished());

    const auto branches = localBranches();
    EXPECT_NE(std::find(branches.begin(), branches.end(), "feature-1"), branches.end());

    const std::string outFile = (repo_ / "..gbm_branch_test_head.txt").string();
    std::string command = "git -C \"" + repo_.string() + "\" symbolic-ref --short HEAD > \"" + outFile + "\"";
    [[maybe_unused]] const int rc = std::system(command.c_str());
    std::ifstream in(outFile);
    std::string head;
    std::getline(in, head);
    EXPECT_EQ(head, "main");
}

TEST_F(BranchApiTest, CreateBranchWithCheckoutAfterMovesHead) {
    gbm_branch_create(session_, "feature-2", "", /*checkoutAfter=*/1, /*setUpstream=*/0, "");
    ASSERT_TRUE(waitForOperationFinished());

    const std::string outFile = (repo_ / "..gbm_branch_test_head2.txt").string();
    std::string command = "git -C \"" + repo_.string() + "\" symbolic-ref --short HEAD > \"" + outFile + "\"";
    [[maybe_unused]] const int rc = std::system(command.c_str());
    std::ifstream in(outFile);
    std::string head;
    std::getline(in, head);
    EXPECT_EQ(head, "feature-2");
}

TEST_F(BranchApiTest, RenameBranchChangesTheLocalBranchName) {
    ASSERT_EQ(runGit({"branch", "old-name"}), 0);

    gbm_branch_rename(session_, "old-name", "new-name", /*force=*/0);
    ASSERT_TRUE(waitForOperationFinished());

    const auto branches = localBranches();
    EXPECT_EQ(std::find(branches.begin(), branches.end(), "old-name"), branches.end());
    EXPECT_NE(std::find(branches.begin(), branches.end(), "new-name"), branches.end());
}

TEST_F(BranchApiTest, DeleteBranchRemovesASingleLocalBranch) {
    ASSERT_EQ(runGit({"branch", "to-delete"}), 0);

    const char* names[] = {"to-delete"};
    gbm_branch_delete(session_, names, 1, /*force=*/0, /*isRemote=*/0, "");
    ASSERT_TRUE(waitForOperationFinished());

    const auto branches = localBranches();
    EXPECT_EQ(std::find(branches.begin(), branches.end(), "to-delete"), branches.end());
}

TEST_F(BranchApiTest, DeleteBranchAcceptsMultipleNamesInOneCall) {
    ASSERT_EQ(runGit({"branch", "multi-1"}), 0);
    ASSERT_EQ(runGit({"branch", "multi-2"}), 0);

    const char* names[] = {"multi-1", "multi-2"};
    gbm_branch_delete(session_, names, 2, /*force=*/0, /*isRemote=*/0, "");
    ASSERT_TRUE(waitForOperationFinished());

    const auto branches = localBranches();
    EXPECT_EQ(std::find(branches.begin(), branches.end(), "multi-1"), branches.end());
    EXPECT_EQ(std::find(branches.begin(), branches.end(), "multi-2"), branches.end());
}

}  // namespace
}  // namespace gbm::capi
