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

// New repository's 「預設分支名」 (DLGS). `-b` alone is not enough: git
// refuses an invalid name only after it has created the directory, which
// then stays behind (measured, git 2.56.0: `init -b a..b x` exits 128 and
// leaves `x/`). So the name is checked first, and init never runs on a no.
TEST(RunInitRepo, ChecksTheInitialBranchThenRunsGitInitWithIt) {
    FakeProcessRunner runner;
    InitRepoRequest request;
    request.path = "/repos/new-project";
    request.initialBranch = "trunk";

    GitResult<void> result = runInitRepo(runner, request, CancellationToken{});

    EXPECT_TRUE(result);
    ASSERT_EQ(runner.invocationCount(), 2u);
    EXPECT_EQ(runner.invokedArgs(0),
              (std::vector<std::string>{"check-ref-format", "--branch", "trunk"}));
    EXPECT_EQ(runner.invokedArgs(1),
              (std::vector<std::string>{"init", "--quiet", "-b", "trunk", "/repos/new-project"}));
}

TEST(RunInitRepo, RefusesAnInvalidInitialBranchWithoutRunningInit) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response invalid;
    invalid.exitCode = 128;
    invalid.err = "fatal: 'a..b' is not a valid branch name\n";
    runner.whenArgsContain({"check-ref-format", "--branch", "a..b"}, invalid);

    InitRepoRequest request;
    request.path = "/repos/new-project";
    request.initialBranch = "a..b";

    GitResult<void> result = runInitRepo(runner, request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::InvalidArgument);
    EXPECT_NE(result.error().message.find("a..b"), std::string::npos) << result.error().message;
    EXPECT_EQ(runner.invocationCount(), 1u);
}

// Only git's "no" is an invalid name; a check that never answered is
// reported as what it was.
TEST(RunInitRepo, ATimedOutBranchCheckIsNotReportedAsAnInvalidName) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response timedOut;
    timedOut.timedOut = true;
    runner.whenArgsContain({"check-ref-format", "--branch", "trunk"}, timedOut);

    InitRepoRequest request;
    request.path = "/repos/new-project";
    request.initialBranch = "trunk";

    GitResult<void> result = runInitRepo(runner, request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::Timeout);
    EXPECT_EQ(runner.invocationCount(), 1u);
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
    runner.whenArgsContain({"clone", "--quiet", "--", "/remotes/origin.git", "/repos/cloned"},
                           response);

    CloneRepoRequest request;
    request.url = "/remotes/origin.git";
    request.destPath = "/repos/cloned";

    GitResult<void> result = runCloneRepo(runner, request, CancellationToken{});

    EXPECT_TRUE(result);
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0),
              (std::vector<std::string>{
                  "clone", "--quiet", "--", "/remotes/origin.git", "/repos/cloned"}));
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
    runner.whenArgsContain({"clone", "--quiet", "--", "/remotes/missing.git", "/repos/cloned"},
                           failure);

    CloneRepoRequest request;
    request.url = "/remotes/missing.git";
    request.destPath = "/repos/cloned";

    GitResult<void> result = runCloneRepo(runner, request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_FALSE(result.error().message.empty());
}

TEST(RunCloneRepo, PassesSubmodulesAndDepthAsOptionsBeforeTheSeparator) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"clone"}, FakeProcessRunner::Response{});

    CloneRepoRequest request;
    request.url = "/remotes/origin.git";
    request.destPath = "/repos/cloned";
    request.recurseSubmodules = true;
    request.depth = 1;

    ASSERT_TRUE(runCloneRepo(runner, request, CancellationToken{}));
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0),
              (std::vector<std::string>{"clone",
                                        "--quiet",
                                        "--recurse-submodules",
                                        "--depth",
                                        "1",
                                        "--",
                                        "/remotes/origin.git",
                                        "/repos/cloned"}));
}

TEST(RunCloneRepo, RejectsAUrlThatReadsAsAnOptionWithoutRunningGit) {
    // `--` already stops git reading it as one; refusing it outright means a
    // pasted `--upload-pack=...` never reaches git in any position.
    FakeProcessRunner runner;
    CloneRepoRequest request;
    request.url = "--upload-pack=touch /tmp/x";
    request.destPath = "/repos/cloned";

    GitResult<void> result = runCloneRepo(runner, request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(RunCloneRepo, RejectsANegativeDepthWithoutRunningGit) {
    FakeProcessRunner runner;
    CloneRepoRequest request;
    request.url = "/remotes/origin.git";
    request.destPath = "/repos/cloned";
    request.depth = -1;

    GitResult<void> result = runCloneRepo(runner, request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(RunCloneRepo, ReportsTransferProgressParsedFromStderr) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.err =
        "Cloning into 'cloned'...\n"
        "Receiving objects: 100% (17333/17333), 9.07 MiB | 56.66 MiB/s, done.\n"
        "Resolving deltas:  51% (6553/12848)\r";
    runner.whenArgsContain({"clone"}, response);

    std::vector<TransferProgress> seen;
    CloneRepoRequest request;
    request.url = "/remotes/origin.git";
    request.destPath = "/repos/cloned";
    request.onProgress = [&seen](const TransferProgress& progress) { seen.push_back(progress); };

    ASSERT_TRUE(runCloneRepo(runner, request, CancellationToken{}));
    EXPECT_EQ(
        seen,
        (std::vector<TransferProgress>{{TransferProgress::Phase::ResolvingDeltas, 6553, 12848}}));
}

TEST(RunCloneRepo, AChunkWithNoProgressReportsNothing) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.err = "Cloning into 'cloned'...\n";
    runner.whenArgsContain({"clone"}, response);

    int calls = 0;
    CloneRepoRequest request;
    request.url = "/remotes/origin.git";
    request.destPath = "/repos/cloned";
    request.onProgress = [&calls](const TransferProgress&) { ++calls; };

    ASSERT_TRUE(runCloneRepo(runner, request, CancellationToken{}));
    EXPECT_EQ(calls, 0);
}

}  // namespace
}  // namespace gbm
