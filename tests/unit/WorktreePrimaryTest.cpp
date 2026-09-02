// `isMain` and `isPrimary` name two different worktrees, and until this test
// existed only one of them had an implementation.
//
// `WorktreeStore::list()` calls `parseEntry(entry, paths_.workDir())`, so
// `isMain` compares each entry against **this session's own working
// directory**. That is "the worktree gbm is open on" -- the mockup's
// `current` badge -- and it is *not* "the repository's main worktree". The
// header has always documented the field that way; what had no field at all
// was the other meaning, which is the one `git worktree remove` cares about,
// because git refuses to remove the main worktree and will happily remove
// the one you are standing in.
//
// **Every fixture in which the two coincide is blind to this**, which is
// almost all of them: open gbm on a normal clone and entry 0 is both. The
// case below opens the store on a *linked* worktree, so the two flags land on
// different entries and a single field cannot answer for both. Same shape as
// [REF-remote-name-is-not-local-name], where a local branch and its remote
// counterpart share a name in nearly every fixture.
//
// The ordering premise -- entry 0 of `git worktree list --porcelain` is the
// main worktree -- was measured on git 2.55.0 rather than read off the docs:
// main comes first from every vantage point (from the main worktree, from a
// linked one, and from the alphabetically-first linked one), and the linked
// entries that follow are sorted by path rather than by creation order.
#include "core/git/RepoPaths.h"
#include "core/git/ops/WorktreeOps.h"
#include "support/FakeProcessRunner.h"

#include <filesystem>
#include <gtest/gtest.h>
#include <string>
#include <vector>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

/// Real directories, because `parseEntry` resolves `isMain` through
/// `fsutil::fileIdOf` rather than a string compare -- a path that does not
/// exist has no file id, and the comparison then answers false for every
/// entry, which would make this test pass for the wrong reason.
class WorktreePrimaryTest : public ::testing::Test {
protected:
    void SetUp() override {
        root_ = std::filesystem::temp_directory_path() /
                ("gbm-wt-primary-" + std::to_string(::testing::UnitTest::GetInstance()
                                                        ->current_test_info()
                                                        ->result()
                                                        ->start_timestamp()));
        std::filesystem::create_directories(mainDir());
        std::filesystem::create_directories(linkedDir());
    }

    void TearDown() override {
        std::error_code ignored;
        std::filesystem::remove_all(root_, ignored);
    }

    std::filesystem::path mainDir() const { return root_ / "main-repo"; }

    std::filesystem::path linkedDir() const { return root_ / "wt-linked"; }

    /// What `git worktree list --porcelain` emits: main first, then linked.
    std::string listOutput() const {
        return "worktree " + mainDir().string() +
               "\n"
               "HEAD 1111111111111111111111111111111111111111\n"
               "branch refs/heads/main\n"
               "\n"
               "worktree " +
               linkedDir().string() +
               "\n"
               "HEAD 2222222222222222222222222222222222222222\n"
               "branch refs/heads/feature\n"
               "\n";
    }

    FakeProcessRunner::Response listResponse() const {
        FakeProcessRunner::Response response;
        response.exitCode = 0;
        response.out = listOutput();
        return response;
    }

    std::filesystem::path root_;
};

}  // namespace

// The case the old single-flag code could not express. A session opened on
// the linked worktree must mark the *linked* one current and the *first* one
// primary -- and `Remove` is gated on primary, so with only `isMain` the
// button refused to remove the worktree you are standing in (removable) and
// offered to remove the repository's main one (not removable).
TEST_F(WorktreePrimaryTest, OpenedOnALinkedWorktreeTheTwoFlagsLandOnDifferentEntries) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"worktree", "list"}, listResponse());
    WorktreeStore store(runner, RepoPaths(linkedDir(), linkedDir() / ".git", mainDir() / ".git"));

    auto result = store.list(CancellationToken());

    ASSERT_TRUE(result);
    const std::vector<WorktreeInfo>& infos = result.value();
    ASSERT_EQ(infos.size(), 2u);

    EXPECT_TRUE(infos[0].isPrimary) << "entry 0 is the repository's main worktree";
    EXPECT_FALSE(infos[0].isMain) << "but the session is not open on it";

    EXPECT_FALSE(infos[1].isPrimary);
    EXPECT_TRUE(infos[1].isMain) << "the session is open on the linked worktree";
}

// The common case, and the reason the defect survived: on an ordinary clone
// the two flags coincide, so a fixture built here proves nothing about the
// case above. Kept anyway, because a change that made `isPrimary` mean
// something else entirely would still have to keep this true.
TEST_F(WorktreePrimaryTest, OpenedOnTheMainWorktreeBothFlagsLandOnEntryZero) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"worktree", "list"}, listResponse());
    WorktreeStore store(runner, RepoPaths(mainDir(), mainDir() / ".git", mainDir() / ".git"));

    auto result = store.list(CancellationToken());

    ASSERT_TRUE(result);
    const std::vector<WorktreeInfo>& infos = result.value();
    ASSERT_EQ(infos.size(), 2u);

    EXPECT_TRUE(infos[0].isPrimary);
    EXPECT_TRUE(infos[0].isMain);
    EXPECT_FALSE(infos[1].isPrimary);
    EXPECT_FALSE(infos[1].isMain);
}

}  // namespace gbm
