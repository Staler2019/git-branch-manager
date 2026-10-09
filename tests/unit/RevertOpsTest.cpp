// `git revert` decides on its own whether to open an editor: it does so
// whenever it thinks it was run from a terminal. On Windows the app handed
// git its own stdin, git took that for a terminal, and a revert opened the
// editor Git for Windows' installer configured (VS Code) -- 使用者回報
// 2026-10-08. `--no-edit` makes the default "Revert "<subject>"" message
// unconditional, the same way MergeOps' --no-ff path already does.
#include "core/git/ops/RevertOps.h"
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

const std::string kOid = "0123456789abcdef0123456789abcdef01234567";

std::vector<std::string> revertArgs(const FakeProcessRunner& runner) {
    for (std::size_t i = 0; i < runner.invocations().size(); ++i) {
        std::vector<std::string> args = runner.invokedArgs(i);
        if (!args.empty() && args.front() == "revert") return args;
    }
    return {};
}

bool contains(const std::vector<std::string>& args, const std::string& token) {
    return std::find(args.begin(), args.end(), token) != args.end();
}

TEST(RevertOperation, NeverAsksGitToOpenAnEditor) {
    FakeProcessRunner runner;
    RevertRequest request;
    request.commits = {ObjectId::fromHex(kOid)};

    makeRevertOperation(request)->run(runner, testPaths(), CancellationToken{});

    const std::vector<std::string> args = revertArgs(runner);
    ASSERT_FALSE(args.empty());
    EXPECT_TRUE(contains(args, "--no-edit"));
    EXPECT_TRUE(contains(args, kOid));
}

TEST(RevertOperation, NoCommitNeedsNoMessageFlag) {
    // --no-commit writes no commit, so there is no message to edit either.
    FakeProcessRunner runner;
    RevertRequest request;
    request.commits = {ObjectId::fromHex(kOid)};
    request.noCommit = true;

    makeRevertOperation(request)->run(runner, testPaths(), CancellationToken{});

    const std::vector<std::string> args = revertArgs(runner);
    ASSERT_FALSE(args.empty());
    EXPECT_TRUE(contains(args, "--no-commit"));
    EXPECT_FALSE(contains(args, "--no-edit"));
}

}  // namespace
}  // namespace gbm
