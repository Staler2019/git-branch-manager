// Integration tests for the M6 Compare slice of the extern "C" surface
// (gbm_capi.h): gbm_request_compare_refs()/gbm_request_compare_file_diff()
// against a real local repository. Same EventLog harness as RemoteApiTest.cpp
// -- these are read-only queries, so no bare remote/filesystem transport is
// needed, just two branches in one repo.
#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"

#include <chrono>
#include <condition_variable>
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

class CompareApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-compare-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "shared.txt") << "base\n";
        ASSERT_EQ(runGit({"add", "shared.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Base commit"}), 0);

        ASSERT_EQ(runGit({"branch", "feature"}), 0);
        ASSERT_EQ(runGit({"checkout", "--quiet", "feature"}), 0);
        std::ofstream(repo_ / "shared.txt") << "feature change\n";
        ASSERT_EQ(runGit({"commit", "--quiet", "-a", "-m", "Feature commit"}), 0);

        ASSERT_EQ(runGit({"checkout", "--quiet", "main"}), 0);
        std::ofstream(repo_ / "main-only.txt") << "main change\n";
        ASSERT_EQ(runGit({"add", "main-only.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Main commit"}), 0);

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

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(CompareApiTest, CompareRefsReportsMergeBaseCommitsAndFilesForBothBranches) {
    gbm_request_compare_refs(session_, "main", "feature", /*threeDot=*/1);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_COMPARE_READY); }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_COMPARE_READY);
    EXPECT_NE(payload.find("\"left\":\"main\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"right\":\"feature\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"threeDot\":true"), std::string::npos) << payload;
    // A real merge base was found (both branches share the base commit).
    EXPECT_EQ(payload.find("\"mergeBase\":\"\""), std::string::npos) << payload;
    // Both sides have a commit unique to them: "Main commit" (left-only,
    // reachable from main but not feature) and "Feature commit"
    // (right-only) -- the commits list covers both directions.
    EXPECT_NE(payload.find("Main commit"), std::string::npos) << payload;
    EXPECT_NE(payload.find("Feature commit"), std::string::npos) << payload;
    // The files list, unlike commits, is one-directional by design: `git
    // diff main...feature` (three-dot) diffs the merge-base against
    // feature's tip only, the same semantics GitHub's PR-diff view uses --
    // it shows what feature changed, not what main changed after the
    // branch point. So "shared.txt" (changed on feature) appears here, but
    // "main-only.txt" (added only by "Main commit", which is main's own
    // history, not feature's) correctly does not.
    EXPECT_NE(payload.find("\"newPath\":\"shared.txt\""), std::string::npos) << payload;
    EXPECT_EQ(payload.find("main-only.txt"), std::string::npos) << payload;
}

TEST_F(CompareApiTest, CompareFileDiffReportsTheDiffForOneFile) {
    gbm_request_compare_file_diff(session_, "main", "feature", /*threeDot=*/1, "shared.txt");
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) { return anyEventOfType(events, GBM_EVENT_COMPARE_FILE_DIFF_READY); }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_COMPARE_FILE_DIFF_READY);
    EXPECT_NE(payload.find("\"path\":\"shared.txt\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("feature change"), std::string::npos) << payload;
}

TEST_F(CompareApiTest, CompareRefsReportsAnErrorWhenARefIsEmpty) {
    gbm_request_compare_refs(session_, "main", "", /*threeDot=*/1);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_ERROR_OCCURRED); }));
}

}  // namespace
}  // namespace gbm::capi
