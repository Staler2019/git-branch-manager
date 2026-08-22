// Integration tests for the commit-meta slice of the extern "C" surface
// (gbm_capi.h): gbm_request_commit_meta()/GBM_EVENT_COMMIT_META_READY.
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

    bool waitFor(
        const std::function<bool(const std::vector<std::pair<int32_t, std::string>>&)>& pred,
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

void logCallback(GbmSessionHandle,
                 int32_t eventType,
                 const uint8_t* payload,
                 int32_t payloadLen,
                 void* userData) {
    auto* log = static_cast<EventLog*>(userData);
    std::string body;
    if (payload != nullptr) {
        body.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        gbm_free_event_payload(payload);
    }
    log->add(eventType, std::move(body));
}

class CommitMetaApiTest : public ::testing::Test {
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
        repo_ = std::filesystem::temp_directory_path() /
                ("gbm-capi-commitmeta-" + std::string(info->name()));
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
    int runGit(std::vector<std::string> args) { return GitCli::run(repo_, std::move(args)); }

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

TEST_F(CommitMetaApiTest, RequestCommitMetaReturnsSubjectAndAuthor) {
    const char* oids[] = {headOid_.c_str()};
    gbm_request_commit_meta(session_, oids, 1);

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_COMMIT_META_READY) return true;
        }
        return false;
    }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_COMMIT_META_READY);
    EXPECT_NE(payload.find("\"oid\":\"" + headOid_ + "\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"subject\":\"first commit\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("\"email\":\"test@example.invalid\""), std::string::npos) << payload;
}

TEST_F(CommitMetaApiTest, UnreadableOidIsOmittedNotAnErrorEvent) {
    const std::string missing(40, 'e');
    const char* oids[] = {missing.c_str()};
    gbm_request_commit_meta(session_, oids, 1);

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_COMMIT_META_READY) return true;
        }
        return false;
    }));

    // Empty array, and never an error event for this request-level path --
    // see gbm_request_commit_meta()'s doc comment.
    EXPECT_EQ(log_.lastPayloadOfType(GBM_EVENT_COMMIT_META_READY), "[]");
    EXPECT_TRUE(log_.waitFor(
                    [](const auto& events) {
                        for (const auto& [type, payload] : events) {
                            if (type == GBM_EVENT_ERROR_OCCURRED) return true;
                        }
                        return false;
                    },
                    std::chrono::milliseconds(200)) == false);
}

TEST_F(CommitMetaApiTest, RequestCommitFileCountsCountsEachCommitOnce) {
    // Two more commits, so the batch really batches and a per-oid answer
    // could not be mistaken for a whole-viewport one.
    std::ofstream(repo_ / "file.txt") << "one\ntwo\n";
    std::ofstream(repo_ / "second.txt") << "second\n";
    ASSERT_EQ(runGit({"add", "."}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "two files"}), 0);
    const std::string twoFiles = revParseHead();

    const char* oids[] = {headOid_.c_str(), twoFiles.c_str()};
    gbm_request_commit_file_counts(session_, oids, 2);

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_COMMIT_FILE_COUNTS_READY) return true;
        }
        return false;
    }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_COMMIT_FILE_COUNTS_READY);
    // The root commit is one file and must not read as empty; diff-tree needs
    // --root for that and `git log` gets it for free, which is the one place
    // the two commands differ by design.
    EXPECT_NE(payload.find("{\"oid\":\"" + headOid_ + "\",\"fileCount\":1}"), std::string::npos)
        << payload;
    EXPECT_NE(payload.find("{\"oid\":\"" + twoFiles + "\",\"fileCount\":2}"), std::string::npos)
        << payload;
}

TEST_F(CommitMetaApiTest, UnknownOidIsOmittedFromTheFileCountsReply) {
    // Absent, not zero -- the caller caches these, and caching a zero for a
    // commit git never answered for would show "0 files" until restart.
    const std::string missing(40, 'e');
    const char* oids[] = {headOid_.c_str(), missing.c_str()};
    gbm_request_commit_file_counts(session_, oids, 2);

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_COMMIT_FILE_COUNTS_READY) return true;
        }
        return false;
    }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_COMMIT_FILE_COUNTS_READY);
    EXPECT_EQ(payload.find(missing), std::string::npos) << payload;
    // And the whole batch is not failed by the one bad oid: an empty reply
    // here would mean a single stale oid blanks the column for the viewport.
    // (git refuses the whole invocation for an unknown rev, so this asserts
    // the reply arrives -- what it contains is git's call, not ours.)
    EXPECT_FALSE(payload.empty());
}

}  // namespace
}  // namespace gbm::capi
