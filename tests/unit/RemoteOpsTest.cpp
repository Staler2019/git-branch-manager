// Tests for the M6 prune addition to RemoteOps: RemoteStore::prunePreview (a
// read-only "git remote prune --dry-run" query) and PruneRemoteOperation
// (the real delete, scoped to an explicit ref list rather than "prune
// everything stale" -- see RemoteOps.h's doc comment on why).
#include "core/git/ops/RemoteOps.h"
#include "support/FakeProcessRunner.h"

#include <gtest/gtest.h>
#include <memory>
#include <optional>
#include <string>

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

TEST(FetchOperation, FetchesEveryRemoteWhenNoRemoteNameIsGiven) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"fetch", "--all"}, response);

    FetchRequest request;
    auto operation = makeFetchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    EXPECT_EQ(runner.invokedArgs(0), (std::vector<std::string>{"fetch", "--all"}));
}

TEST(FetchOperation, FetchesJustTheGivenRemoteWhenRefsIsEmpty) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"fetch", "origin"}, response);

    FetchRequest request;
    request.remoteName = "origin";
    auto operation = makeFetchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    EXPECT_EQ(runner.invokedArgs(0), (std::vector<std::string>{"fetch", "origin"}));
}

TEST(FetchOperation, FetchesExactlyTheGivenRefsFromTheRemote) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"fetch", "origin", "feature/one", "feature/two"}, response);

    FetchRequest request;
    request.remoteName = "origin";
    request.refs = {"feature/one", "feature/two"};
    auto operation = makeFetchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0),
             (std::vector<std::string>{"fetch", "origin", "feature/one", "feature/two"}));
}

TEST(FetchOperation, PruneAndTagsStillApplyWithSpecificRefs) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"fetch", "--prune", "--tags", "origin", "feature/one"}, response);

    FetchRequest request;
    request.remoteName = "origin";
    request.refs = {"feature/one"};
    request.prune = true;
    request.tags = true;
    auto operation = makeFetchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    EXPECT_EQ(runner.invokedArgs(0),
             (std::vector<std::string>{"fetch", "--prune", "--tags", "origin", "feature/one"}));
}

TEST(FetchOperation, RejectsSpecificRefsWithoutARemoteNameWithoutRunningGit) {
    FakeProcessRunner runner;
    FetchRequest request;
    request.refs = {"feature/one"};
    auto operation = makeFetchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(AddRemoteOperation, RunsRemoteAddWithNameAndUrl) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"remote", "add", "origin", "git@github.com:example/repo.git"},
                           response);

    AddRemoteRequest request;
    request.name = "origin";
    request.url = "git@github.com:example/repo.git";
    auto operation = makeAddRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0),
             (std::vector<std::string>{"remote", "add", "origin",
                                       "git@github.com:example/repo.git"}));
}

TEST(AddRemoteOperation, RejectsEmptyNameWithoutRunningGit) {
    FakeProcessRunner runner;
    AddRemoteRequest request;
    request.name = "";
    request.url = "git@github.com:example/repo.git";
    auto operation = makeAddRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(AddRemoteOperation, RejectsEmptyUrlWithoutRunningGit) {
    FakeProcessRunner runner;
    AddRemoteRequest request;
    request.name = "origin";
    request.url = "";
    auto operation = makeAddRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(AddRemoteOperation, ReportsGitErrorOnFailure) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response failure;
    failure.exitCode = 1;
    failure.err = "error: remote origin already exists.\n";
    runner.whenArgsContain({"remote", "add", "origin", "git@github.com:example/repo.git"},
                           failure);

    AddRemoteRequest request;
    request.name = "origin";
    request.url = "git@github.com:example/repo.git";
    auto operation = makeAddRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
}

TEST(RemoveRemoteOperation, RunsRemoteRemoveWithName) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"remote", "remove", "origin"}, response);

    RemoveRemoteRequest request;
    request.name = "origin";
    auto operation = makeRemoveRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0),
             (std::vector<std::string>{"remote", "remove", "origin"}));
}

TEST(RemoveRemoteOperation, RejectsEmptyNameWithoutRunningGit) {
    FakeProcessRunner runner;
    RemoveRemoteRequest request;
    request.name = "";
    auto operation = makeRemoveRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(RemoveRemoteOperation, ReportsGitErrorOnFailure) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response failure;
    failure.exitCode = 1;
    failure.err = "error: No such remote: 'origin'\n";
    runner.whenArgsContain({"remote", "remove", "origin"}, failure);

    RemoveRemoteRequest request;
    request.name = "origin";
    auto operation = makeRemoveRemoteOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
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

std::optional<std::string> envOf(const GitCommand& command, const std::string& key) {
    for (const auto& [k, v] : command.envOverrides) {
        if (k == key) {
            return v;
        }
    }
    return std::nullopt;
}

TEST(FetchOperation, BackgroundFetchSkipsMaintenanceAndFetchHead) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"fetch", "--all"}, response);

    FetchRequest request;
    request.background = true;
    auto operation = makeFetchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    EXPECT_EQ(runner.invokedArgs(0),
              (std::vector<std::string>{
                  "fetch", "--no-auto-maintenance", "--no-write-fetch-head", "--all"}));
}

TEST(FetchOperation, BackgroundFetchRefusesPromptsEvenWithAnAskpassDir) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"fetch"}, response);

    FetchRequest request;
    request.background = true;
    request.askpassDir = "/tmp/gbm-askpass-should-be-ignored";
    auto operation = makeFetchOperation(request);

    operation->run(runner, testPaths(), CancellationToken{});

    ASSERT_EQ(runner.invocationCount(), 1u);
    const GitCommand& command = runner.invocations()[0];
    EXPECT_EQ(envOf(command, "GBM_ASKPASS_DIR"), "")
        << "nobody pressed a button, so no credential prompt may be raised";
    EXPECT_EQ(envOf(command, "GCM_INTERACTIVE"), "false");
}

TEST(FetchOperation, ForegroundFetchKeepsItsPromptAndPlainArgs) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"fetch"}, response);

    FetchRequest request;
    request.askpassDir = "/tmp/gbm-askpass-foreground";
    auto operation = makeFetchOperation(request);

    operation->run(runner, testPaths(), CancellationToken{});

    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0), (std::vector<std::string>{"fetch", "--all"}));
    EXPECT_EQ(envOf(runner.invocations()[0], "GBM_ASKPASS_DIR"), "/tmp/gbm-askpass-foreground");
}

TEST(FetchOperation, OnlyABackgroundFetchIsABackgroundUnit) {
    FetchRequest background;
    background.background = true;
    EXPECT_TRUE(makeFetchOperation(background)->isBackground());
    EXPECT_FALSE(makeFetchOperation(FetchRequest{})->isBackground());
}

TEST(FetchOperation, ABackgroundFetchWithNoEarlierSnapshotCountsAsMoved) {
    FakeProcessRunner runner;
    FetchRequest request;
    request.background = true;

    OperationOutcome outcome = makeFetchOperation(request)->run(runner, testPaths(), {});

    ASSERT_TRUE(outcome.succeeded);
    EXPECT_EQ(outcome.refsMoved, std::optional<bool>(true))
        << "no snapshot to compare against: walk rather than hide a change";
    EXPECT_EQ(runner.invocationCount(), 1u) << "nothing to compare, so no read either";
}

TEST(FetchOperation, ABackgroundFetchWhoseRefReadFailsCountsAsMoved) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response failed;
    failed.exitCode = 128;
    runner.whenArgsContain({"for-each-ref"}, failed);
    FetchRequest request;
    request.background = true;
    request.refsBefore = std::make_shared<const RefSnapshot>();

    OperationOutcome outcome = makeFetchOperation(request)->run(runner, testPaths(), {});

    ASSERT_TRUE(outcome.succeeded);
    EXPECT_EQ(outcome.refsMoved, std::optional<bool>(true));
}

TEST(FetchOperation, AForegroundFetchLeavesRefsMovedUnset) {
    FakeProcessRunner runner;
    FetchRequest request;
    request.refsBefore = std::make_shared<const RefSnapshot>();

    OperationOutcome outcome = makeFetchOperation(request)->run(runner, testPaths(), {});

    EXPECT_FALSE(outcome.refsMoved.has_value());
    EXPECT_EQ(runner.invocationCount(), 1u);
}

}  // namespace
}  // namespace gbm
