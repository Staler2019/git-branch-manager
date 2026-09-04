// 建立於 for a linked worktree, read out of `<commonDir>/worktrees/<name>/logs/HEAD`.
//
// Everything asserted here was measured against git 2.55.0 before it was
// written, because the documented reflog format and the bytes git actually
// writes on the line we need are not the same shape:
//
//  * The documented entry is `<old> <new> <name> <email> <time> <tz>\t<msg>`.
//    **The first line `git worktree add` writes has no tab and no message
//    at all** -- it ends at the timezone. A parser that splits on the tab
//    first finds nothing on exactly the line this feature reads.
//  * `<name>` is a *human* name and may contain spaces, so the timestamp is
//    **not** at a fixed field index. With `user.name = "Jia Jyun Van Der
//    Berg"`, field 5 is the literal string `Van`. The timestamp and timezone
//    are the *last two* whitespace tokens, which is the only rule that holds
//    for both shapes.
//  * The time recorded is the `worktree add` time, not the tip commit's:
//    measured 5s apart on purpose (commit 1788359660, add 1788359665), and
//    the line carried the add time.
//  * `git worktree move` rewrites `gitdir` and leaves `logs/HEAD`
//    byte-identical, and **the admin directory keeps its original name** --
//    a worktree moved to `.../moved` still lives under `worktrees/linked/`.
//    That is why the admin directory is found by indexing every `gitdir`
//    file rather than by assuming `<name> == path.filename()`.
#include "core/base/FsUtil.h"
#include "core/git/ops/WorktreeOps.h"

#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>
#include <system_error>
#include <vector>

namespace gbm {
namespace {

class WorktreeCreatedAtTest : public ::testing::Test {
protected:
    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        root_ = std::filesystem::temp_directory_path() /
                ("gbm-test-WorktreeCreatedAt-" + std::string(info->name()));
        std::filesystem::remove_all(root_);
        std::filesystem::create_directories(root_ / "main" / ".git" / "worktrees");
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(root_, ec);
    }

    std::filesystem::path commonDir() const { return root_ / "main" / ".git"; }

    RepoPaths paths() const { return RepoPaths(root_ / "main", commonDir(), commonDir()); }

    /// Creates the administrative directory git writes for a linked worktree:
    /// a `gitdir` file pointing at `<workPath>/.git`, plus `logs/HEAD` when
    /// `reflog` is non-empty.
    ///
    /// `createWorkDir` defaults to **true** on purpose. With it false for every
    /// case, `fsutil::fileIdOf` is nullopt everywhere and every lookup falls to
    /// the string-key branch -- so the file-identity branch, which is the one
    /// that runs for every worktree that still exists, would be exercised by
    /// nothing. Deleting it then reddened five tests instead of one, which is
    /// how the gap was found: a broad mutation red means the fixture cannot
    /// tell the two paths apart.
    void makeAdminDir(const std::string& adminName,
                      const std::filesystem::path& workPath,
                      const std::string& reflog,
                      bool createWorkDir = true) {
        const std::filesystem::path admin = commonDir() / "worktrees" / adminName;
        std::filesystem::create_directories(admin);
        if (createWorkDir) {
            std::filesystem::create_directories(workPath);
        }
        std::ofstream(admin / "gitdir") << (workPath / ".git").string() << "\n";
        if (!reflog.empty()) {
            std::filesystem::create_directories(admin / "logs");
            std::ofstream(admin / "logs" / "HEAD") << reflog;
        }
    }

    std::vector<WorktreeInfo> attachFor(const std::filesystem::path& workPath) {
        WorktreeInfo info;
        info.path = workPath;
        info.branch = "side";
        std::vector<WorktreeInfo> worktrees{info};
        attachCreatedAt(paths(), worktrees);
        return worktrees;
    }

    std::filesystem::path root_;
};

TEST_F(WorktreeCreatedAtTest, TheFirstEntryIsTheCreationTimeAndALaterOneDoesNotOverrideIt) {
    // Byte-for-byte the shape git 2.55.0 wrote: no tab on line 1, a tab and a
    // message on the ones after it.
    makeAdminDir("linked",
                 root_ / "linked",
                 "0000000000000000000000000000000000000000 "
                 "ccd3a76638fb5556621115d60df0505f15ccc7cc T <t@e.invalid> 1788359665 +0800\n"
                 "ccd3a76638fb5556621115d60df0505f15ccc7cc "
                 "0918c72ae2bb613a6ae2f070bf70d8950541182f T <t@e.invalid> 1788999999 "
                 "+0800\tcommit: later\n");

    const std::vector<WorktreeInfo> got = attachFor(root_ / "linked");

    EXPECT_EQ(got[0].createdAtUnix, 1788359665)
        << "the newest reflog entry is when HEAD last moved, not when the "
           "worktree was created";
}

TEST_F(WorktreeCreatedAtTest, AnAuthorNameWithSpacesDoesNotShiftTheTimestamp) {
    // Measured: with this exact name, the fifth whitespace-separated field is
    // the literal string "Van". Only "the last two tokens" reads it correctly.
    makeAdminDir("linked",
                 root_ / "linked",
                 "0000000000000000000000000000000000000000 "
                 "ccd3a76638fb5556621115d60df0505f15ccc7cc "
                 "Jia Jyun Van Der Berg <x@y.com> 1788359688 +0800\n");

    const std::vector<WorktreeInfo> got = attachFor(root_ / "linked");

    EXPECT_EQ(got[0].createdAtUnix, 1788359688)
        << "a fixed field index reads \"Van\" here and reports absent";
}

TEST_F(WorktreeCreatedAtTest, AnEntryThatDoesCarryAMessageIsReadTheSameWay) {
    // The other shape, so the parser is pinned against both rather than
    // against whichever one the fixture happened to use.
    makeAdminDir("linked",
                 root_ / "linked",
                 "0000000000000000000000000000000000000000 "
                 "ccd3a76638fb5556621115d60df0505f15ccc7cc T <t@e.invalid> 1788359665 "
                 "+0800\tbranch: Created from HEAD\n");

    EXPECT_EQ(attachFor(root_ / "linked")[0].createdAtUnix, 1788359665);
}

TEST_F(WorktreeCreatedAtTest, AMovedWorktreeIsFoundThroughItsGitdirNotItsDirectoryName) {
    // `git worktree move` rewrites gitdir and keeps the admin directory's
    // original name. Assuming `<name> == path.filename()` reports absent here,
    // and this is the whole reason the lookup is an index over gitdir files.
    makeAdminDir("linked",
                 root_ / "moved",
                 "0000000000000000000000000000000000000000 "
                 "ccd3a76638fb5556621115d60df0505f15ccc7cc T <t@e.invalid> 1788359665 +0800\n");

    EXPECT_EQ(attachFor(root_ / "moved")[0].createdAtUnix, 1788359665);
}

TEST_F(WorktreeCreatedAtTest, ADirectoryThatIsTheSameByIdentityButNotByStringStillMatches) {
    // The trap parseEntry already records -- /var vs /private/var on macOS --
    // generalised so it exists on Linux too: git writes each worktree's
    // realpath into `gitdir`, and a path that reached us through a symlinked
    // *parent* names the same directory with different bytes.
    //
    // The symlink has to be an **intermediate** component, not the last one.
    // fsutil::fileIdOf is lstat (and FILE_FLAG_OPEN_REPARSE_POINT on Windows),
    // so it identifies a terminal symlink as itself -- deliberately, since it
    // is also the scanner's loop guard. lstat does follow the components
    // before the last, which is exactly why /var/.../linked and
    // /private/var/.../linked come out equal while their strings differ.
    std::error_code ec;
    std::filesystem::create_directories(root_ / "real");
    std::filesystem::create_directory_symlink(root_ / "real", root_ / "via", ec);
    if (ec) {
        GTEST_SKIP() << "symlink creation unavailable: " << ec.message();
    }
    makeAdminDir("linked",
                 root_ / "real" / "linked",
                 "0000000000000000000000000000000000000000 "
                 "ccd3a76638fb5556621115d60df0505f15ccc7cc T <t@e.invalid> 1788222222 +0800\n");

    const std::filesystem::path viaLink = root_ / "via" / "linked";
    ASSERT_NE(fsutil::canonicalKey(viaLink), fsutil::canonicalKey(root_ / "real" / "linked"))
        << "if the strings already agree, this case proves nothing";
    ASSERT_EQ(fsutil::fileIdOf(viaLink), fsutil::fileIdOf(root_ / "real" / "linked"))
        << "and if the identities disagree, it is testing the wrong mechanism";

    EXPECT_EQ(attachFor(viaLink)[0].createdAtUnix, 1788222222)
        << "a string compare reports absent here";
}

TEST_F(WorktreeCreatedAtTest, AWorktreeWhosePathIsGoneIsStillResolved) {
    // The only case that passes createWorkDir=false: a prunable worktree, whose
    // path is gone and its `.git` pointer with it. It has no file identity left
    // to compare, so this is the one case the string-key branch answers -- and
    // therefore the one that reddens if that branch is deleted.
    makeAdminDir("gone",
                 root_ / "gone",
                 "0000000000000000000000000000000000000000 "
                 "ccd3a76638fb5556621115d60df0505f15ccc7cc T <t@e.invalid> 1788111111 +0800\n",
                 /*createWorkDir=*/false);
    ASSERT_FALSE(std::filesystem::exists(root_ / "gone"));

    EXPECT_EQ(attachFor(root_ / "gone")[0].createdAtUnix, 1788111111)
        << "reading <path>/.git cannot answer this, and it is the commonest "
           "case in which the panel still has a row to draw";
}

TEST_F(WorktreeCreatedAtTest, NoLogsHeadIsAbsentRatherThanNowOrADirectoryMtime) {
    makeAdminDir("linked", root_ / "linked", /*reflog=*/"");

    EXPECT_EQ(attachFor(root_ / "linked")[0].createdAtUnix, 0)
        << "core.logAllRefUpdates can be off; absent beats approximately "
           "right, and a directory mtime would be a second source that can "
           "silently disagree";
}

TEST_F(WorktreeCreatedAtTest, TheCurrentWorktreeHasNoAdminDirectoryAndIsAbsent) {
    // The main/current worktree's own logs/HEAD holds this repository's first
    // checkout, which is a different fact under the same label.
    EXPECT_EQ(attachFor(root_ / "main")[0].createdAtUnix, 0);
}

TEST_F(WorktreeCreatedAtTest, AGarbageFirstLineIsAbsentRatherThanZeroOrPartial) {
    makeAdminDir("linked", root_ / "linked", "not a reflog line at all\n");

    EXPECT_EQ(attachFor(root_ / "linked")[0].createdAtUnix, 0);
}

}  // namespace
}  // namespace gbm
