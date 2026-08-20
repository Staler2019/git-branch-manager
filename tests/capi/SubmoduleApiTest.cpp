// Integration tests for the M7 submodule slice of the extern "C" surface
// (gbm_capi.h).
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

using ::gbm::testing::GitCli;

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

class SubmoduleApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-submod-" + std::string(info->name()));
        inner_ = std::filesystem::temp_directory_path() / ("gbm-capi-submod-inner-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::remove_all(inner_);
        std::filesystem::create_directories(repo_);
        std::filesystem::create_directories(inner_);

        // The inner repo that will be added as a submodule.
        ASSERT_EQ(runGitIn(inner_, {"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGitIn(inner_, {"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGitIn(inner_, {"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGitIn(inner_, {"config", "commit.gpgsign", "false"}), 0);
        std::ofstream(inner_ / "lib.txt") << "lib\n";
        ASSERT_EQ(runGitIn(inner_, {"add", "lib.txt"}), 0);
        ASSERT_EQ(runGitIn(inner_, {"commit", "--quiet", "-m", "Inner commit"}), 0);

        // The outer (super)project.
        ASSERT_EQ(runGitIn(repo_, {"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGitIn(repo_, {"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGitIn(repo_, {"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGitIn(repo_, {"config", "commit.gpgsign", "false"}), 0);
        // Git refuses a submodule's clone over the plain `file` transport by
        // default since CVE-2022-39253, and deliberately will not honour a
        // repo-local config override for it (a malicious repository could
        // otherwise just grant itself the permission) -- relax this
        // process-wide for the test binary instead, the same way
        // tests/unit/GitIntegrationTest.cpp's submodule tests do. The app
        // itself never sets this.
#ifdef _WIN32
        _putenv_s("GIT_ALLOW_PROTOCOL", "file:git:http:https:ssh");
#else
        setenv("GIT_ALLOW_PROTOCOL", "file:git:http:https:ssh", 1);
#endif
        std::ofstream(repo_ / "root.txt") << "root\n";
        ASSERT_EQ(runGitIn(repo_, {"add", "root.txt"}), 0);
        ASSERT_EQ(runGitIn(repo_, {"commit", "--quiet", "-m", "Root commit"}), 0);

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
        std::filesystem::remove_all(inner_, ec);
    }

    int runGitIn(const std::filesystem::path& dir, std::vector<std::string> args) {
        return GitCli::run(dir, std::move(args));
    }

    std::string submodulesJson() {
        [[maybe_unused]] const int32_t rc = gbm_submodules_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    std::filesystem::path repo_;
    std::filesystem::path inner_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(SubmoduleApiTest, AddSubmoduleAddsAndListsIt) {
    gbm_submodule_add(session_, inner_.string().c_str(), "sub", "");
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_SUBMODULES_UPDATED); }));

    EXPECT_TRUE(std::filesystem::exists(repo_ / "sub" / "lib.txt"));
    const std::string json = submodulesJson();
    EXPECT_NE(json.find("\"path\":\"sub\""), std::string::npos) << json;
}

TEST_F(SubmoduleApiTest, DeinitSubmoduleEmptiesTheWorkTree) {
    ASSERT_EQ(runGitIn(repo_, {"submodule", "add", "--quiet", inner_.string(), "sub"}), 0);
    ASSERT_TRUE(std::filesystem::exists(repo_ / "sub" / "lib.txt"));
    // `deinit` refuses while the submodule addition itself is still only
    // staged ("local modifications") -- commit it first, matching how a
    // real caller would have to before deinit is even offered.
    ASSERT_EQ(runGitIn(repo_, {"commit", "--quiet", "-m", "Add submodule"}), 0);

    const char* paths[] = {"sub"};
    gbm_submodule_deinit(session_, paths, 1, /*force=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_SUBMODULES_UPDATED); }));

    EXPECT_FALSE(std::filesystem::exists(repo_ / "sub" / "lib.txt"));
}

}  // namespace
}  // namespace gbm::capi
