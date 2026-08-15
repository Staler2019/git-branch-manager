// Tests for the M6 prune addition to RemoteOps: RemoteStore::prunePreview (a
// read-only "git remote prune --dry-run" query) and PruneRemoteOperation
// (the real delete, scoped to an explicit ref list rather than "prune
// everything stale" -- see RemoteOps.h's doc comment on why).
#include "core/git/ops/RemoteOps.h"
#include "support/FakeProcessRunner.h"

#include <gtest/gtest.h>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

RepoPaths testPaths() {
    return RepoPaths("/repo", "/repo/.git", "/repo/.git");
}

TEST(RemoteStorePrunePreview, ParsesWouldPruneLinesFromDryRunOutput) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    response.out =
        "Pruning origin\n"
        "URL: git@github.com:example/repo.git\n"
        " * [would prune] origin/feature/old-branch\n"
        " * [would prune] origin/another-stale-one\n";
    runner.whenArgsContain({"remote", "prune", "origin", "--dry-run"}, response);

    RemoteStore store(runner, testPaths());
    GitResult<std::vector<RemotePrunePreviewEntry>> result =
        store.prunePreview("origin", CancellationToken{});

    ASSERT_TRUE(result);
    ASSERT_EQ(result->size(), 2u);
    EXPECT_EQ((*result)[0].ref, "origin/feature/old-branch");
    EXPECT_EQ((*result)[1].ref, "origin/another-stale-one");
}

TEST(RemoteStorePrunePreview, ReturnsEmptyListWhenNothingIsStale) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    response.out = "Pruning origin\nURL: git@github.com:example/repo.git\n";
    runner.whenArgsContain({"remote", "prune", "origin", "--dry-run"}, response);

    RemoteStore store(runner, testPaths());
    GitResult<std::vector<RemotePrunePreviewEntry>> result =
        store.prunePreview("origin", CancellationToken{});

    ASSERT_TRUE(result);
    EXPECT_TRUE(result->empty());
}

TEST(RemoteStorePrunePreview, FailsCleanlyWithNoRemoteSelected) {
    FakeProcessRunner runner;
    RemoteStore store(runner, testPaths());
    GitResult<std::vector<RemotePrunePreviewEntry>> result =
        store.prunePreview("", CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(PruneRemoteOperation, DeletesExactlyTheGivenRefsViaBranchDeleteRemotes) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    response.out = "Deleted remote-tracking branch origin/feature/old-branch (was abc1234).\n";
    runner.whenArgsContain({"branch", "--delete", "--remotes", "origin/feature/old-branch"},
                           response);

    PruneRemoteRequest request;
    request.remoteName = "origin";
    request.refs = {"origin/feature/old-branch"};
    auto operation = makePruneRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0),
             (std::vector<std::string>{
                 "branch", "--delete", "--remotes", "origin/feature/old-branch"}));
}

TEST(PruneRemoteOperation, DeletesMultipleSelectedRefsInOneCall) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain(
        {"branch", "--delete", "--remotes", "origin/a", "origin/b"}, response);

    PruneRemoteRequest request;
    request.remoteName = "origin";
    request.refs = {"origin/a", "origin/b"};
    auto operation = makePruneRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    ASSERT_EQ(runner.invocationCount(), 1u);
}

TEST(PruneRemoteOperation, DoesNothingWhenNoRefsAreSelected) {
    FakeProcessRunner runner;
    PruneRemoteRequest request;
    request.remoteName = "origin";
    auto operation = makePruneRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(PruneRemoteOperation, ReportsGitErrorOnFailure) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response failure;
    failure.exitCode = 1;
    failure.err = "error: branch 'origin/feature/old-branch' not found.\n";
    runner.whenArgsContain({"branch", "--delete", "--remotes", "origin/feature/old-branch"},
                           failure);

    PruneRemoteRequest request;
    request.remoteName = "origin";
    request.refs = {"origin/feature/old-branch"};
    auto operation = makePruneRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
}

}  // namespace
}  // namespace gbm
