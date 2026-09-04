// Per-worktree uncommitted-change counts: spec page 19's `PANELSPEC` row for
// manage-worktrees names 待提交數 in the detail column, and the mockup writes
// it as 「9 個未提交變更」.
//
// Two things are pinned here that a simpler implementation gets wrong:
//
//  1. **A clean worktree is `Measured` with count 0, never `Unmeasured`.**
//     The whole point of the tri-state is that 0 is an answer.
//  2. **A rename must not shift the count.** Under `--porcelain=v2 -z` a
//     rename ('2') spends *two* NUL records where every other kind spends
//     one, so a loop that counts records instead of parsing them is silently
//     wrong after the first rename -- the same shape as the numstat
//     three-records-per-rename trap already recorded for attachNumstat().
//     Cases 3 and 4 differ only by that rename, which is what makes case 4
//     able to fail while case 3 passes.
#include "core/git/ops/WorktreeOps.h"
#include "support/FakeProcessRunner.h"

#include <gtest/gtest.h>
#include <string>
#include <vector>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

/// Joins porcelain-v2 records with the NUL separator git actually emits.
std::string nulJoined(const std::vector<std::string>& records) {
    std::string out;
    for (const std::string& record : records) {
        out += record;
        out.push_back('\0');
    }
    return out;
}

FakeProcessRunner::Response statusOut(const std::vector<std::string>& records) {
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    response.out = nulJoined(records);
    return response;
}

/// One ordinary modified entry ('1'), the commonest record shape.
std::string modified(const std::string& path) {
    return "1 .M N... 100644 100644 100644 "
           "1111111111111111111111111111111111111111 "
           "1111111111111111111111111111111111111111 " +
           path;
}

WorktreeInfo linkedAt(const std::string& path) {
    WorktreeInfo info;
    info.path = path;
    info.headOid = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0";
    info.branch = "feature";
    return info;
}

/// How many `status` commands the runner was asked for. Counted, not
/// `.any()`-ed: the interesting failures here are "ran when it should have
/// skipped" and "ran twice", and a boolean cannot see either.
std::size_t statusInvocations(const FakeProcessRunner& runner) {
    std::size_t count = 0;
    for (std::size_t i = 0; i < runner.invocationCount(); ++i) {
        const std::vector<std::string> args = runner.invokedArgs(i);
        for (const std::string& arg : args) {
            if (arg == "status") {
                ++count;
                break;
            }
        }
    }
    return count;
}

TEST(WorktreePendingCountTest, BareWorktreeIsSkippedWithoutRunningStatus) {
    FakeProcessRunner runner;
    WorktreeInfo bare = linkedAt("/repo/bare");
    bare.isBare = true;
    std::vector<WorktreeInfo> worktrees{bare};

    attachPendingCounts(runner, worktrees, CancellationToken());

    EXPECT_EQ(statusInvocations(runner), 0u)
        << "a bare worktree has no work tree; `git status` there is "
           "`fatal: this operation must be run in a work tree`";
    EXPECT_EQ(worktrees[0].pendingCountState, WorktreePendingCountState::NotApplicable);
}

TEST(WorktreePendingCountTest, PrunableWorktreeIsSkippedWithoutRunningStatus) {
    FakeProcessRunner runner;
    WorktreeInfo gone = linkedAt("/repo/gone");
    gone.isPrunable = true;
    std::vector<WorktreeInfo> worktrees{gone};

    attachPendingCounts(runner, worktrees, CancellationToken());

    EXPECT_EQ(statusInvocations(runner), 0u)
        << "the directory is gone, so the command cannot start at all";
    EXPECT_EQ(worktrees[0].pendingCountState, WorktreePendingCountState::NotApplicable);
}

TEST(WorktreePendingCountTest, CleanWorktreeIsMeasuredZeroNotUnmeasured) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, statusOut({}));
    std::vector<WorktreeInfo> worktrees{linkedAt("/repo/wt")};

    attachPendingCounts(runner, worktrees, CancellationToken());

    EXPECT_EQ(worktrees[0].pendingChanges, 0u);
    EXPECT_EQ(worktrees[0].pendingCountState, WorktreePendingCountState::Measured)
        << "0 has to mean measured-and-clean, or the tri-state buys nothing";
}

TEST(WorktreePendingCountTest, ARenameDoesNotShiftTheCount) {
    FakeProcessRunner runner;
    // Nine changes, one of which is a rename. Under -z a '2' record is
    // followed by a second record carrying the original path, so these nine
    // entries arrive as ten records.
    runner.whenArgsContain({"status", "--porcelain=v2"},
                           statusOut({
                               modified("a.txt"),
                               modified("b.txt"),
                               "2 R. N... 100644 100644 100644 "
                               "1111111111111111111111111111111111111111 "
                               "1111111111111111111111111111111111111111 R100 new.txt",
                               "old.txt",  // the rename's second record
                               modified("c.txt"),
                               modified("d.txt"),
                               "? untracked-one.txt",
                               "? untracked-two.txt",
                               modified("e.txt"),
                               modified("f.txt"),
                           }));
    std::vector<WorktreeInfo> worktrees{linkedAt("/repo/wt")};

    attachPendingCounts(runner, worktrees, CancellationToken());

    EXPECT_EQ(worktrees[0].pendingChanges, 9u)
        << "a record counter reads 10 here and is silently wrong from the "
           "rename onwards";
    EXPECT_EQ(worktrees[0].pendingCountState, WorktreePendingCountState::Measured);
}

TEST(WorktreePendingCountTest, AFailedStatusIsCachedAsFailedNotLeftUnmeasured) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response broken;
    broken.exitCode = 128;
    broken.err = "fatal: not a git repository";
    runner.whenArgsContain({"status", "--porcelain=v2"}, broken);
    std::vector<WorktreeInfo> worktrees{linkedAt("/repo/wt")};

    attachPendingCounts(runner, worktrees, CancellationToken());

    EXPECT_EQ(worktrees[0].pendingCountState, WorktreePendingCountState::Failed)
        << "a failure is an answer; leaving it Unmeasured makes the caller "
           "re-request forever";
}

TEST(WorktreePendingCountTest, EveryEligibleWorktreeIsMeasuredExactlyOnce) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"},
                           statusOut({modified("a.txt"), modified("b.txt")}));
    WorktreeInfo bare = linkedAt("/repo/bare");
    bare.isBare = true;
    std::vector<WorktreeInfo> worktrees{linkedAt("/repo/one"), bare, linkedAt("/repo/two")};

    attachPendingCounts(runner, worktrees, CancellationToken());

    EXPECT_EQ(statusInvocations(runner), 2u) << "one per eligible worktree, no more";
    EXPECT_EQ(worktrees[0].pendingChanges, 2u);
    EXPECT_EQ(worktrees[2].pendingChanges, 2u);
}

}  // namespace
}  // namespace gbm
