// GitCli is the fixture-side git runner that replaced std::system() in the capi
// tests. It is itself test infrastructure, so the properties the migration
// depends on are asserted here rather than assumed: that an argument reaches
// git verbatim (no shell in between), that stdout comes back, and that a
// non-zero exit is reported as git's own code rather than a wait status.
#include "support/GitCli.h"

#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>

namespace gbm::testing {
namespace {

class GitCliTest : public ::testing::Test {
protected:
    void SetUp() override {
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ =
            std::filesystem::temp_directory_path() / ("gbm-gitcli-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);
        ASSERT_EQ(GitCli::run(repo_, {"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(GitCli::run(repo_, {"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(GitCli::run(repo_, {"config", "user.name", "Test"}), 0);
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(repo_, ec);
    }

    void write(const std::string& name, const std::string& contents) {
        std::ofstream out(repo_ / name, std::ios::binary | std::ios::trunc);
        out << contents;
    }

    std::filesystem::path repo_;
};

TEST_F(GitCliTest, ReturnsStdoutInsteadOfNeedingARedirectToATempFile) {
    write("a.txt", "one\n");
    ASSERT_EQ(GitCli::run(repo_, {"add", "a.txt"}), 0);
    ASSERT_EQ(GitCli::run(repo_, {"commit", "--quiet", "-m", "first"}), 0);

    const GitCliResult branch = GitCli::capture(repo_, {"branch", "--format=%(refname:short)"});
    EXPECT_EQ(branch.exitCode, 0);
    EXPECT_EQ(branch.out, "main");
}

TEST_F(GitCliTest, PassesAnArgumentThroughVerbatimWithNoShellInTheMiddle) {
    // `%(refname:short)` unquoted is a syntax error in dash because of the
    // parentheses, and a single-quoted argument reaches git.exe with the quotes
    // still attached under cmd.exe. Both were real problems for the string-and-
    // shell helper this replaced; neither can happen through an argv vector.
    // A commit subject with a space, a quote and a dollar sign proves the same
    // point on the write side.
    write("a.txt", "one\n");
    ASSERT_EQ(GitCli::run(repo_, {"add", "a.txt"}), 0);
    const std::string subject = R"(a "quoted" $subject with spaces)";
    ASSERT_EQ(GitCli::run(repo_, {"commit", "--quiet", "-m", subject}), 0);

    const GitCliResult logged = GitCli::capture(repo_, {"log", "-1", "--format=%s"});
    EXPECT_EQ(logged.exitCode, 0);
    EXPECT_EQ(logged.out, subject);
}

TEST_F(GitCliTest, ReportsGitsOwnExitCodeRatherThanAWaitStatus) {
    // std::system() returned exitCode << 8 on POSIX, so a failing git looked
    // like 256 rather than 1. Fixtures only ever compared against zero, but the
    // value is now the real one and worth pinning.
    const int rc = GitCli::run(repo_, {"rev-parse", "--verify", "--quiet", "refs/heads/nope"});
    EXPECT_NE(rc, 0);
    EXPECT_EQ(rc, 1);
}

TEST_F(GitCliTest, RunsInTheDirectoryItIsGivenNotTheProcessWorkingDirectory) {
    // RemoteApiTest and InitCloneApiTest drive a second repository (a bare
    // origin, a scratch clone source) alongside the fixture's own.
    const std::filesystem::path other = repo_.string() + "-other";
    std::filesystem::remove_all(other);
    std::filesystem::create_directories(other);
    ASSERT_EQ(GitCli::run(other, {"init", "--quiet", "--initial-branch=trunk"}), 0);

    EXPECT_EQ(GitCli::capture(other, {"symbolic-ref", "--short", "HEAD"}).out, "trunk");
    EXPECT_EQ(GitCli::capture(repo_, {"symbolic-ref", "--short", "HEAD"}).out, "main");

    std::error_code ec;
    std::filesystem::remove_all(other, ec);
}

}  // namespace
}  // namespace gbm::testing
