// Integration tests for the M6 commit 8 slice of the extern "C" surface
// (gbm_capi.h): gbm_request_original_operation_message()/
// GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY, and the write side --
// gbm_cherry_pick_continue_with_message()/gbm_rebase_continue_with_message().
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

bool waitForOperationFinished(EventLog& log) {
    return log.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_OPERATION_FINISHED) return true;
        }
        return false;
    });
}

// Both branches edit the same file so cherry-pick/rebase produce a genuine
// conflict, matching the fixture used to empirically probe git's own
// MERGE_MSG/rebase-merge/message behavior during M6 commit 7's design.
class OriginalOperationMessageApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-oom-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "f.txt") << "line1\n";
        ASSERT_EQ(runGit({"add", "f.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "base commit"}), 0);

        ASSERT_EQ(runGit({"checkout", "--quiet", "-b", "branchA"}), 0);
        std::ofstream(repo_ / "f.txt", std::ios::trunc) << "A change\n";
        ASSERT_EQ(runGit({"commit", "--quiet", "-am", "A changes f.txt"}), 0);
        branchACommit_ = commitHex("branchA");

        ASSERT_EQ(runGit({"checkout", "--quiet", "main"}), 0);
        std::ofstream(repo_ / "f.txt", std::ios::trunc) << "main change\n";
        ASSERT_EQ(runGit({"commit", "--quiet", "-am", "main changes f.txt"}), 0);

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

    std::string commitHex(const std::string& revision) {
        const std::string outFile = (repo_ / "..gbm_rev.txt").string();
        std::string command = "git -C \"" + repo_.string() + "\" rev-parse " + revision + " > \"" + outFile + "\"";
        [[maybe_unused]] const int rc = std::system(command.c_str());
        std::ifstream in(outFile);
        std::string line;
        std::getline(in, line);
        return line;
    }

    // Trims trailing newlines: `git log --format=%B` appends its own
    // terminator on top of the commit message's own trailing newline, and
    // that formatting detail is not what these tests care about.
    std::string headCommitMessage() {
        const std::string outFile = (repo_ / "..gbm_msg.txt").string();
        std::string command =
            "git -C \"" + repo_.string() + "\" log -1 --format=%B > \"" + outFile + "\"";
        [[maybe_unused]] const int rc = std::system(command.c_str());
        std::ifstream in(outFile);
        std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
        while (!content.empty() && content.back() == '\n') {
            content.pop_back();
        }
        return content;
    }

    void resolveConflictOnDisk() {
        std::ofstream(repo_ / "f.txt", std::ios::trunc) << "resolved\n";
        ASSERT_EQ(runGit({"add", "f.txt"}), 0);
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
    std::string branchACommit_;
};

TEST_F(OriginalOperationMessageApiTest, RequestReturnsGitsProposedMessageDuringConflictedCherryPick) {
    const char* commits[] = {branchACommit_.c_str()};
    gbm_cherry_pick(session_, commits, 1, /*mainline=*/0, /*noCommit=*/0, /*stashFirst=*/0);
    ASSERT_TRUE(waitForOperationFinished(log_));

    gbm_request_original_operation_message(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY) return true;
        }
        return false;
    }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY);
    EXPECT_NE(payload.find("A changes f.txt"), std::string::npos) << payload;
    EXPECT_NE(payload.find("# Conflicts:"), std::string::npos) << payload;

    runGit({"cherry-pick", "--abort"});
}

TEST_F(OriginalOperationMessageApiTest, CherryPickContinueWithMessageUsesTheEditedMessage) {
    const char* commits[] = {branchACommit_.c_str()};
    gbm_cherry_pick(session_, commits, 1, /*mainline=*/0, /*noCommit=*/0, /*stashFirst=*/0);
    ASSERT_TRUE(waitForOperationFinished(log_));

    resolveConflictOnDisk();
    gbm_cherry_pick_continue_with_message(session_, "Custom cherry-pick message");
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        int count = 0;
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_OPERATION_FINISHED) ++count;
        }
        return count >= 2;
    }));

    EXPECT_EQ(headCommitMessage(), "Custom cherry-pick message");
}

TEST_F(OriginalOperationMessageApiTest, RebaseContinueWithMessageUsesTheEditedMessage) {
    ASSERT_EQ(runGit({"checkout", "--quiet", "branchA"}), 0);

    gbm_rebase_start(session_, "main", "", /*stashFirst=*/0);
    ASSERT_TRUE(waitForOperationFinished(log_));

    resolveConflictOnDisk();
    gbm_rebase_continue_with_message(session_, "Custom rebase message");
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        int count = 0;
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_OPERATION_FINISHED) ++count;
        }
        return count >= 2;
    }));

    EXPECT_EQ(headCommitMessage(), "Custom rebase message");
}

}  // namespace
}  // namespace gbm::capi
