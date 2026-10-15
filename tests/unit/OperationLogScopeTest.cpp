// Which open session an operation-log record is delivered to. gbm::Log's sink
// is process-wide and knows nothing of sessions, so Session fans each record
// out by the directory its git command ran in -- and a record that no session
// claims is never shown. These are the claims it has to make, and the one it
// must refuse.
#include "core/base/FsUtil.h"
#include "core/git/OperationLogScope.h"

#include <filesystem>
#include <gtest/gtest.h>
#include <string>
#include <system_error>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#endif

namespace gbm {
namespace {

const std::vector<std::filesystem::path> kSession{
    std::filesystem::path("/work/repo"),
    std::filesystem::path("/work/repo/.git"),
    std::filesystem::path("/work/linked"),
};

TEST(OperationLogScope, TheSessionsOwnWorkTreeIsClaimed) {
    EXPECT_TRUE(recordBelongsToSession("/work/repo", kSession));
}

// attachPendingCounts runs `git status` in every linked worktree; those
// records used to be dropped because only the work tree was compared.
TEST(OperationLogScope, ALinkedWorktreeOfTheSessionIsClaimed) {
    EXPECT_TRUE(recordBelongsToSession("/work/linked", kSession));
}

TEST(OperationLogScope, ATrailingSeparatorDoesNotMakeItAnotherDirectory) {
    EXPECT_TRUE(recordBelongsToSession("/work/repo/", kSession));
}

// clone, init and the git-version probe run with no directory, and clone's
// argv carries the URL -- possibly with a token in it. Such a record belongs to
// no session, so it is never shown in any repository's log.
TEST(OperationLogScope, ARecordWithNoDirectoryIsNeverClaimed) {
    EXPECT_FALSE(recordBelongsToSession("", kSession));
    // Even by a session holding an empty directory -- a bare repository's
    // work tree is one -- or "" would equal "" and the clone record would
    // reach it.
    const std::vector<std::filesystem::path> withEmpty{std::filesystem::path(),
                                                       std::filesystem::path("/work/bare.git")};
    EXPECT_FALSE(recordBelongsToSession("", withEmpty));
}

TEST(OperationLogScope, AnotherRepositoryIsNotClaimed) {
    EXPECT_FALSE(recordBelongsToSession("/work/other", kSession));
    EXPECT_FALSE(recordBelongsToSession("/work/repository", kSession));
}

// The record's directory is UTF-8 (utf8FromPath), so a Chinese worktree path
// has to compare equal to the same path the session holds.
TEST(OperationLogScope, AChineseLinkedWorktreePathIsClaimed) {
    const std::vector<std::filesystem::path> session{
        std::filesystem::path(u8"/work/測試"),
        std::filesystem::path(u8"/work/工作樹"),
    };
    EXPECT_TRUE(recordBelongsToSession("/work/\xE5\xB7\xA5\xE4\xBD\x9C\xE6\xA8\xB9", session));
}

// One directory, two spellings: git lists a worktree by its resolved path,
// while a session holds whatever path it was opened with. These need real
// directories, since only the filesystem knows the two name one place.
class OperationLogScopeOnDisk : public ::testing::Test {
protected:
    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        root_ =
            std::filesystem::temp_directory_path() / ("gbm-log-scope-" + std::string(info->name()));
        std::filesystem::remove_all(root_);
        std::filesystem::create_directories(root_ / "real directory" / "repo");
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(root_, ec);
    }

    std::filesystem::path root_;
};

// macOS's temp dir is /var/..., a symlink to /private/var/...: the record
// says one, `git worktree list` the other. The symlink is an intermediate
// component, the only shape that occurs there.
TEST_F(OperationLogScopeOnDisk, ADirectoryReachedThroughASymlinkedParentIsClaimed) {
    std::error_code ec;
    std::filesystem::create_directory_symlink(root_ / "real directory", root_ / "via", ec);
    if (ec) {
        GTEST_SKIP() << "symlink creation unavailable: " << ec.message();
    }
    const std::filesystem::path real = root_ / "real directory" / "repo";
    const std::filesystem::path viaLink = root_ / "via" / "repo";
    ASSERT_NE(fsutil::canonicalKey(viaLink), fsutil::canonicalKey(real))
        << "if the strings already agree, this case proves nothing";

    const std::vector<std::filesystem::path> session{real};
    EXPECT_TRUE(recordBelongsToSession(fsutil::utf8FromPath(viaLink), session));
    const std::vector<std::filesystem::path> sessionViaLink{viaLink};
    EXPECT_TRUE(recordBelongsToSession(fsutil::utf8FromPath(real), sessionViaLink));
}

// A repository opened through a link to the repository itself: the session
// holds the link, git runs and reports in the target.
TEST_F(OperationLogScopeOnDisk, ARepositoryOpenedThroughALinkToItIsClaimed) {
    std::error_code ec;
    std::filesystem::create_directory_symlink(
        root_ / "real directory" / "repo", root_ / "linked-repo", ec);
    if (ec) {
        GTEST_SKIP() << "symlink creation unavailable: " << ec.message();
    }
    const std::filesystem::path real = root_ / "real directory" / "repo";
    const std::filesystem::path link = root_ / "linked-repo";

    const std::vector<std::filesystem::path> sessionViaLink{link};
    EXPECT_TRUE(recordBelongsToSession(fsutil::utf8FromPath(real), sessionViaLink));
    const std::vector<std::filesystem::path> session{real};
    EXPECT_TRUE(recordBelongsToSession(fsutil::utf8FromPath(link), session));
}

// A different directory that exists is still another directory.
TEST_F(OperationLogScopeOnDisk, AnotherExistingDirectoryIsNotClaimed) {
    std::filesystem::create_directories(root_ / "other");
    const std::vector<std::filesystem::path> session{root_ / "real directory" / "repo"};
    EXPECT_FALSE(recordBelongsToSession(fsutil::utf8FromPath(root_ / "other"), session));
}

#ifdef _WIN32
// The Windows runner's temp dir is C:/Users/RUNNER~1/...: an 8.3 alias of the
// long name git reports.
TEST_F(OperationLogScopeOnDisk, AnEightDotThreeAliasIsClaimed) {
    const std::filesystem::path real = root_ / "real directory" / "repo";
    wchar_t buffer[MAX_PATH * 4];
    const DWORD length = ::GetShortPathNameW(real.c_str(), buffer, MAX_PATH * 4);
    if (length == 0 || length >= MAX_PATH * 4) {
        GTEST_SKIP() << "no short name available";
    }
    const std::filesystem::path shortName(std::wstring(buffer, length));
    if (fsutil::canonicalKey(shortName) == fsutil::canonicalKey(real)) {
        GTEST_SKIP() << "8.3 names are disabled on this volume";
    }

    const std::vector<std::filesystem::path> session{real};
    EXPECT_TRUE(recordBelongsToSession(fsutil::utf8FromPath(shortName), session));
}
#endif

}  // namespace
}  // namespace gbm
