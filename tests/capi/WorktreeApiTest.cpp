// Integration tests for the M5 worktree slice of the extern "C" surface
// (gbm_capi.h).
#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"
#include "support/GitCli.h"

#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <ctime>
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

class WorktreeApiTest : public ::testing::Test {
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
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-wt-" + std::string(info->name()));
        extra_ = std::filesystem::temp_directory_path() / ("gbm-capi-wt-extra-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::remove_all(extra_);
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
        std::filesystem::remove_all(extra_, ec);
    }

    /// Fixture git, without a shell in the middle -- see tests/support/GitCli.h
    /// for why that matters (one process instead of two, and no per-platform
    /// quoting hazard).
    int runGit(std::vector<std::string> args) {
        return GitCli::run(repo_, std::move(args));
    }

    std::string worktreesJson() {
        [[maybe_unused]] const int32_t rc = gbm_worktrees_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    std::filesystem::path repo_;
    std::filesystem::path extra_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(WorktreeApiTest, AddWorktreeCreatesANewCheckout) {
    gbm_worktree_add(
        session_, extra_.string().c_str(), "", /*createBranch=*/1, "feature", /*detach=*/0, /*force=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));

    EXPECT_TRUE(std::filesystem::exists(extra_ / "file.txt"));
    const std::string json = worktreesJson();
    EXPECT_NE(json.find("\"branch\":\"feature\""), std::string::npos) << json;
}

TEST_F(WorktreeApiTest, RemoveWorktreeDeletesTheCheckout) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);

    gbm_worktree_remove(session_, extra_.string().c_str(), /*force=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));

    EXPECT_FALSE(std::filesystem::exists(extra_));
}

TEST_F(WorktreeApiTest, LockThenUnlockClearsTheLockedFlag) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);

    gbm_worktree_lock(session_, extra_.string().c_str(), "testing");
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));
    EXPECT_NE(worktreesJson().find("\"isLocked\":true"), std::string::npos);

    log_.clear();
    gbm_worktree_unlock(session_, extra_.string().c_str());
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));
    EXPECT_NE(worktreesJson().find("\"isLocked\":false"), std::string::npos);
}

TEST_F(WorktreeApiTest, PruneRemovesAdministrativeMetadataForADeletedWorktree) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);
    std::filesystem::remove_all(extra_);

    gbm_worktree_prune(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));

    const std::string json = worktreesJson();
    EXPECT_EQ(json.find("feature"), std::string::npos) << json;
}

// The guard that keeps the per-worktree status pass *out* of the refresh set.
//
// `refreshWorktrees()` is a zero-argument `refresh*`, so it is a member of the
// focus-regain (2s-throttled) and F5 refresh sets by the rule in
// `RepoSessionController.refreshRepoStatus()`'s doc comment. Folding the status pass into it would put one `git status` process per
// worktree on both of those paths, for a panel the user may not have open.
//
// This test passes today and is expected to: it is a regression guard, not a
// red-first test, and its whole value is the day someone "simplifies" the two
// entry points into one. Mutation-checked by making WorktreeStore::list() call
// attachPendingCounts -- which reddens exactly this case.
TEST_F(WorktreeApiTest, APlainRefreshLeavesEveryPendingCountUnmeasured) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);
    std::ofstream(extra_ / "dirty.txt") << "uncommitted\n";

    gbm_worktree_refresh(session_);
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));

    const std::string json = worktreesJson();
    EXPECT_EQ(json.find("\"pendingCountState\":\"measured\""), std::string::npos)
        << "a plain refresh must not spawn a status process per worktree: " << json;
    EXPECT_NE(json.find("\"pendingCountState\":\"unmeasured\""), std::string::npos)
        << "and the field has to be there to be unmeasured: " << json;
}

TEST_F(WorktreeApiTest, RequestingPendingCountsMeasuresARealWorkingTree) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);
    // Three changes of three different kinds, so a count that only saw one
    // porcelain-v2 record type cannot pass: one modified-and-staged, one
    // modified-unstaged, one untracked.
    std::ofstream(extra_ / "file.txt") << "changed\n";
    std::ofstream(extra_ / "added.txt") << "staged\n";
    ASSERT_EQ(GitCli::run(extra_, {"add", "added.txt"}), 0);
    std::ofstream(extra_ / "untracked.txt") << "new\n";

    gbm_worktree_request_pending_counts(session_);
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));

    const std::string json = worktreesJson();
    EXPECT_NE(json.find("\"pendingChanges\":3,\"pendingCountState\":\"measured\""),
              std::string::npos)
        << "expected the linked worktree measured at 3: " << json;
    // The repository the session is open on is untouched, so it is the
    // measured-and-genuinely-clean case the tri-state exists for.
    EXPECT_NE(json.find("\"pendingChanges\":0,\"pendingCountState\":\"measured\""),
              std::string::npos)
        << "0 has to be an answer, not a synonym for unmeasured: " << json;
}

TEST_F(WorktreeApiTest, AWorktreeWhoseDirectoryIsGoneIsNotApplicableAndRaisesNoError) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);
    std::filesystem::remove_all(extra_);

    gbm_worktree_request_pending_counts(session_);
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));

    const std::string json = worktreesJson();
    EXPECT_NE(json.find("\"pendingCountState\":\"notApplicable\""), std::string::npos) << json;

    std::lock_guard<std::mutex> lock(log_.mutex);
    EXPECT_FALSE(anyEventOfType(log_.events, GBM_EVENT_ERROR_OCCURRED))
        << "knowing the command cannot run is not a failure to report";
}

/// Every `"createdAtUnix":N` in the payload, in the order it appears.
std::vector<std::int64_t> createdAtValues(const std::string& json) {
    const std::string key = "\"createdAtUnix\":";
    std::vector<std::int64_t> out;
    for (std::size_t at = json.find(key); at != std::string::npos;
         at = json.find(key, at + key.size())) {
        out.push_back(std::strtoll(json.c_str() + at + key.size(), nullptr, 10));
    }
    return out;
}

// The real-git half of attachCreatedAt: the unit tests hand-write the reflog
// bytes, so on their own they are evidence about the parser and never about
// git's actual output ([TEST-fixture-cannot-disagree] shape 9 -- ask which
// side assigns the field). This is the only test that reads a file git wrote.
TEST_F(WorktreeApiTest, ALinkedWorktreeReportsItsCreationTimeAndTheCurrentOneDoesNot) {
    const auto before = static_cast<std::int64_t>(std::time(nullptr));
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);

    gbm_worktree_refresh(session_);
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));
    const auto after = static_cast<std::int64_t>(std::time(nullptr));

    const std::string json = worktreesJson();
    const std::vector<std::int64_t> values = createdAtValues(json);
    ASSERT_EQ(values.size(), 2u) << json;

    // Asserted as a pair rather than by index: which entry is which is
    // `git worktree list`'s ordering, and that is not the claim being made.
    const std::size_t absent =
        static_cast<std::size_t>(std::count(values.begin(), values.end(), 0));
    EXPECT_EQ(absent, 1u) << "the current worktree has no worktrees/<name>/ "
                             "directory, so it reports absent -- not now(): "
                          << json;

    const std::int64_t created = values[0] == 0 ? values[1] : values[0];
    EXPECT_GE(created, before);
    EXPECT_LE(created, after) << "a value outside the window means this read "
                                 "something other than the add: "
                              << json;
}

// The worktree panel and the Add worktree dialog both read the published
// worktree list, which records each worktree's branch. A checkout changes
// that branch, so a list left from before it showed the old branch and kept
// the one just switched away from "already checked out" in the add dialog.
TEST_F(WorktreeApiTest, ACheckoutRepublishesTheWorktreeListWithTheNewBranch) {
    ASSERT_EQ(runGit({"branch", "other"}), 0);
    gbm_worktree_refresh(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));
    ASSERT_NE(worktreesJson().find("\"branch\":\"main\""), std::string::npos);
    log_.clear();

    gbm_branch_checkout(session_, "other", /*detach=*/0, /*createBranch=*/0, "", /*force=*/0,
                        /*stashFirst=*/0, /*recurseSubmodules=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }))
        << "a checkout must republish the worktree list";

    const std::string json = worktreesJson();
    EXPECT_NE(json.find("\"branch\":\"other\""), std::string::npos) << json;
    EXPECT_EQ(json.find("\"branch\":\"main\""), std::string::npos) << json;
}

// The other two ways a worktree's branch changes under it: a new branch
// checked out on creation, and a rename -- including a rename of the branch
// *another* worktree has checked out, which `git branch -m` allows.
TEST_F(WorktreeApiTest, CreatingAndCheckingOutABranchRepublishesTheWorktreeList) {
    gbm_branch_create(session_, "fresh", "", /*checkoutAfter=*/1, /*setUpstream=*/0, "");
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }))
        << "a branch created and checked out must republish the worktree list";
    EXPECT_NE(worktreesJson().find("\"branch\":\"fresh\""), std::string::npos) << worktreesJson();
}

TEST_F(WorktreeApiTest, RenamingABranchAnotherWorktreeHasCheckedOutRepublishesTheWorktreeList) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);

    gbm_branch_rename(session_, "feature", "feature-renamed", /*force=*/0, /*renameRemote=*/0, "");
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }))
        << "a rename must republish the worktree list";
    const std::string json = worktreesJson();
    EXPECT_NE(json.find("\"branch\":\"feature-renamed\""), std::string::npos) << json;
}

// The user's report: "delete a worktree, the branch it used to be still
// cannot be deleted". Two shapes of "removed": through gbm, and a directory
// already gone from disk (deleted in Finder) that is then removed through gbm.
TEST_F(WorktreeApiTest, AfterRemovingAWorktreeItsBranchCanBeDeleted) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);
    gbm_worktree_remove(session_, extra_.string().c_str(), /*force=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));
    log_.clear();

    const char* names[] = {"feature"};
    gbm_branch_delete(session_, names, 1, /*forces=*/nullptr, /*expectedTips=*/nullptr, /*isRemote=*/0, "");
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_OPERATION_FINISHED); }));
    EXPECT_NE(runGit({"rev-parse", "--verify", "--quiet", "refs/heads/feature"}), 0)
        << "the branch must be gone";
}

TEST_F(WorktreeApiTest, RemovingAWorktreeWhoseDirectoryIsAlreadyGoneFreesItsBranch) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);
    std::filesystem::remove_all(extra_);

    gbm_worktree_remove(session_, extra_.string().c_str(), /*force=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        return anyEventOfType(events, GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    }));
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }))
        << "remove must leave the list republished without the entry";
    EXPECT_EQ(worktreesJson().find("feature"), std::string::npos) << worktreesJson();
    log_.clear();

    const char* names[] = {"feature"};
    gbm_branch_delete(session_, names, 1, /*forces=*/nullptr, /*expectedTips=*/nullptr, /*isRemote=*/0, "");
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_OPERATION_FINISHED); }));
    EXPECT_NE(runGit({"rev-parse", "--verify", "--quiet", "refs/heads/feature"}), 0)
        << "a worktree registration left behind keeps git refusing the delete";
}

// git frees the branch (the two tests above), but the sidebar's bulk "gone"
// selection excludes any branch whose RefInfo.worktreePath is non-empty, and
// refs were read only by checkout-shaped operations -- never by a worktree
// add/remove/prune. The removed worktree's branch stayed unselectable.
TEST_F(WorktreeApiTest, RemovingAWorktreeRereadsRefsSoItsBranchHasNoWorktreePath) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);
    gbm_history_refresh(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_REFS_UPDATED); }));
    log_.clear();

    gbm_worktree_remove(session_, extra_.string().c_str(), /*force=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_REFS_UPDATED); }))
        << "a worktree removal must re-read refs";

    ASSERT_EQ(gbm_refs_json(session_), 0);
    std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
    EXPECT_EQ(json.find(extra_.filename().string()), std::string::npos)
        << "no ref may still name the removed worktree: " << json;
}

// 使用者裁定 2026-10-21: 「worktree delete 應該自己預設 prune 掉」. A remove
// runs `git worktree prune` after it, so registrations whose directory is
// already gone (deleted outside gbm) go with it instead of lingering as
// prunable entries that still hold their branch.
TEST_F(WorktreeApiTest, RemovingAWorktreeAlsoPrunesRegistrationsWhoseDirectoryIsGone) {
    const std::filesystem::path stale = extra_.string() + "-stale";
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "orphaned", stale.string()}), 0);
    std::filesystem::remove_all(stale);

    gbm_worktree_remove(session_, extra_.string().c_str(), /*force=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));

    const std::string json = worktreesJson();
    EXPECT_EQ(json.find("orphaned"), std::string::npos) << json;
    EXPECT_FALSE(std::filesystem::exists(repo_ / ".git" / "worktrees" / stale.filename()));
}

// The Flutter side opens every session as `<workDir>/.git` with no commonDir
// (`RepoIdentity.forWorkDir`), and in a linked worktree that path is a
// `gitdir:` pointer *file*. Every per-worktree stat RepoState makes
// (MERGE_HEAD, rebase-merge/, index.lock) then looks under a file and finds
// nothing, so a merge in progress there is reported as a clean tree.
TEST_F(WorktreeApiTest, ASessionOpenedThroughALinkedWorktreesGitFileSeesItsOwnMergeState) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", extra_.string()}), 0);
    ASSERT_TRUE(std::filesystem::is_regular_file(extra_ / ".git"));

    const std::filesystem::path adminDir = repo_ / ".git" / "worktrees" / extra_.filename();
    ASSERT_TRUE(std::filesystem::is_directory(adminDir));
    std::string head;
    std::ifstream(repo_ / ".git" / "refs" / "heads" / "main") >> head;
    std::ofstream(adminDir / "MERGE_HEAD") << head << "\n";

    GbmSessionHandle linked =
        gbm_session_open(extra_.string().c_str(), (extra_ / ".git").string().c_str(), "");
    ASSERT_NE(linked, nullptr);
    ASSERT_EQ(gbm_repo_state_json(linked), 0);
    std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
    gbm_session_close(linked);

    EXPECT_NE(json.find("\"isClean\":false"), std::string::npos) << json;
}

// Every operation that moves HEAD changes the worktree's `headOid`, which
// the worktree panel draws ("a1b2c3d · subject") and keys its pending-count
// cache on (`path@headOid`). Republishing only on a branch change left both
// stale after a commit, reset, undo, pull or merge until the next F5/focus
// sweep. One test per dispatch path that re-reads refs after an operation.
class WorktreeHeadRepublishTest : public WorktreeApiTest {
protected:
    std::string head() { return GitCli::capture(repo_, {"rev-parse", "HEAD"}).firstLine(); }

    /// A fresh list so the next republish is the operation's, not the open's.
    void settle() {
        gbm_worktree_refresh(session_);
        ASSERT_TRUE(log_.waitFor(
            [](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }));
        log_.clear();
    }

    void commitWithGit(const std::string& name) {
        std::ofstream(repo_ / name) << name << "\n";
        ASSERT_EQ(runGit({"add", name}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", name}), 0);
    }

    /// True when a republish arrives, within the usual 10 s, that names [oid]
    /// as a worktree's head. Republishes that still name another head are
    /// skipped: settle()'s own refresh can land after it cleared the log.
    bool republishedWithHead(const std::string& oid) {
        const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
        while (std::chrono::steady_clock::now() < deadline) {
            const auto left = std::chrono::duration_cast<std::chrono::milliseconds>(
                deadline - std::chrono::steady_clock::now());
            if (!log_.waitFor(
                    [](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); },
                    left)) {
                return false;
            }
            log_.clear();
            if (worktreesJson().find("\"headOid\":\"" + oid + "\"") != std::string::npos) {
                return true;
            }
        }
        return false;
    }
};

TEST_F(WorktreeHeadRepublishTest, ACommitRepublishesTheWorktreeListWithTheNewHead) {
    std::ofstream(repo_ / "second.txt") << "second\n";
    ASSERT_EQ(runGit({"add", "second.txt"}), 0);
    settle();

    gbm_commit_changes(session_, "Second", /*amend=*/0, /*signOff=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        return anyEventOfType(events, GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    }));
    EXPECT_TRUE(republishedWithHead(head())) << worktreesJson();
}

// Reset goes through submitOperation, the path every merge, cherry-pick,
// revert, rebase, am and bisect step shares.
TEST_F(WorktreeHeadRepublishTest, AResetRepublishesTheWorktreeListWithTheNewHead) {
    const std::string first = head();
    commitWithGit("second.txt");
    settle();

    gbm_reset_to(session_, first.c_str(), /*mode=*/0);
    EXPECT_TRUE(republishedWithHead(first)) << worktreesJson();
}

TEST_F(WorktreeHeadRepublishTest, AnUndoRepublishesTheWorktreeListWithTheNewHead) {
    const std::string first = head();
    std::ofstream(repo_ / "second.txt") << "second\n";
    ASSERT_EQ(runGit({"add", "second.txt"}), 0);
    gbm_commit_changes(session_, "Second", /*amend=*/0, /*signOff=*/0);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        return anyEventOfType(events, GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    }));
    ASSERT_NE(head(), first);
    settle();

    gbm_undo_last(session_);
    EXPECT_TRUE(republishedWithHead(first)) << worktreesJson();
}

TEST_F(WorktreeHeadRepublishTest, BranchingFromAStashRepublishesTheWorktreeListWithTheNewBranch) {
    std::ofstream(repo_ / "file.txt") << "changed\n";
    ASSERT_EQ(runGit({"stash", "--quiet"}), 0);
    settle();

    gbm_stash_branch(session_, 0, "from-stash");
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) { return anyEventOfType(events, GBM_EVENT_WORKTREES_UPDATED); }))
        << "a branch made from a stash is checked out, so the list must be republished";
    EXPECT_NE(worktreesJson().find("\"branch\":\"from-stash\""), std::string::npos) << worktreesJson();
}

TEST_F(WorktreeHeadRepublishTest, APullRepublishesTheWorktreeListWithTheNewHead) {
    // The repository is its own remote: `ahead` is one commit past main, and
    // pulling it into main fast-forwards HEAD.
    ASSERT_EQ(runGit({"remote", "add", "origin", repo_.string()}), 0);
    ASSERT_EQ(runGit({"checkout", "--quiet", "-b", "ahead"}), 0);
    commitWithGit("second.txt");
    const std::string ahead = head();
    ASSERT_EQ(runGit({"checkout", "--quiet", "main"}), 0);
    settle();

    gbm_pull(session_, "origin", "ahead", /*rebase=*/0, /*stashFirst=*/0);
    EXPECT_TRUE(republishedWithHead(ahead)) << worktreesJson();
}

}  // namespace
}  // namespace gbm::capi
