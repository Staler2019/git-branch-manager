// Pins GitCommand::worktreeReadFlags() onto the two background reads that
// compare the work tree against the index.
//
// These are argv assertions, not a race reproduction, and that is deliberate.
// The regression they guard (see GitCommand::worktreeReadFlags()' own comment)
// only fires on a machine with `core.fsmonitor=true`, is absent on CI, and is
// suppressed by every observation technique tried -- GIT_TRACE2_EVENT, an exec
// shim, even a shim doing a single write(). A test that tried to catch the
// LockHeld failure itself would be green everywhere for the wrong reason. What
// *is* checkable everywhere is that the flags are on the command at all, which
// is the thing a later refactor would silently drop.
#include "core/git/DiffService.h"
#include "core/git/WorkingCopyStatus.h"
#include "support/FakeProcessRunner.h"

#include <algorithm>
#include <gtest/gtest.h>
#include <string>
#include <vector>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

RepoPaths testPaths() {
    return RepoPaths("/repo", "/repo/.git", "/repo/.git");
}

/// One modified tracked file, so the numstat passes have an entry to attach to
/// -- attachNumstat() returns early on an empty list, and a reader that never
/// runs the command would pass an assertion about the command's flags for the
/// wrong reason.
FakeProcessRunner::Response statusWithOneModifiedFile() {
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    response.out = std::string("1 .M N... 100644 100644 100644 ") +
                   "1111111111111111111111111111111111111111 "
                   "1111111111111111111111111111111111111111 f.txt";
    response.out.push_back('\0');
    return response;
}

bool carriesNoFsmonitor(const std::vector<std::string>& args) {
    for (std::size_t i = 0; i + 1 < args.size(); ++i) {
        if (args[i] == "-c" && args[i + 1] == "core.fsmonitor=false") {
            return true;
        }
    }
    return false;
}

/// The argv of the one invocation whose args contain every token in `tokens`
/// and none in `absent`. Fails the test rather than returning a wrong match:
/// picking the staged pass while meaning the unstaged one is exactly the
/// mistake these tests exist to catch.
std::vector<std::string> soleInvocationWith(const FakeProcessRunner& runner,
                                            const std::vector<std::string>& tokens,
                                            const std::vector<std::string>& absent) {
    std::vector<std::string> found;
    std::size_t matches = 0;
    for (std::size_t i = 0; i < runner.invocationCount(); ++i) {
        const std::vector<std::string> args = runner.invokedArgs(i);
        const auto has = [&args](const std::string& token) {
            return std::find(args.begin(), args.end(), token) != args.end();
        };
        if (std::all_of(tokens.begin(), tokens.end(), has) &&
            std::none_of(absent.begin(), absent.end(), has)) {
            ++matches;
            found = args;
        }
    }
    EXPECT_EQ(matches, 1u) << "expected exactly one matching invocation";
    return found;
}

TEST(WorktreeReadFlags, UnstagedNumstatPassCarriesThem) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, statusWithOneModifiedFile());

    WorkingCopyStatusReader reader(runner, testPaths());
    ASSERT_TRUE(reader.read(CancellationToken{}));

    EXPECT_TRUE(
        carriesNoFsmonitor(soleInvocationWith(runner, {"diff", "--numstat"}, {"--cached"})));
}

TEST(WorktreeReadFlags, StagedNumstatPassDoesNotPayForThem) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, statusWithOneModifiedFile());

    WorkingCopyStatusReader reader(runner, testPaths());
    ASSERT_TRUE(reader.read(CancellationToken{}));

    EXPECT_FALSE(
        carriesNoFsmonitor(soleInvocationWith(runner, {"diff", "--numstat", "--cached"}, {})));
}

TEST(WorktreeReadFlags, StatusReadItselfDoesNotPayForThem) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, statusWithOneModifiedFile());

    WorkingCopyStatusReader reader(runner, testPaths());
    ASSERT_TRUE(reader.read(CancellationToken{}));

    EXPECT_FALSE(carriesNoFsmonitor(soleInvocationWith(runner, {"status"}, {})));
}

TEST(WorktreeReadFlags, UnstagedWorkingTreeDiffCarriesThem) {
    FakeProcessRunner runner;
    DiffService diffs(runner, testPaths());
    ASSERT_TRUE(
        diffs.workingTreeDiff(/*staged=*/false, {"f.txt"}, DiffOptions{}, CancellationToken{}));

    EXPECT_TRUE(carriesNoFsmonitor(soleInvocationWith(runner, {"diff"}, {"--cached"})));
}

TEST(WorktreeReadFlags, StagedWorkingTreeDiffDoesNotPayForThem) {
    FakeProcessRunner runner;
    DiffService diffs(runner, testPaths());
    ASSERT_TRUE(
        diffs.workingTreeDiff(/*staged=*/true, {"f.txt"}, DiffOptions{}, CancellationToken{}));

    EXPECT_FALSE(carriesNoFsmonitor(soleInvocationWith(runner, {"diff", "--cached"}, {})));
}

}  // namespace
}  // namespace gbm
