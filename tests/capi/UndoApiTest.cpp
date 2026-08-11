// Integration tests for the M6 undo slice of the extern "C" surface
// (gbm_capi.h) -- see core/git/ops/UndoOps.h and Session::undoJournal()'s
// doc comment for the thread-safety story behind gbm_undo_journal_json().
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

/// A successful commit/undo chains refreshWorkingCopy() and refreshHistory()
/// (see Session::commitChanges()/undoLastOperation()), both of which post
/// their own `git` subprocess reads to the shared read pool independently of
/// WORKING_COPY_OPERATION_FINISHED -- so that event alone does not mean
/// those reads are done. A raw `git` command run against the same repo
/// right after (as UndoRefusesAfterSwitchingBranches does, simulating
/// something outside this session touching the checkout) can otherwise race
/// one of them for the index/HEAD lock. Waiting for both chained refreshes'
/// own completion signals avoids that.
bool waitForRefreshesToSettle(EventLog& log) {
    return log.waitFor([](const auto& events) {
        bool sawStatus = false;
        bool sawCompleteGraph = false;
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_STATUS_UPDATED) sawStatus = true;
            if (type == GBM_EVENT_GRAPH_UPDATED && payload.find("\"complete\":true") != std::string::npos) {
                sawCompleteGraph = true;
            }
        }
        return sawStatus && sawCompleteGraph;
    });
}

class UndoApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-undo-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "base.txt") << "base\n";
        ASSERT_EQ(runGit({"add", "base.txt"}), 0);
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

    int runGit(std::vector<std::string> args) {
        std::string command = "git -C \"" + repo_.string() + "\"";
        for (const auto& arg : args) {
            command += " \"" + arg + "\"";
        }
        command += " >/dev/null 2>&1";
        return std::system(command.c_str());
    }

    std::string undoJournalJson() {
        [[maybe_unused]] const int32_t rc = gbm_undo_journal_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(UndoApiTest, UndoLastOperationRevertsTheCommit) {
    EXPECT_EQ(undoJournalJson(), "[]");

    std::ofstream(repo_ / "second.txt") << "content\n";
    const char* paths[] = {"second.txt"};
    gbm_stage_files(session_, paths, 1);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));
    log_.clear();

    gbm_commit_changes(session_, "Second commit", /*amend=*/0, /*signOff=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));
    ASSERT_TRUE(waitForRefreshesToSettle(log_));

    const std::string journalAfterCommit = undoJournalJson();
    EXPECT_NE(journalAfterCommit.find("\"branchBefore\":\"main\""), std::string::npos) << journalAfterCommit;
    EXPECT_NE(journalAfterCommit.find("\"id\":"), std::string::npos) << journalAfterCommit;

    log_.clear();
    gbm_undo_last(session_);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));
    ASSERT_TRUE(waitForRefreshesToSettle(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    EXPECT_FALSE(std::filesystem::exists(repo_ / "second.txt"));
    EXPECT_EQ(runGit({"log", "-1", "--format=%s"}), 0);
}

TEST_F(UndoApiTest, UndoRefusesAfterSwitchingBranches) {
    // A commit recorded with branchBefore="main"...
    std::ofstream(repo_ / "second.txt") << "content\n";
    const char* paths[] = {"second.txt"};
    gbm_stage_files(session_, paths, 1);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));
    log_.clear();
    gbm_commit_changes(session_, "Second commit", 0, 0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));
    ASSERT_TRUE(waitForRefreshesToSettle(log_));
    log_.clear();

    // ...but by the time undo runs, something outside this session (a
    // terminal, another tool) has switched the checked-out branch away
    // from "main" -- undo must refuse rather than reset the wrong branch.
    ASSERT_EQ(runGit({"checkout", "--quiet", "-b", "other"}), 0);

    gbm_undo_last(session_);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":false"), std::string::npos) << outcome;
    // The commit must still be there -- undo did not touch anything.
    EXPECT_TRUE(std::filesystem::exists(repo_ / "second.txt"));
}

}  // namespace
}  // namespace gbm::capi
