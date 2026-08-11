// Integration tests for the M5 remote slice of the extern "C" surface
// (gbm_capi.h): fetch/pull/push against a local bare repository reached
// over the plain filesystem transport, which needs no credentials -- git
// never invokes askpass for it, so these stay fully offline.
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

bool waitForWorkingCopyOperationFinished(EventLog& log) {
    return log.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    });
}

class RemoteApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-remote-" + std::string(info->name()));
        remote_ = std::filesystem::temp_directory_path() / ("gbm-capi-remote-bare-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::remove_all(remote_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runIn(remote_.parent_path(), {"init", "--quiet", "--bare", remote_.string()}), 0);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);
        ASSERT_EQ(runGit({"remote", "add", "origin", remote_.string()}), 0);

        std::ofstream(repo_ / "file.txt") << "content\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Initial commit"}), 0);
        ASSERT_EQ(runGit({"push", "--quiet", "-u", "origin", "main"}), 0);

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
        std::filesystem::remove_all(remote_, ec);
    }

    int runGit(std::vector<std::string> args) { return runIn(repo_, std::move(args)); }

    int runIn(const std::filesystem::path& dir, std::vector<std::string> args) {
        std::string command = "git -C \"" + dir.string() + "\"";
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

    std::string remotesJson() {
        [[maybe_unused]] const int32_t rc = gbm_remotes_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    std::filesystem::path repo_;
    std::filesystem::path remote_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(RemoteApiTest, RefreshReportsTheConfiguredRemote) {
    gbm_remote_refresh(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_REMOTES_UPDATED); }));

    const std::string json = remotesJson();
    EXPECT_NE(json.find("\"name\":\"origin\""), std::string::npos) << json;
}

TEST_F(RemoteApiTest, FetchBringsInNewRemoteCommits) {
    // A second clone pushes a commit that repo_ has not seen yet.
    const std::filesystem::path other = repo_.parent_path() / (repo_.filename().string() + "-other");
    std::error_code ec;
    std::filesystem::remove_all(other, ec);
    ASSERT_EQ(runIn(other.parent_path(), {"clone", "--quiet", remote_.string(), other.string()}), 0);
    // The bare remote's default branch (its HEAD symref, fixed at `git init
    // --bare` time) is whatever init.defaultBranch says, not necessarily
    // "main" -- only pushing to it makes "main" exist there. A clone
    // therefore checks out that default branch, which may not be "main"
    // even though `main` exists as a remote-tracking branch; check it out
    // explicitly so the commit below lands on the branch this test expects.
    ASSERT_EQ(runIn(other, {"checkout", "--quiet", "main"}), 0);
    ASSERT_EQ(runIn(other, {"config", "user.email", "test@example.invalid"}), 0);
    ASSERT_EQ(runIn(other, {"config", "user.name", "Test"}), 0);
    ASSERT_EQ(runIn(other, {"config", "commit.gpgsign", "false"}), 0);
    std::ofstream(other / "from-other.txt") << "content\n";
    ASSERT_EQ(runIn(other, {"add", "from-other.txt"}), 0);
    ASSERT_EQ(runIn(other, {"commit", "--quiet", "-m", "From the other clone"}), 0);
    ASSERT_EQ(runIn(other, {"push", "--quiet", "origin", "main"}), 0);
    std::filesystem::remove_all(other, ec);

    gbm_remote_fetch(session_, "origin", /*prune=*/0, /*tags=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    // The remote-tracking ref now has the file the other clone pushed...
    EXPECT_EQ(runGit({"cat-file", "-e", "origin/main:from-other.txt"}), 0);
    // ...but a fetch never touches the work tree or local main.
    EXPECT_FALSE(std::filesystem::exists(repo_ / "from-other.txt"));
}

TEST_F(RemoteApiTest, PullMergesRemoteCommitsIntoTheCurrentBranch) {
    const std::filesystem::path other = repo_.parent_path() / (repo_.filename().string() + "-other");
    std::error_code ec;
    std::filesystem::remove_all(other, ec);
    ASSERT_EQ(runIn(other.parent_path(), {"clone", "--quiet", remote_.string(), other.string()}), 0);
    // The bare remote's default branch (its HEAD symref, fixed at `git init
    // --bare` time) is whatever init.defaultBranch says, not necessarily
    // "main" -- only pushing to it makes "main" exist there. A clone
    // therefore checks out that default branch, which may not be "main"
    // even though `main` exists as a remote-tracking branch; check it out
    // explicitly so the commit below lands on the branch this test expects.
    ASSERT_EQ(runIn(other, {"checkout", "--quiet", "main"}), 0);
    ASSERT_EQ(runIn(other, {"config", "user.email", "test@example.invalid"}), 0);
    ASSERT_EQ(runIn(other, {"config", "user.name", "Test"}), 0);
    ASSERT_EQ(runIn(other, {"config", "commit.gpgsign", "false"}), 0);
    std::ofstream(other / "from-other.txt") << "content\n";
    ASSERT_EQ(runIn(other, {"add", "from-other.txt"}), 0);
    ASSERT_EQ(runIn(other, {"commit", "--quiet", "-m", "From the other clone"}), 0);
    ASSERT_EQ(runIn(other, {"push", "--quiet", "origin", "main"}), 0);
    std::filesystem::remove_all(other, ec);

    gbm_pull(session_, "origin", "main", /*rebase=*/0, /*stashFirst=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    EXPECT_TRUE(std::filesystem::exists(repo_ / "from-other.txt"));
}

TEST_F(RemoteApiTest, PushUploadsLocalCommitsToTheRemote) {
    std::ofstream(repo_ / "new-file.txt") << "content\n";
    ASSERT_EQ(runGit({"add", "new-file.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "New commit"}), 0);

    gbm_push(session_, "origin", "main", /*setUpstream=*/0, /*pushTags=*/0, /*forceWithLease=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    // Named explicitly, not bare HEAD: the bare remote's HEAD symref is
    // whatever init.defaultBranch says (fixed at `git init --bare` time),
    // not necessarily "main" -- see the FetchBringsInNewRemoteCommits doc
    // comment above for the same distinction.
    EXPECT_EQ(runIn(remote_, {"cat-file", "-e", "refs/heads/main:new-file.txt"}), 0);
}

}  // namespace
}  // namespace gbm::capi
