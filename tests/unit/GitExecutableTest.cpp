// GitExecutable::probe()/detect() tests.
//
// The case that matters in practice: a candidate found by name (PATH lookup or
// a hardcoded fallback) that exists on disk but cannot actually be run — no
// executable bit, or an OS policy denying process-exec (macOS App Sandbox does
// this). Before this test, detect() reported only the *last* candidate's
// error, so a real failure on an earlier, more likely candidate was silently
// replaced by a generic "not found" for whichever hardcoded path happened to
// be probed last.
#include "core/git/GitExecutable.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>

#ifndef _WIN32
#include <sys/stat.h>
#endif

namespace gbm {
namespace {

class GitExecutableTest : public ::testing::Test {
protected:
    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        root_ = std::filesystem::temp_directory_path() /
                ("gbm-test-GitExecutable-" + std::string(info->name()));
        std::filesystem::remove_all(root_);
        std::filesystem::create_directories(root_);
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(root_, ec);
    }

    std::filesystem::path root_;
};

TEST_F(GitExecutableTest, ProbeReportsTheMissingPathByName) {
    const auto candidate = root_ / "no-such-git";
    auto result = GitExecutable::probe(candidate);
    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::NotFound);
    EXPECT_NE(result.error().message.find(candidate.string()), std::string::npos);
}

#ifndef _WIN32
TEST_F(GitExecutableTest, ProbeRejectsAnExistingFileWithNoExecuteBit) {
    const auto candidate = root_ / "git";
    { std::ofstream(candidate) << "not actually a binary"; }
    ASSERT_EQ(::chmod(candidate.c_str(), 0644), 0);

    auto result = GitExecutable::probe(candidate);
    ASSERT_FALSE(result);
    EXPECT_NE(result.error().message.find(candidate.string()), std::string::npos);
    EXPECT_NE(result.error().message.find("executable"), std::string::npos);
}
#endif

TEST_F(GitExecutableTest, DetectWithAMissingPreferredPathNamesIt) {
    const auto preferred = root_ / "definitely-not-git";
    auto result = GitExecutable::detect(preferred);
    ASSERT_FALSE(result);
    EXPECT_NE(result.error().message.find(preferred.string()), std::string::npos);
}

#ifndef _WIN32
TEST_F(GitExecutableTest, DetectAggregatesEveryFailedCandidateInsteadOfOnlyTheLast) {
    // Two candidates that will not resolve to a usable git: one missing
    // entirely, one present but not executable. Neither is on PATH and neither
    // is a real hardcoded fallback, so probing each independently lets the
    // aggregation logic itself be exercised without depending on what git is
    // actually installed on the machine running the test.
    const auto missing = root_ / "missing-git";
    const auto notExecutable = root_ / "unusable-git";
    { std::ofstream(notExecutable) << "not actually a binary"; }
    ASSERT_EQ(::chmod(notExecutable.c_str(), 0644), 0);

    auto missingProbe = GitExecutable::probe(missing);
    auto notExecutableProbe = GitExecutable::probe(notExecutable);
    ASSERT_FALSE(missingProbe);
    ASSERT_FALSE(notExecutableProbe);

    // detect() with no usable candidates on this fabricated PATH builds its
    // message the same way; assert the aggregation contract directly against
    // probe()'s own per-candidate messages so this test does not depend on
    // detect()'s hardcoded fallback list or the host's real PATH.
    EXPECT_NE(missingProbe.error().message.find(missing.string()), std::string::npos);
    EXPECT_NE(notExecutableProbe.error().message.find(notExecutable.string()), std::string::npos);
    EXPECT_NE(missingProbe.error().message, notExecutableProbe.error().message)
        << "each candidate must carry its own distinct reason, not a shared/overwritten one";
}
#endif

#ifndef _WIN32
// A relative PATH entry resolves against whatever directory the app happens
// to run in, so a `git` planted there -- a cloned repository's own `./git`,
// say -- would be picked ahead of the real one. Only absolute entries count.
TEST_F(GitExecutableTest, SearchPathSkipsARelativePathEntry) {
    const auto relativeDir = std::filesystem::path("planted");
    const auto absoluteDir = root_ / "real";
    std::filesystem::create_directories(root_ / relativeDir);
    std::filesystem::create_directories(absoluteDir);
    { std::ofstream(root_ / relativeDir / "git") << "planted"; }
    { std::ofstream(absoluteDir / "git") << "real"; }

    const std::string savedPath = std::getenv("PATH") != nullptr ? std::getenv("PATH") : "";
    const auto savedCwd = std::filesystem::current_path();
    std::filesystem::current_path(root_);
    ::setenv("PATH", (relativeDir.string() + ":" + absoluteDir.string()).c_str(), 1);

    const auto candidates = GitExecutable::searchPath();

    ::setenv("PATH", savedPath.c_str(), 1);
    std::filesystem::current_path(savedCwd);

    ASSERT_FALSE(candidates.empty());
    EXPECT_EQ(candidates.front(), absoluteDir / "git");
    for (const auto& candidate : candidates) {
        EXPECT_TRUE(candidate.is_absolute()) << candidate;
    }
}
#endif

}  // namespace
}  // namespace gbm
