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

/// Index differs from HEAD: `git diff --cached --quiet` exits 1.
void scriptStagedChanges(FakeProcessRunner& runner) {
    runner.whenArgsContain({"diff", "--cached", "--quiet"}, exitWith(1));
}

TEST(MergeOperationSquash, CommitsWithTheMessageOverStdin) {
    FakeProcessRunner runner;
    scriptStagedChanges(runner);

    OperationOutcome outcome =
        makeMergeOperation(squash(kMessage))->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded) << outcome.summary;
    ASSERT_EQ(runner.invocations().size(), 3u);
    const std::vector<std::string> commit = runner.invokedArgs(2);
    ASSERT_FALSE(commit.empty());
    EXPECT_EQ(commit.front(), "commit");
    EXPECT_TRUE(contains(commit, "--file"));
    EXPECT_TRUE(contains(commit, "-"));
    EXPECT_FALSE(contains(commit, "-m"));
    EXPECT_FALSE(contains(commit, kMessage));
    EXPECT_EQ(runner.invocations()[2].stdinData.value_or(""), kMessage);
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
    EXPECT_EQ(runner.invocations().size(), 3u);
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
    EXPECT_EQ(runner.invocations().size(), 2u);
}

TEST(MergeOperationSquash, AConflictNeverCommits) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"merge", "--squash"},
                           exitWith(1, "CONFLICT (content): Merge conflict in f.txt\n"));

    OperationOutcome outcome =
        makeMergeOperation(squash(kMessage))->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    EXPECT_EQ(runner.invocations().size(), 1u);
}

TEST(MergeOperationSquash, NoMessageStillOnlyStages) {
    FakeProcessRunner runner;

    OperationOutcome outcome =
        makeMergeOperation(squash(""))->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    EXPECT_EQ(runner.invocations().size(), 1u);
}

}  // namespace
}  // namespace gbm
