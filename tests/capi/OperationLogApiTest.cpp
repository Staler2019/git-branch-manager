// Integration test for the M5 operation-log slice of the extern "C" surface
// (gbm_capi.h): every `git` invocation a session makes should surface as a
// GBM_EVENT_OPERATION_LOG_RECORD, for an operation-log panel -- see
// core/base/Logging.h's OperationRecord doc comment and
// Session::dispatchOperationLogRecord()'s doc comment for how the
// process-wide gbm::Log sink gets routed back to the right session.
#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"
#include "support/GitCli.h"

#include <algorithm>
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

// Windows paths contain backslashes, which JSON escapes as `\\` -- searching
// the raw path.string() as a substring of serialized JSON never matches
// there, even though the same code is correct on POSIX where paths use `/`.
std::string jsonNeedle(const std::filesystem::path& path) {
    std::string escaped;
    for (char c : path.string()) {
        if (c == '\\') escaped += '\\';
        escaped += c;
    }
    return escaped;
}

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

    std::vector<std::string> payloadsOfType(int32_t type) {
        std::lock_guard<std::mutex> lock(mutex);
        std::vector<std::string> out;
        for (const auto& [eventType, payload] : events) {
            if (eventType == type) out.push_back(payload);
        }
        return out;
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

class OperationLogApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-oplog-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
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
        return GitCli::run(repo_, std::move(args));
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(OperationLogApiTest, HistoryRefreshEmitsOperationLogRecordsForItsGitInvocations) {
    gbm_history_refresh(session_);

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_GRAPH_UPDATED && payload.find("\"complete\":true") != std::string::npos) return true;
        }
        return false;
    }));

    const std::vector<std::string> records = log_.payloadsOfType(GBM_EVENT_OPERATION_LOG_RECORD);
    ASSERT_FALSE(records.empty());
    // The repoDir in every record should be this session's own work tree --
    // dispatchOperationLogRecord() must not leak another session's records.
    for (const std::string& record : records) {
        EXPECT_NE(record.find("\"repoDir\":\"" + jsonNeedle(repo_) + "\""), std::string::npos) << record;
        EXPECT_NE(record.find("\"argv\":["), std::string::npos) << record;
        EXPECT_NE(record.find("\"commandLine\":"), std::string::npos) << record;
    }
    // At least one of them should be the `git` invocation that reads refs.
    const bool sawGitInvocation = std::any_of(records.begin(), records.end(), [](const std::string& record) {
        return record.find("\"argv\":[\"") != std::string::npos;
    });
    EXPECT_TRUE(sawGitInvocation);
}

}  // namespace
}  // namespace gbm::capi
