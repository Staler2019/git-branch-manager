// Which open session an operation-log record is delivered to. gbm::Log's sink
// is process-wide and knows nothing of sessions, so Session fans each record
// out by the directory its git command ran in -- and a record that no session
// claims is never shown. These are the claims it has to make, and the one it
// must refuse.
#include "core/git/OperationLogScope.h"

#include <filesystem>
#include <gtest/gtest.h>
#include <string>
#include <vector>

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

}  // namespace
}  // namespace gbm
