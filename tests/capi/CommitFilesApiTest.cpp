// Integration tests for the commit-files slice of the extern "C" surface
// (gbm_capi.h): gbm_request_commit_files()/GBM_EVENT_COMMIT_FILES_READY and
// gbm_request_commit_file_diff()/GBM_EVENT_COMMIT_FILE_DIFF_READY.
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

class CommitFilesApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        // GitCli detects git once per test binary and caches it; this used to
        // be a GitExecutable::detect() per suite, i.e. one `git --version`
        // process each -- 29 of them across this binary.
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-commitfiles-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "file.txt") << "one\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "first commit"}), 0);
        headOid_ = revParseHead();
        ASSERT_FALSE(headOid_.empty());

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

    std::string revParseHead() {
        // The redirect this replaces wrote head-oid.txt *inside* the
        // repository under test, leaving an untracked file behind for every
        // later status read to trip over.
        const auto result = GitCli::capture(repo_, {"rev-parse", "HEAD"});
        return result.exitCode == 0 ? result.firstLine() : std::string();
    }

    std::filesystem::path repo_;
    std::string headOid_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(CommitFilesApiTest, RequestCommitFilesReturnsAddedFile) {
    gbm_request_commit_files(session_, headOid_.c_str());

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_COMMIT_FILES_READY) return true;
        }
        return false;
    }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_COMMIT_FILES_READY);
    EXPECT_NE(payload.find("\"oid\":\"" + headOid_ + "\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"files\":["), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"path\":\"file.txt\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"kind\":1"), std::string::npos) << payload;  // FileChangeKind::Added = 1

    // Spec page 02 item 10's badge reads these two. file.txt is one line, so
    // an added file is +1/-0; a JSON writer that emitted the pair in the
    // wrong order would produce 0/1 and fail here.
    EXPECT_NE(payload.find("\"addedLines\":1"), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"removedLines\":0"), std::string::npos) << payload;
}

TEST_F(CommitFilesApiTest, RequestCommitFilesReportsAsymmetricLineCounts) {
    // The +1/-0 above cannot tell a real count from a constant, and its two
    // numbers are 1 and 0 -- which also appear in this payload as "kind" and
    // "similarity". A second commit with counts that are non-zero, unequal,
    // and not otherwise present in the JSON is what makes the assertion mean
    // "the numstat join survived the capi boundary".
    std::ofstream(repo_ / "file.txt", std::ios::trunc) << "a\nb\nc\nd\n";
    ASSERT_EQ(runGit({"add", "file.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "rewrite file"}), 0);
    const std::string oid = revParseHead();
    ASSERT_FALSE(oid.empty());

    gbm_request_commit_files(session_, oid.c_str());

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_COMMIT_FILES_READY) return true;
        }
        return false;
    }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_COMMIT_FILES_READY);
    EXPECT_NE(payload.find("\"path\":\"file.txt\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"addedLines\":4"), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"removedLines\":1"), std::string::npos) << payload;
}

TEST_F(CommitFilesApiTest, RequestCommitFileDiffReturnsFileDiff) {
    gbm_request_commit_file_diff(session_, headOid_.c_str(), "file.txt");

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_COMMIT_FILE_DIFF_READY) return true;
        }
        return false;
    }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_COMMIT_FILE_DIFF_READY);
    EXPECT_NE(payload.find("\"oid\":\"" + headOid_ + "\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"path\":\"file.txt\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"diff\":{"), std::string::npos) << payload;
}

TEST_F(CommitFilesApiTest, UnknownOidEmitsError) {
    const std::string missing(40, 'e');
    gbm_request_commit_files(session_, missing.c_str());

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_ERROR_OCCURRED) return true;
        }
        return false;
    }));

    EXPECT_TRUE(log_.lastPayloadOfType(GBM_EVENT_COMMIT_FILES_READY).empty());
    EXPECT_FALSE(log_.lastPayloadOfType(GBM_EVENT_ERROR_OCCURRED).empty());
}

}  // namespace
}  // namespace gbm::capi
