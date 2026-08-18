// Tests for InitCloneOps: `git init <path>` and `git clone <url> <dest>`,
// the two session-less operations run before any RepoPaths/Session exists
// (see InitCloneOps.h's doc comment for why these are plain functions
// rather than Operation subclasses).
#include "core/git/ops/InitCloneOps.h"
#include "support/FakeProcessRunner.h"

#include <gtest/gtest.h>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

TEST(RunInitRepo, RunsGitInitWithThePath) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"init", "--quiet", "/repos/new-project"}, response);

    InitRepoRequest request;
    request.path = "/repos/new-project";

    GitResult<void> result = runInitRepo(runner, request, CancellationToken{});

    EXPECT_TRUE(result);
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0),
              (std::vector<std::string>{"init", "--quiet", "/repos/new-project"}));
}

TEST(RunInitRepo, RejectsEmptyPathWithoutRunningGit) {
    FakeProcessRunner runner;
    InitRepoRequest request;

    GitResult<void> result = runInitRepo(runner, request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(RunInitRepo, ReportsGitErrorOnFailure) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response failure;
    failure.exitCode = 128;
    failure.err = "fatal: cannot mkdir /root/no-permission: Permission denied\n";
    runner.whenArgsContain({"init", "--quiet", "/root/no-permission"}, failure);

    InitRepoRequest request;
    request.path = "/root/no-permission";

    GitResult<void> result = runInitRepo(runner, request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_FALSE(result.error().message.empty());
}

TEST(RunCloneRepo, RunsGitCloneWithUrlAndDestination) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 0;
    runner.whenArgsContain({"clone", "--quiet", "/remotes/origin.git", "/repos/cloned"}, response);

    CloneRepoRequest request;
    request.url = "/remotes/origin.git";
    request.destPath = "/repos/cloned";

    GitResult<void> result = runCloneRepo(runner, request, CancellationToken{});

    EXPECT_TRUE(result);
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(
        runner.invokedArgs(0),
        (std::vector<std::string>{"clone", "--quiet", "/remotes/origin.git", "/repos/cloned"}));
}

TEST(RunCloneRepo, RejectsEmptyUrlWithoutRunningGit) {
    FakeProcessRunner runner;
    CloneRepoRequest request;
    request.destPath = "/repos/cloned";

    GitResult<void> result = runCloneRepo(runner, request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(RunCloneRepo, RejectsEmptyDestinationWithoutRunningGit) {
    FakeProcessRunner runner;
    CloneRepoRequest request;
    request.url = "/remotes/origin.git";

    GitResult<void> result = runCloneRepo(runner, request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(RunCloneRepo, ReportsGitErrorOnFailure) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response failure;
    failure.exitCode = 128;
    failure.err = "fatal: repository '/remotes/missing.git' does not exist\n";
    runner.whenArgsContain({"clone", "--quiet", "/remotes/missing.git", "/repos/cloned"}, failure);

    CloneRepoRequest request;
    request.url = "/remotes/missing.git";
    request.destPath = "/repos/cloned";

    GitResult<void> result = runCloneRepo(runner, request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_FALSE(result.error().message.empty());
}

}  // namespace
}  // namespace gbm
