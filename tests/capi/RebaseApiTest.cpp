// Integration tests for the M7 rebase slice of the extern "C" surface
// (gbm_capi.h).
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

class RebaseApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-rebase-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "base.txt") << "base\n";
        ASSERT_EQ(runGit({"add", "base.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Base commit"}), 0);

        ASSERT_EQ(runGit({"checkout", "--quiet", "-b", "feature"}), 0);
        std::ofstream(repo_ / "feature.txt") << "feature\n";
        ASSERT_EQ(runGit({"add", "feature.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Feature commit"}), 0);

        ASSERT_EQ(runGit({"checkout", "--quiet", "main"}), 0);
        std::ofstream(repo_ / "main-only.txt") << "main\n";
        ASSERT_EQ(runGit({"add", "main-only.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Commit unique to main"}), 0);
        ASSERT_EQ(runGit({"checkout", "--quiet", "feature"}), 0);

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

TEST_F(RebaseApiTest, RequestRebasePlanListsCommitsOldestFirst) {
    gbm_request_rebase_plan(session_, "main");
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) {
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_REBASE_PLAN_READY) return true;
            }
            return false;
        }));

    const std::string json = log_.lastPayloadOfType(GBM_EVENT_REBASE_PLAN_READY);
    EXPECT_NE(json.find("\"subject\":\"Feature commit\""), std::string::npos) << json;
    // Every planned entry defaults to Pick (ordinal 0, see RebaseOps.h).
    EXPECT_NE(json.find("\"action\":0"), std::string::npos) << json;
}

TEST_F(RebaseApiTest, PlainRebaseReplaysFeatureCommitsOntoMain) {
    gbm_rebase_start(session_, "main", "", /*stashFirst=*/0);
    ASSERT_TRUE(waitForOperationFinished());

    // feature no longer contains "Commit unique to main" as an unmerged
    // ancestor of main -- after a successful rebase, main is now an ancestor
    // of feature.
    const std::string command = "git -C \"" + repo_.string() + "\" merge-base --is-ancestor main feature";
    EXPECT_EQ(std::system(command.c_str()), 0);

    std::ifstream file(repo_ / "feature.txt");
    ASSERT_TRUE(file.good());
}

}  // namespace
}  // namespace gbm::capi
