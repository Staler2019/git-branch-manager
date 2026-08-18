// Integration tests against the public extern "C" surface (gbm_capi.h) and a
// real, tiny git repository -- the capi analog of unit/GitIntegrationTest.cpp.
// Exercises the same path Dart's FFI bindings will: open a session, refresh
// history asynchronously, read the packed graph buffer, and check out a
// branch, all through the C ABI rather than the C++ classes directly.
#include "capi/Session.h"
#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"
#include "core/graph/GraphSnapshot.h"

#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
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

    /// Waits until a predicate over the accumulated events is true, or fails
    /// the current test on timeout.
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

bool anyEventOfType(const std::vector<std::pair<int32_t, std::string>>& events, int32_t type) {
    for (const auto& [eventType, payload] : events) {
        if (eventType == type) return true;
    }
    return false;
}

class CapiSessionTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "file.txt") << "hello\n";
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
    }

    /// Shells out to the real `git` binary directly (not through gbm_capi) to
    /// build the fixture repository -- mirrors GitIntegrationTest's `run()`.
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

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(CapiSessionTest, RepoStateJsonReportsCleanRepository) {
    ASSERT_EQ(gbm_repo_state_json(session_), 0);
    std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));

    EXPECT_NE(json.find("\"isClean\":true"), std::string::npos);
}

TEST_F(CapiSessionTest, HistoryRefreshPublishesACompleteGraphSnapshot) {
    gbm_history_refresh(session_);

    const bool arrived = log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_GRAPH_UPDATED && payload.find("\"complete\":true") != std::string::npos) {
                return true;
            }
        }
        return false;
    });
    ASSERT_TRUE(arrived) << "timed out waiting for a complete GRAPH_UPDATED event";

    {
        std::lock_guard<std::mutex> lock(log_.mutex);
        EXPECT_TRUE(anyEventOfType(log_.events, GBM_EVENT_REFS_UPDATED));
    }

    ASSERT_EQ(gbm_refs_json(session_), 0);
    std::string refsJson(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(refsJson.data()), static_cast<int32_t>(refsJson.size()));
    EXPECT_NE(refsJson.find("\"branchName\":\"main\""), std::string::npos) << refsJson;
    EXPECT_NE(refsJson.find("\"shortName\":\"main\""), std::string::npos) << refsJson;

    int32_t rowCount = -1;
    int32_t rowStride = -1;
    const uint8_t* rows = gbm_graph_snapshot_rows(session_, &rowCount, &rowStride);
    EXPECT_EQ(rowStride, static_cast<int32_t>(sizeof(RowMeta)));
    ASSERT_EQ(rowCount, 1);  // One commit in the fixture repo.
    ASSERT_NE(rows, nullptr);

    RowMeta row;
    std::memcpy(&row, rows, sizeof(RowMeta));
    EXPECT_EQ(row.parentCount(), 0);

    gbm_graph_snapshot_release(session_);
}

TEST_F(CapiSessionTest, CheckoutCreatesAndSwitchesToNewBranch) {
    // target is the start point for the new branch when createBranch is set
    // (see CheckoutOp.cpp: "switch --create <newBranchName> [<target>]"), not
    // the new branch's own name -- empty means "start from HEAD".
    gbm_branch_checkout(session_, "", 0, 1, "feature", 0, 0, 0);

    const bool finished = log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_OPERATION_FINISHED) return true;
        }
        return false;
    });
    ASSERT_TRUE(finished) << "timed out waiting for OPERATION_FINISHED";

    std::string outcomeJson;
    {
        std::lock_guard<std::mutex> lock(log_.mutex);
        for (const auto& [type, payload] : log_.events) {
            if (type == GBM_EVENT_OPERATION_FINISHED) outcomeJson = payload;
        }
    }
    EXPECT_NE(outcomeJson.find("\"succeeded\":true"), std::string::npos) << outcomeJson;
    // Lets Dart's PendingOperationTracker attribute this outcome to the
    // checkout() call that produced it, rather than the next
    // operationFinished event to arrive on the shared submitOperation channel.
    EXPECT_NE(outcomeJson.find("\"kind\":\"checkout\""), std::string::npos) << outcomeJson;

    std::ifstream headFile(repo_ / ".git" / "HEAD");
    std::string head((std::istreambuf_iterator<char>(headFile)), std::istreambuf_iterator<char>());
    EXPECT_NE(head.find("refs/heads/feature"), std::string::npos);

    // A successful checkout also triggers a refresh -- see Session::checkout.
    EXPECT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_REFS_UPDATED); }));
}

// --- sharedGitInstallation() / GBM_GIT_PATH ---------------------------------
//
// Not a CapiSessionTest: these exercise sharedGitInstallation() itself, not a
// Session opened against a real repository, and each one restores the process
// environment and the cache before returning so it cannot leak state into
// whichever test runs next in this binary.
#ifndef _WIN32
TEST(SharedGitInstallation, HonorsGbmGitPathOverride) {
    auto detected = GitExecutable::detect();
    if (!detected) {
        GTEST_SKIP() << "no usable git found: " << detected.error().message;
    }

    ::setenv("GBM_GIT_PATH", detected->executable.c_str(), 1);
    resetSharedGitInstallationForTest();
    auto result = sharedGitInstallation();
    ::unsetenv("GBM_GIT_PATH");
    resetSharedGitInstallationForTest();

    ASSERT_TRUE(result) << result.error().message;
    EXPECT_EQ(result->executable, detected->executable);
}

TEST(SharedGitInstallation, RetriesInsteadOfPermanentlyCachingAFailure) {
    resetSharedGitInstallationForTest();
    ::setenv("GBM_GIT_PATH", "/definitely/not/a/git/binary", 1);
    auto first = sharedGitInstallation();
    ASSERT_FALSE(first);

    auto detected = GitExecutable::detect();
    if (!detected) {
        ::unsetenv("GBM_GIT_PATH");
        GTEST_SKIP() << "no usable git found: " << detected.error().message;
    }

    // Fixed the override and call again *without* an explicit reset: with the
    // old always-cache-the-result behaviour, `resolved` would already be true
    // from the failed first call and this would still return that stale
    // failure instead of re-detecting.
    ::setenv("GBM_GIT_PATH", detected->executable.c_str(), 1);
    auto second = sharedGitInstallation();
    ::unsetenv("GBM_GIT_PATH");
    resetSharedGitInstallationForTest();

    ASSERT_TRUE(second) << second.error().message;
    EXPECT_EQ(second->executable, detected->executable);
}
#endif

}  // namespace
}  // namespace gbm::capi
