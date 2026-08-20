// Integration test for gbm_branch_create/_rename/_delete against a real
// repo with two commits and a couple of extra local branches.
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

class BranchApiTest : public ::testing::Test {
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
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-branch-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "file.txt") << "v1\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "First commit"}), 0);

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
        if (!remote_.empty()) {
            std::filesystem::remove_all(remote_, ec);
        }
    }

    /// Adds a local bare repository as `origin` and publishes `branch` to it
    /// with `-u`, so the rename tests have a real upstream to carry across.
    /// Deliberately not in SetUp(): only the remote-rename tests need it, and
    /// an extra init+push on every test in this file is pure overhead.
    /// Same fixture shape as RemoteApiTest's -- no network involved.
    void setUpRemoteWithBranch(const std::string& branch) {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        remote_ = std::filesystem::temp_directory_path() /
                  ("gbm-capi-branch-remote-" + std::string(info->name()));
        std::filesystem::remove_all(remote_);
        ASSERT_EQ(runIn(remote_.parent_path(), {"init", "--quiet", "--bare", remote_.string()}), 0);
        ASSERT_EQ(runGit({"remote", "add", "origin", remote_.string()}), 0);
        ASSERT_EQ(runGit({"branch", branch}), 0);
        ASSERT_EQ(runGit({"push", "--quiet", "-u", "origin", branch}), 0);
    }

    int runIn(const std::filesystem::path& dir, std::vector<std::string> args) {
        return GitCli::run(dir, std::move(args));
    }

    /// Branch names present in the bare remote, read from the remote itself
    /// rather than from any remote-tracking ref -- a stale local ref would
    /// otherwise make a failed delete look like it worked.
    std::vector<std::string> remoteBranches() {
        return GitCli::capture(remote_, {"branch", "--format=%(refname:short)"}).lines();
    }

    /// `branch`'s configured upstream, or empty when it has none.
    std::string upstreamOf(const std::string& branch) {
        return GitCli::capture(
                   repo_, {"for-each-ref", "--format=%(upstream:short)", "refs/heads/" + branch})
            .firstLine();
    }

    /// Fixture git, without a shell in the middle -- see tests/support/GitCli.h
    /// for why that matters (one process instead of two, and no per-platform
    /// quoting hazard).
    int runGit(std::vector<std::string> args) {
        return GitCli::run(repo_, std::move(args));
    }

    std::vector<std::string> localBranches() {
        const std::string outFile = (repo_ / "..gbm_branch_test_list.txt").string();
        // This used to build a command string, and the quoting was a genuine
        // hazard rather than a theoretical one: single quotes are POSIX-shell
        // syntax that cmd.exe passes through literally to git.exe on Windows,
        // so git got them as part of the format string and the branch names
        // never came back bare -- while leaving %(refname:short) unquoted made
        // dash treat the parentheses as a syntax error. An argv vector has
        // neither problem, because no shell ever sees it.
        return GitCli::capture(repo_, {"branch", "--format=%(refname:short)"})
            .lines();
    }

    bool waitForOperationFinished() {
        return log_.waitFor([](const auto& events) {
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_OPERATION_FINISHED) return true;
            }
            return false;
        });
    }

    /// The most recent GBM_EVENT_OPERATION_FINISHED payload, or empty if none
    /// arrived. Used to assert on the OperationOutcome JSON's "kind" field.
    std::string lastOperationFinishedPayload() {
        std::lock_guard<std::mutex> lock(log_.mutex);
        std::string payload;
        for (const auto& [type, body] : log_.events) {
            if (type == GBM_EVENT_OPERATION_FINISHED) payload = body;
        }
        return payload;
    }

    std::filesystem::path repo_;
    std::filesystem::path remote_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(BranchApiTest, CreateBranchAddsALocalBranchWithoutMovingHead) {
    gbm_branch_create(session_, "feature-1", "", /*checkoutAfter=*/0, /*setUpstream=*/0, "");
    ASSERT_TRUE(waitForOperationFinished());

    // CreateBranchOperation does not override Operation::kind(), so JsonCodec
    // must omit the key entirely rather than emit "kind":"" -- this is the
    // proof that stamping checkout/delete-branch below leaves every other
    // outcome's JSON byte-identical to before.
    EXPECT_EQ(lastOperationFinishedPayload().find("\"kind\""), std::string::npos)
        << lastOperationFinishedPayload();

    const auto branches = localBranches();
    EXPECT_NE(std::find(branches.begin(), branches.end(), "feature-1"), branches.end());

    EXPECT_EQ(GitCli::capture(repo_, {"symbolic-ref", "--short", "HEAD"}).firstLine(),
              "main");
}

TEST_F(BranchApiTest, CreateBranchWithCheckoutAfterMovesHead) {
    gbm_branch_create(session_, "feature-2", "", /*checkoutAfter=*/1, /*setUpstream=*/0, "");
    ASSERT_TRUE(waitForOperationFinished());

    EXPECT_EQ(GitCli::capture(repo_, {"symbolic-ref", "--short", "HEAD"}).firstLine(),
              "feature-2");
}

TEST_F(BranchApiTest, RenameBranchChangesTheLocalBranchName) {
    ASSERT_EQ(runGit({"branch", "old-name"}), 0);

    gbm_branch_rename(
        session_, "old-name", "new-name", /*force=*/0, /*renameRemote=*/0, /*remoteName=*/"");
    ASSERT_TRUE(waitForOperationFinished());

    const auto branches = localBranches();
    EXPECT_EQ(std::find(branches.begin(), branches.end(), "old-name"), branches.end());
    EXPECT_NE(std::find(branches.begin(), branches.end(), "new-name"), branches.end());
}

TEST_F(BranchApiTest, RenameBranchWithRenameRemotePushesTheNewNameAndDeletesTheOldOne) {
    setUpRemoteWithBranch("old-name");
    const auto before = remoteBranches();
    ASSERT_NE(std::find(before.begin(), before.end(), "old-name"), before.end());

    gbm_branch_rename(
        session_, "old-name", "new-name", /*force=*/0, /*renameRemote=*/1, /*remoteName=*/"origin");
    ASSERT_TRUE(waitForOperationFinished());

    const auto branches = localBranches();
    EXPECT_NE(std::find(branches.begin(), branches.end(), "new-name"), branches.end());

    const auto onRemote = remoteBranches();
    EXPECT_NE(std::find(onRemote.begin(), onRemote.end(), "new-name"), onRemote.end());
    EXPECT_EQ(std::find(onRemote.begin(), onRemote.end(), "old-name"), onRemote.end());

    // --set-upstream on the push is what re-points tracking at the new name;
    // without it the renamed branch would still track origin/old-name.
    EXPECT_EQ(upstreamOf("new-name"), "origin/new-name");
}

TEST_F(BranchApiTest, RenameBranchWithoutRenameRemoteClearsTheUpstreamAndLeavesTheRemoteAlone) {
    setUpRemoteWithBranch("old-name");
    ASSERT_EQ(upstreamOf("old-name"), "origin/old-name");

    gbm_branch_rename(
        session_, "old-name", "new-name", /*force=*/0, /*renameRemote=*/0, /*remoteName=*/"");
    ASSERT_TRUE(waitForOperationFinished());

    // `git branch -m` keeps branch.<name>.remote/.merge, so this is the one
    // assertion that proves the --unset-upstream step ran: without it the
    // renamed branch silently still tracks origin/old-name.
    EXPECT_EQ(upstreamOf("new-name"), "");

    const auto onRemote = remoteBranches();
    EXPECT_NE(std::find(onRemote.begin(), onRemote.end(), "old-name"), onRemote.end());
}

TEST_F(BranchApiTest, RenameBranchReportsTheLocalRenameWhenTheRemoteStepFails) {
    ASSERT_EQ(runGit({"branch", "old-name"}), 0);

    // No such remote, so the push fails while the local rename has already
    // landed -- the half-done case the summary exists to describe.
    gbm_branch_rename(session_,
                      "old-name",
                      "new-name",
                      /*force=*/0,
                      /*renameRemote=*/1,
                      /*remoteName=*/"no-such-remote");
    ASSERT_TRUE(waitForOperationFinished());

    const auto branches = localBranches();
    EXPECT_NE(std::find(branches.begin(), branches.end(), "new-name"), branches.end());

    const std::string payload = lastOperationFinishedPayload();
    EXPECT_NE(payload.find("\"succeeded\":false"), std::string::npos) << payload;
    EXPECT_NE(payload.find("Renamed locally to new-name"), std::string::npos) << payload;
}

TEST_F(BranchApiTest, DeleteBranchRemovesASingleLocalBranch) {
    ASSERT_EQ(runGit({"branch", "to-delete"}), 0);

    const char* names[] = {"to-delete"};
    gbm_branch_delete(session_, names, 1, /*force=*/0, /*isRemote=*/0, "");
    ASSERT_TRUE(waitForOperationFinished());

    // DeleteBranchOperation::kind() lets Dart's PendingOperationTracker
    // attribute this outcome to the deleteBranch() call that produced it,
    // instead of whichever operationFinished event happens to arrive next.
    EXPECT_NE(lastOperationFinishedPayload().find("\"kind\":\"delete-branch\""), std::string::npos)
        << lastOperationFinishedPayload();

    const auto branches = localBranches();
    EXPECT_EQ(std::find(branches.begin(), branches.end(), "to-delete"), branches.end());
}

TEST_F(BranchApiTest, DeleteBranchAcceptsMultipleNamesInOneCall) {
    ASSERT_EQ(runGit({"branch", "multi-1"}), 0);
    ASSERT_EQ(runGit({"branch", "multi-2"}), 0);

    const char* names[] = {"multi-1", "multi-2"};
    gbm_branch_delete(session_, names, 2, /*force=*/0, /*isRemote=*/0, "");
    ASSERT_TRUE(waitForOperationFinished());

    const auto branches = localBranches();
    EXPECT_EQ(std::find(branches.begin(), branches.end(), "multi-1"), branches.end());
    EXPECT_EQ(std::find(branches.begin(), branches.end(), "multi-2"), branches.end());
}

}  // namespace
}  // namespace gbm::capi
