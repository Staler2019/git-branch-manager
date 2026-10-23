// Integration tests for the session-less slice of the extern "C" surface
// (gbm_capi.h): gbm_repo_init and gbm_git_version_json. Clone is a job now
// (gbm_clone_start); CloneJobApiTest.cpp covers it.
#include "capi/gbm_capi.h"
#include "core/base/Error.h"
#include "core/git/GitExecutable.h"
#include "support/GitCli.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>

namespace gbm::capi {
namespace {

using ::gbm::testing::GitCli;

std::string lastResultJson() {
    std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()),
                              static_cast<int32_t>(json.size()));
    return json;
}

class InitCloneApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        // GitCli detects git once per test binary and caches it; this used to
        // be a GitExecutable::detect() per suite, i.e. one `git --version`
        // process each -- 29 of them across this binary.
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        base_ = std::filesystem::temp_directory_path() /
                ("gbm-capi-initclone-" + std::string(info->name()));
        std::filesystem::remove_all(base_);
        std::filesystem::create_directories(base_);
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(base_, ec);
    }

    std::filesystem::path base_;
};

TEST_F(InitCloneApiTest, InitCreatesAUsableRepository) {
    const std::filesystem::path repo = base_ / "new-project";

    ASSERT_EQ(gbm_repo_init(repo.string().c_str(), nullptr), 0);

    EXPECT_TRUE(std::filesystem::is_directory(repo / ".git"));
}

TEST_F(InitCloneApiTest, InitCreatesMissingParentDirectories) {
    const std::filesystem::path repo = base_ / "nested" / "deep" / "new-project";

    ASSERT_EQ(gbm_repo_init(repo.string().c_str(), nullptr), 0);

    EXPECT_TRUE(std::filesystem::is_directory(repo / ".git"));
}

TEST_F(InitCloneApiTest, InitFailsCleanlyWithAnEmptyPath) {
    const int32_t result = gbm_repo_init("", nullptr);

    EXPECT_LT(result, 0);
    EXPECT_NE(lastResultJson().find("InvalidArgument"), std::string::npos);
}

// New repository's 「預設分支名」 reaches git as `-b`: a fresh repository has
// no commit yet, so HEAD is the only place the name is visible.
TEST_F(InitCloneApiTest, InitStartsOnTheRequestedBranch) {
    const std::filesystem::path repo = base_ / "new-project";

    ASSERT_EQ(gbm_repo_init(repo.string().c_str(), "trunk"), 0);

    std::ifstream head(repo / ".git" / "HEAD");
    std::string line;
    std::getline(head, line);
    EXPECT_EQ(line, "ref: refs/heads/trunk");
}

// git refuses an invalid `-b` only after creating the directory (measured,
// git 2.56.0); core checks the name first, so nothing is left on disk.
TEST_F(InitCloneApiTest, AnInvalidInitialBranchLeavesNothingOnDisk) {
    const std::filesystem::path repo = base_ / "new-project";

    const int32_t result = gbm_repo_init(repo.string().c_str(), "a..b");

    EXPECT_LT(result, 0);
    EXPECT_NE(lastResultJson().find("InvalidArgument"), std::string::npos) << lastResultJson();
    EXPECT_FALSE(std::filesystem::exists(repo));
}

// The clone dialog decides whether "clone submodules" starts checked from the
// detected git's version (welcome-and-clone-spec.html W-D5), so the capi
// reports exactly what core detected -- the same installation every git
// invocation runs.
TEST_F(InitCloneApiTest, GitVersionJsonReportsTheDetectedInstallation) {
    // The same lookup sharedGitInstallation() makes, GBM_GIT_PATH included.
    const char* overridePath = std::getenv("GBM_GIT_PATH");
    const GitResult<GitInstallation> detected = GitExecutable::detect(
        overridePath != nullptr ? std::filesystem::path(overridePath) : std::filesystem::path{});
    ASSERT_TRUE(detected);
    const GitVersion& v = detected.value().version;

    ASSERT_EQ(gbm_git_version_json(), 0);

    EXPECT_EQ(lastResultJson(),
              "{\"major\":" + std::to_string(v.major) + ",\"minor\":" + std::to_string(v.minor) +
                  ",\"patch\":" + std::to_string(v.patch) + "}");
}

}  // namespace
}  // namespace gbm::capi
