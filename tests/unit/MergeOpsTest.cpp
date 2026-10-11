// MergeOperation's squash path (merge-rebase-dialogs-spec.html 02-C). With a
// message, a squash that lands without conflict is committed with it (使用者
// 裁定 2026-10-08：「merge沒conflict才可以直接commit」); the message goes over
// stdin, as CommitOps' does, because a SQUASH_MSG lists every commit's full
// body and can outgrow an argv entry.
#include "core/git/ops/MergeOps.h"
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

const std::string kMessage =
    "Squashed commit of the following:\n\ncommit 0123\nAuthor: T <t@t>\n\n    Add g\n";

FakeProcessRunner::Response exitWith(int code, std::string err = {}) {
    FakeProcessRunner::Response response;
    response.exitCode = code;
    response.err = std::move(err);
    return response;
}

MergeRequest squash(std::string message) {
    MergeRequest request;
    request.target = "feature";
    request.mode = MergeMode::Squash;
    request.message = std::move(message);
    return request;
}

bool contains(const std::vector<std::string>& args, const std::string& token) {
    return std::find(args.begin(), args.end(), token) != args.end();
}

/// `git diff --cached --quiet` is asked twice: before the squash (exit 0, the
/// index matched HEAD -- nothing of the user's is staged) and after it (exit
/// 1, the squash staged something).
void scriptStagedChanges(FakeProcessRunner& runner) {
    runner.whenArgsContainInTurn({"diff", "--cached", "--quiet"}, {exitWith(0), exitWith(1)});
}

TEST(MergeOperationSquash, CommitsWithTheMessageOverStdin) {
    FakeProcessRunner runner;
    scriptStagedChanges(runner);

    OperationOutcome outcome =
        makeMergeOperation(squash(kMessage))->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded) << outcome.summary;
    ASSERT_EQ(runner.invocations().size(), 4u);
    const std::vector<std::string> commit = runner.invokedArgs(3);
    ASSERT_FALSE(commit.empty());
    EXPECT_EQ(commit.front(), "commit");
    EXPECT_TRUE(contains(commit, "--file"));
    EXPECT_TRUE(contains(commit, "-"));
    EXPECT_FALSE(contains(commit, "-m"));
    EXPECT_FALSE(contains(commit, kMessage));
    EXPECT_EQ(runner.invocations()[3].stdinData.value_or(""), kMessage);
}

TEST(MergeOperationSquash, AFailedCommitSaysTheChangesAreStaged) {
    // A hook, a gpg failure: the squash itself landed, HEAD did not move.
    FakeProcessRunner runner;
    scriptStagedChanges(runner);
    runner.whenArgsContain({"commit"}, exitWith(1, "error: commit-msg hook rejected\n"));

    OperationOutcome outcome =
        makeMergeOperation(squash(kMessage))->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    EXPECT_TRUE(outcome.error.has_value());
    EXPECT_NE(outcome.summary.find("staged"), std::string::npos) << outcome.summary;
    EXPECT_EQ(runner.invocations().size(), 4u);
}

TEST(MergeOperationSquash, NothingStagedMeansNoCommit) {
    // Source already contained in HEAD: git says "Already up to date" and
    // stages nothing; a commit would only fail with "nothing to commit".
    FakeProcessRunner runner;
    runner.whenArgsContain({"diff", "--cached", "--quiet"}, exitWith(0));

    OperationOutcome outcome =
        makeMergeOperation(squash(kMessage))->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    EXPECT_NE(outcome.summary.find("up to date"), std::string::npos) << outcome.summary;
    EXPECT_EQ(runner.invocations().size(), 3u);
}

TEST(MergeOperationSquash, AlreadyStagedWorkIsNeverCommittedWithTheSquash) {
    // A fast-forward squash keeps whatever the user had staged, and `git
    // commit` would fold it into a commit whose message lists only the
    // source's commits. So: squash, stage, and stop -- the pre-2026-10-08
    // behaviour, for exactly this case.
    FakeProcessRunner runner;
    runner.whenArgsContain({"diff", "--cached", "--quiet"}, exitWith(1));

    OperationOutcome outcome =
        makeMergeOperation(squash(kMessage))->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded) << outcome.summary;
    EXPECT_NE(outcome.summary.find("not committed"), std::string::npos) << outcome.summary;
    for (std::size_t i = 0; i < runner.invocations().size(); ++i) {
        EXPECT_NE(runner.invokedArgs(i).front(), "commit") << "invocation " << i;
    }
    ASSERT_EQ(runner.invocations().size(), 2u);
    EXPECT_TRUE(contains(runner.invokedArgs(1), "--squash"));
}

TEST(MergeOperationSquash, AConflictNeverCommits) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"merge", "--squash"},
                           exitWith(1, "CONFLICT (content): Merge conflict in f.txt\n"));

    OperationOutcome outcome =
        makeMergeOperation(squash(kMessage))->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    EXPECT_EQ(runner.invocations().size(), 2u);
}

TEST(MergeOperationSquash, NoMessageStillOnlyStages) {
    FakeProcessRunner runner;

    OperationOutcome outcome =
        makeMergeOperation(squash(""))->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    EXPECT_EQ(runner.invocations().size(), 1u);
}

// The dialogs hand git the full ref so a same-named tag cannot win; what
// the app itself writes for people -- the undo list, the summary, the stash
// entry -- still names the branch the way they picked it.
TEST(MergeOperationText, NamesTheBranchButHandsGitTheFullRef) {
    FakeProcessRunner runner;
    MergeRequest request;
    request.target = "refs/heads/feature";
    request.mode = MergeMode::NoFastForward;
    request.message = "Merge branch 'feature'";
    request.stashFirst = true;
    auto operation = makeMergeOperation(request);

    EXPECT_EQ(operation->describe(), "Merge feature");
    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_EQ(outcome.summary, "Merged feature");
    ASSERT_EQ(runner.invocations().size(), 2u);
    EXPECT_TRUE(contains(runner.invokedArgs(0), "git-branch-manager: before merging feature"));
    EXPECT_TRUE(contains(runner.invokedArgs(1), "refs/heads/feature")) << "git gets the full ref";
}

TEST(MergeOperationText, NamesARemoteBranchByItsRemoteName) {
    FakeProcessRunner runner;
    MergeRequest request = squash("");
    request.target = "refs/remotes/origin/feat";
    auto operation = makeMergeOperation(request);

    EXPECT_EQ(operation->describe(), "Squash merge origin/feat");
}

TEST(MergeOperationText, LeavesACommitOidAsItIs) {
    MergeRequest request;
    request.target = "0123456789abcdef0123456789abcdef01234567";
    EXPECT_EQ(makeMergeOperation(request)->describe(),
              "Merge 0123456789abcdef0123456789abcdef01234567");
}

}  // namespace
}  // namespace gbm
