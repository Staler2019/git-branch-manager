// Integration tests for the M4 cherry-pick + revert slice of the extern "C"
// surface (gbm_capi.h).
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

class CherryPickRevertApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-cpr-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "base.txt") << "base\n";
        ASSERT_EQ(runGit({"add", "base.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Base commit"}), 0);
        baseCommit_ = commitHex("main");

        ASSERT_EQ(runGit({"checkout", "--quiet", "-b", "feature"}), 0);
        std::ofstream(repo_ / "picked.txt") << "picked\n";
        ASSERT_EQ(runGit({"add", "picked.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Commit to cherry-pick"}), 0);
        pickedCommit_ = commitHex("feature");
        ASSERT_EQ(runGit({"checkout", "--quiet", "main"}), 0);

        // A commit unique to main, so cherry-picking feature's commit is not
        // fast-forward-eligible (main's tip must not equal the picked
        // commit's parent): git's cherry-pick special-cases that situation
        // into a bare ref move instead of actually replaying the commit --
        // see git-cherry-pick(1) -- which would make rowCount below
        // (and which commit ends up as HEAD) depend on that internal
        // optimization rather than on gbm_cherry_pick() actually working.
        std::ofstream(repo_ / "main-only.txt") << "main\n";
        ASSERT_EQ(runGit({"add", "main-only.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Commit unique to main"}), 0);

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

    std::string commitHex(const std::string& revision) {
        const std::string outFile = (repo_ / "..gbm_rev.txt").string();
        std::string command = "git -C \"" + repo_.string() + "\" rev-parse " + revision + " > \"" + outFile + "\"";
        [[maybe_unused]] const int rc = std::system(command.c_str());
        std::ifstream in(outFile);
        std::string line;
        std::getline(in, line);
        return line;
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
    std::string pickedCommit_;
    std::string baseCommit_;
};

TEST_F(CherryPickRevertApiTest, CherryPickAppliesCommitOntoCurrentBranch) {
    const char* commits[] = {pickedCommit_.c_str()};
    gbm_cherry_pick(session_, commits, 1, /*mainline=*/0, /*noCommit=*/0, /*stashFirst=*/0);
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    EXPECT_TRUE(std::filesystem::exists(repo_ / "picked.txt"));

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_GRAPH_UPDATED && payload.find("\"complete\":true") != std::string::npos) return true;
        }
        return false;
    }));
    int32_t rowCount = -1;
    int32_t rowStride = -1;
    gbm_graph_snapshot_rows(session_, &rowCount, &rowStride);
    // base + main-only commit + feature's own original commit (still
    // reachable through the still-existing "feature" branch -- the walk
    // always adds --all, see HistoryQuery::toRevListArgs()) + main's newly
    // cherry-picked replay.
    EXPECT_EQ(rowCount, 4);
    gbm_graph_snapshot_release(session_);
}

TEST_F(CherryPickRevertApiTest, RevertCreatesInverseCommit) {
    // Revert the base commit itself -- removes base.txt. baseCommit_ (not
    // commitHex("main")) since main's tip is now the later "main-only.txt"
    // commit added in SetUp() to keep the cherry-pick test's fixture out of
    // git's fast-forward-eligible case -- see SetUp()'s doc comment above.
    const char* commits[] = {baseCommit_.c_str()};
    gbm_revert(session_, commits, 1, /*noCommit=*/0, /*stashFirst=*/0);
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    EXPECT_FALSE(std::filesystem::exists(repo_ / "base.txt"));
}

}  // namespace
}  // namespace gbm::capi
