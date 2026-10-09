// RebaseOperation's own text. The Rebase dialog hands git the full ref
// (refs/heads/<name>) so a same-named tag cannot be the base; the undo list
// and the summary still name the branch the way the user picked it.
#include "core/git/ops/RebaseOps.h"
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

TEST(RebaseOperationText, NamesTheBranchButHandsGitTheFullRef) {
    FakeProcessRunner runner;
    RebaseRequest request;
    request.upstream = "refs/heads/main";
    auto operation = makeRebaseOperation(request);

    EXPECT_EQ(operation->describe(), "Rebase onto main");
    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_EQ(outcome.summary, "Rebased onto main");
    const std::vector<std::string> args = runner.invokedArgs(runner.invocations().size() - 1);
    EXPECT_NE(std::find(args.begin(), args.end(), "refs/heads/main"), args.end())
        << "git gets the full ref";
}

TEST(RebaseOperationText, NamesARemoteBranchByItsRemoteName) {
    RebaseRequest request;
    request.upstream = "refs/remotes/origin/main";
    EXPECT_EQ(makeRebaseOperation(request)->describe(), "Rebase onto origin/main");
}

}  // namespace
}  // namespace gbm
