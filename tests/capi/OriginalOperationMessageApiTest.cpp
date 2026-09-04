// Integration tests for the M6 commit 8 slice of the extern "C" surface
// (gbm_capi.h): gbm_request_original_operation_message()/
// GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY, and the write side --
// gbm_cherry_pick_continue_with_message()/gbm_rebase_continue_with_message().
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

    /// Drops everything recorded so far, so a subsequent wait can only be
    /// satisfied by events from the operation issued after this call.
    ///
    /// Without it, "wait until N events of type T exist" counts events from
    /// earlier operations too: an operation that happens to emit two
    /// OPERATION_FINISHED (its own plus one from a follow-up refresh) would
    /// satisfy a `count >= 2` wait before the *second* operation had even
    /// started, and the assertions after it would read pre-operation state.
    void clear() {
        std::lock_guard<std::mutex> lock(mutex);
        events.clear();
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

bool waitForOperationFinished(EventLog& log) {
    return log.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_OPERATION_FINISHED) return true;
        }
        return false;
    });
}

/// Waits until the session has gone quiet again after an operation.
///
/// `Session::submitOperation` emits GBM_EVENT_OPERATION_FINISHED and only
/// *then* calls refreshWorkingCopy() (and refreshHistory()), which post a
/// `git status` onto the shared read pool. So OPERATION_FINISHED does not
/// mean "no git process is running against this repository" -- it means the
/// operation's own git process is done, while the session's follow-up reads
/// are still starting up.
///
/// A test that shells out to raw git in that window races the refresh for
/// `.git/index.lock` and fails with exit 128, which is exactly how
/// `resolveConflictOnDisk`'s `git add` used to fail intermittently (roughly
/// 1 run in 10 locally; on CI it showed up on the slower sanitizer jobs).
/// GBM_EVENT_WORKING_COPY_STATUS_UPDATED is emitted at the very end of that
/// refresh, so waiting for it is what makes the repository safe to touch
/// directly again.
///
/// Real clients never need this: they mutate through the capi, whose
/// operations are serialized on the session's own queue.
bool waitForWorkingCopyStatusUpdated(EventLog& log) {
    return log.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_STATUS_UPDATED) return true;
        }
        return false;
    });
}

// Both branches edit the same file so cherry-pick/rebase produce a genuine
// conflict, matching the fixture used to empirically probe git's own
// MERGE_MSG/rebase-merge/message behavior during M6 commit 7's design.
class OriginalOperationMessageApiTest : public ::testing::Test {
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
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-oom-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "f.txt") << "line1\n";
        ASSERT_EQ(runGit({"add", "f.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "base commit"}), 0);

        ASSERT_EQ(runGit({"checkout", "--quiet", "-b", "branchA"}), 0);
        std::ofstream(repo_ / "f.txt", std::ios::trunc) << "A change\n";
        ASSERT_EQ(runGit({"commit", "--quiet", "-am", "A changes f.txt"}), 0);
        branchACommit_ = commitHex("branchA");

        ASSERT_EQ(runGit({"checkout", "--quiet", "main"}), 0);
        std::ofstream(repo_ / "f.txt", std::ios::trunc) << "main change\n";
        ASSERT_EQ(runGit({"commit", "--quiet", "-am", "main changes f.txt"}), 0);

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

    std::string commitHex(const std::string& revision) {
        return GitCli::capture(repo_, {"rev-parse", revision}).firstLine();
    }

    // Trims trailing newlines: `git log --format=%B` appends its own
    // terminator on top of the commit message's own trailing newline, and
    // that formatting detail is not what these tests care about.
    std::string headCommitMessage() {
        std::string content = GitCli::capture(repo_, {"log", "-1", "--format=%B"}).out;
        while (!content.empty() && content.back() == '\n') {
            content.pop_back();
        }
        return content;
    }

    /// Resolves the fixture's one conflicted file the way a user would --
    /// with raw git, behind the session's back.
    ///
    /// Waits for the session's post-operation refresh to finish first; see
    /// [waitForWorkingCopyStatusUpdated] for why `git add` otherwise loses a
    /// race for `.git/index.lock`.
    void resolveConflictOnDisk() {
        ASSERT_TRUE(waitForWorkingCopyStatusUpdated(log_));
        std::ofstream(repo_ / "f.txt", std::ios::trunc) << "resolved\n";
        ASSERT_EQ(runGit({"add", "f.txt"}), 0);
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
    std::string branchACommit_;
};

TEST_F(OriginalOperationMessageApiTest, RequestReturnsGitsProposedMessageDuringConflictedCherryPick) {
    const char* commits[] = {branchACommit_.c_str()};
    gbm_cherry_pick(session_, commits, 1, /*mainline=*/0, /*noCommit=*/0, /*stashFirst=*/0);
    ASSERT_TRUE(waitForOperationFinished(log_));

    gbm_request_original_operation_message(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY) return true;
        }
        return false;
    }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY);
    EXPECT_NE(payload.find("A changes f.txt"), std::string::npos) << payload;
    EXPECT_NE(payload.find("# Conflicts:"), std::string::npos) << payload;

    runGit({"cherry-pick", "--abort"});
}

TEST_F(OriginalOperationMessageApiTest, CherryPickContinueWithMessageUsesTheEditedMessage) {
    const char* commits[] = {branchACommit_.c_str()};
    gbm_cherry_pick(session_, commits, 1, /*mainline=*/0, /*noCommit=*/0, /*stashFirst=*/0);
    ASSERT_TRUE(waitForOperationFinished(log_));

    resolveConflictOnDisk();
    // Cleared so the wait below can only be satisfied by the continue's own
    // OPERATION_FINISHED -- counting to two across the whole log would also
    // accept a second event belonging to the cherry-pick above.
    log_.clear();
    gbm_cherry_pick_continue_with_message(session_, "Custom cherry-pick message");
    ASSERT_TRUE(waitForOperationFinished(log_));
    // HEAD is written by the continue's git process, which has exited by the
    // time the event fires; the extra wait keeps the read off the refresh.
    ASSERT_TRUE(waitForWorkingCopyStatusUpdated(log_));

    EXPECT_EQ(headCommitMessage(), "Custom cherry-pick message");
}

TEST_F(OriginalOperationMessageApiTest, RebaseContinueWithMessageUsesTheEditedMessage) {
    ASSERT_EQ(runGit({"checkout", "--quiet", "branchA"}), 0);

    gbm_rebase_start(session_, "main", "", /*stashFirst=*/0, /*rebaseMerges=*/0, /*autosquash=*/0);
    ASSERT_TRUE(waitForOperationFinished(log_));

    resolveConflictOnDisk();
    // See the cherry-pick test above for why the log is cleared first.
    log_.clear();
    gbm_rebase_continue_with_message(session_, "Custom rebase message");
    ASSERT_TRUE(waitForOperationFinished(log_));
    ASSERT_TRUE(waitForWorkingCopyStatusUpdated(log_));

    EXPECT_EQ(headCommitMessage(), "Custom rebase message");
}

}  // namespace
}  // namespace gbm::capi
