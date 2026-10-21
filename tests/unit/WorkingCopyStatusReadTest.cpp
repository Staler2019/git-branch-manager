// What one working-copy read publishes when the line-count passes fail.
//
// The conflict list -- and so, for a plain merge, `conflictActive` itself --
// comes only from this read. When either `git diff --numstat` pass failed the
// whole read used to fail with it, so on a machine slow enough for numstat's
// rename detection to time out, a merge's conflicts simply never appeared.
// Line counts are badges; conflicts are material state. Only the badges may be
// lost.
#include "core/git/WorkingCopyStatus.h"
#include "support/FakeProcessRunner.h"

#include <algorithm>
#include <gtest/gtest.h>
#include <string>
#include <vector>

namespace gbm {
namespace {

using ::gbm::testing::FakeProcessRunner;

/// `git status --porcelain=v2 -z` with one conflicted path (both modified).
FakeProcessRunner::Response conflictedStatus() {
    FakeProcessRunner::Response response;
    const std::string zeros(40, '0');
    response.out = "u UU N... 100644 100644 100644 100644 " + zeros + " " + zeros + " " + zeros +
                   " shared.txt";
    response.out.push_back('\0');
    return response;
}

FakeProcessRunner::Response timedOut() {
    FakeProcessRunner::Response response;
    response.timedOut = true;
    return response;
}

FakeProcessRunner::Response cancelledRun() {
    FakeProcessRunner::Response response;
    response.cancelled = true;
    return response;
}

const RepoPaths kPaths{"/no/such/repo", "/no/such/repo/.git", ""};

TEST(WorkingCopyStatusRead, ANumstatTimeoutStillPublishesTheConflicts) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, conflictedStatus());
    runner.whenArgsContain({"diff", "--numstat"}, timedOut());
    WorkingCopyStatusReader reader(runner, kPaths);

    const auto result = reader.read(CancellationToken());

    ASSERT_TRUE(result) << result.error().message;
    EXPECT_EQ(result.value()->conflicted().size(), 1u);
    EXPECT_TRUE(result.value()->lineCountsUnavailable);
}

TEST(WorkingCopyStatusRead, CountsThatArrivedAreNotMarkedUnavailable) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, conflictedStatus());
    WorkingCopyStatusReader reader(runner, kPaths);

    const auto result = reader.read(CancellationToken());

    ASSERT_TRUE(result);
    EXPECT_FALSE(result.value()->lineCountsUnavailable);
}

// A cancelled read is abandoned work, not a slow one: publishing it would
// replace real badges with zeros and flash "unavailable" on every repository
// switch, for counts that were never actually out of reach.
TEST(WorkingCopyStatusRead, ACancelledNumstatStillFailsTheRead) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, conflictedStatus());
    runner.whenArgsContain({"diff", "--numstat"}, cancelledRun());
    WorkingCopyStatusReader reader(runner, kPaths);

    const auto result = reader.read(CancellationToken());

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::Cancelled);
}

TEST(WorkingCopyStatusRead, AFailedStatusStillFailsTheRead) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, timedOut());
    WorkingCopyStatusReader reader(runner, kPaths);

    const auto result = reader.read(CancellationToken());

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::Timeout);
}

// `--untracked-files=all` walks every directory of the work tree even when
// nothing is untracked: 450-710 ms on microsoft/vscode against 30 ms for
// `=normal` (使用者裁定 2026-10-21: 「先 normal，有目錄才展開」). `=normal`
// collapses an untracked directory to one `dir/` record; only those are
// expanded, with one `ls-files --others` over exactly them.
FakeProcessRunner::Response statusRecords(const std::vector<std::string>& records) {
    FakeProcessRunner::Response response;
    for (const std::string& record : records) {
        response.out += record;
        response.out.push_back('\0');
    }
    return response;
}

std::vector<std::vector<std::string>> argsOf(const FakeProcessRunner& runner,
                                             const std::string& subcommand) {
    std::vector<std::vector<std::string>> out;
    for (std::size_t i = 0; i < runner.invocationCount(); ++i) {
        const std::vector<std::string> args = runner.invokedArgs(i);
        if (std::find(args.begin(), args.end(), subcommand) != args.end()) {
            out.push_back(args);
        }
    }
    return out;
}

TEST(WorkingCopyStatusRead, StatusAsksForNormalUntrackedModeNotAll) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, statusRecords({"? top.txt"}));
    WorkingCopyStatusReader reader(runner, kPaths);

    ASSERT_TRUE(reader.read(CancellationToken()));

    const auto status = argsOf(runner, "status");
    ASSERT_EQ(status.size(), 1u);
    EXPECT_NE(std::find(status[0].begin(), status[0].end(), "--untracked-files=normal"),
              status[0].end());
    EXPECT_EQ(std::find(status[0].begin(), status[0].end(), "--untracked-files=all"),
              status[0].end());
    EXPECT_TRUE(argsOf(runner, "ls-files").empty())
        << "no untracked directory, so nothing to expand";
}

TEST(WorkingCopyStatusRead, OnlyUntrackedDirectoriesAreExpandedInOneLsFiles) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"},
                           statusRecords({"? top.txt", "? u/", "? nest/"}));
    FakeProcessRunner::Response expanded = statusRecords({"nest/", "u/v/y", "u/x"});
    runner.whenArgsContain({"ls-files", "--others"}, expanded);
    WorkingCopyStatusReader reader(runner, kPaths);

    const auto result = reader.read(CancellationToken());
    ASSERT_TRUE(result) << result.error().message;

    const auto lsFiles = argsOf(runner, "ls-files");
    ASSERT_EQ(lsFiles.size(), 1u);
    const std::vector<std::string>& args = lsFiles[0];
    const auto dashes = std::find(args.begin(), args.end(), "--");
    ASSERT_NE(dashes, args.end());
    EXPECT_EQ(std::vector<std::string>(dashes + 1, args.end()),
              (std::vector<std::string>{":(literal)u/", ":(literal)nest/"}))
        << "literal, so a directory named like a glob (g[1]/) is not a pattern";

    std::vector<std::string> untracked;
    for (const WorkingCopyEntry* entry : result.value()->untracked()) {
        untracked.push_back(entry->path);
    }
    std::sort(untracked.begin(), untracked.end());
    EXPECT_EQ(untracked, (std::vector<std::string>{"nest/", "top.txt", "u/v/y", "u/x"}));
}

}  // namespace
}  // namespace gbm
