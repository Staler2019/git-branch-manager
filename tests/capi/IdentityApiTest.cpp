// Integration tests for the M8 local/effective Git identity and
// commit-graph maintenance slice of the extern "C" surface (gbm_capi.h).
#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"
#include "support/GitCli.h"

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

class IdentityApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-identity-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "global@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Global User"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);
        std::ofstream(repo_ / "file.txt") << "content\n";
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

    /// Fixture git, without a shell in the middle -- see tests/support/GitCli.h
    /// for why that matters (one process instead of two, and no per-platform
    /// quoting hazard).
    int runGit(std::vector<std::string> args) {
        return ::gbm::testing::GitCli::run(repo_, std::move(args));
    }

    std::string localIdentityJson() {
        [[maybe_unused]] const int32_t rc = gbm_local_identity_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    std::string effectiveIdentityJson() {
        [[maybe_unused]] const int32_t rc = gbm_effective_identity_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(IdentityApiTest, LocalIdentityReadsWhatSetUpConfigured) {
    // SetUp() ran `git config user.email/user.name` with no --global flag,
    // which git resolves to `--local` by default -- so the fixture repo
    // already has a local override, and gbm_local_identity_json() should
    // report it (this exercises the read path, not any capi-side logic
    // about scope precedence -- that is entirely git's own).
    gbm_local_identity_refresh(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_LOCAL_IDENTITY_UPDATED); }));
    const std::string localJson = localIdentityJson();
    EXPECT_NE(localJson.find("\"overridden\":true"), std::string::npos) << localJson;
    EXPECT_NE(localJson.find("\"name\":\"Global User\""), std::string::npos) << localJson;

    gbm_effective_identity_refresh(session_);
    ASSERT_TRUE(
        log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_EFFECTIVE_IDENTITY_UPDATED); }));
    EXPECT_NE(effectiveIdentityJson().find("\"name\":\"Global User\""), std::string::npos);
}

TEST_F(IdentityApiTest, SetThenClearLocalIdentityOverride) {
    gbm_set_local_identity(session_, "Repo Override", "override@example.invalid");
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_LOCAL_IDENTITY_UPDATED); }));

    std::string json = localIdentityJson();
    EXPECT_NE(json.find("\"overridden\":true"), std::string::npos) << json;
    EXPECT_NE(json.find("\"name\":\"Repo Override\""), std::string::npos) << json;

    log_.clear();
    gbm_clear_local_identity(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_LOCAL_IDENTITY_UPDATED); }));

    EXPECT_NE(localIdentityJson().find("\"overridden\":false"), std::string::npos);
}

TEST_F(IdentityApiTest, WriteCommitGraphCreatesAGraphFile) {
    EXPECT_EQ(gbm_has_commit_graph(session_), 0);

    gbm_write_commit_graph(session_);
    ASSERT_TRUE(
        log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_COMMIT_GRAPH_WRITE_FINISHED); }));

    EXPECT_EQ(gbm_has_commit_graph(session_), 1);
}

}  // namespace
}  // namespace gbm::capi
