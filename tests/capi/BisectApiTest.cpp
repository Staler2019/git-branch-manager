// Integration tests for the M7 bisect slice of the extern "C" surface
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

    void clear() {
        std::lock_guard<std::mutex> lock(mutex);
        events.clear();
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

class BisectApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-bisect-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "file.txt") << "v1\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Good commit"}), 0);
        goodCommit_ = commitHex("HEAD");

        std::ofstream(repo_ / "file.txt") << "v2\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Middle commit"}), 0);

        std::ofstream(repo_ / "file.txt") << "v3\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Bad commit"}), 0);
        badCommit_ = commitHex("HEAD");

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

    std::string currentBranch() {
        const std::string outFile = (repo_ / "..gbm_branch.txt").string();
        std::string command = "git -C \"" + repo_.string() + "\" symbolic-ref --short -q HEAD > \"" + outFile + "\"";
        [[maybe_unused]] const int rc = std::system(command.c_str());
        std::ifstream in(outFile);
        std::string line;
        std::getline(in, line);
        return line;
    }

    std::string bisectStatusJson() {
        [[maybe_unused]] const int32_t rc = gbm_bisect_status_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
    std::string goodCommit_;
    std::string badCommit_;
};

TEST_F(BisectApiTest, BisectStartActivatesASessionAndRecordsTheBadCommit) {
    const char* goodRefs[] = {goodCommit_.c_str()};
    gbm_bisect_start(session_, badCommit_.c_str(), goodRefs, 1, nullptr, 0, /*noCheckout=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_BISECT_STATUS_UPDATED); }));

    const std::string json = bisectStatusJson();
    EXPECT_NE(json.find("\"active\":true"), std::string::npos) << json;
    EXPECT_NE(json.find("\"badOid\":\"" + badCommit_ + "\""), std::string::npos) << json;
}

TEST_F(BisectApiTest, BisectResetEndsTheSessionAndRestoresTheOriginalBranch) {
    const char* goodRefs[] = {goodCommit_.c_str()};
    gbm_bisect_start(session_, badCommit_.c_str(), goodRefs, 1, nullptr, 0, /*noCheckout=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_BISECT_STATUS_UPDATED); }));
    log_.clear();

    gbm_bisect_reset(session_, "");
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_BISECT_STATUS_UPDATED); }));

    EXPECT_NE(bisectStatusJson().find("\"active\":false"), std::string::npos);
    EXPECT_EQ(currentBranch(), "main");
}

}  // namespace
}  // namespace gbm::capi
