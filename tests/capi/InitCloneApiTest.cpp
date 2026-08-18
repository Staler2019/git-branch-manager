// Integration tests for the session-less repository-creation slice of the
// extern "C" surface (gbm_capi.h): gbm_repo_init and gbm_repo_clone. Clone
// is tested against a local bare repository reached over the plain
// filesystem transport, which needs no credentials -- git never invokes
// askpass for it, so this stays fully offline, same as RemoteApiTest.cpp.
#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>

namespace gbm::capi {
namespace {

std::string lastResultJson() {
    std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()),
                              static_cast<int32_t>(json.size()));
    return json;
}

class InitCloneApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
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

    /// A bare repo with one commit on main, reachable as a plain filesystem
    /// path -- git treats that as a transport with no network/credentials
    /// involved, same fixture style as RemoteApiTest.cpp.
    std::filesystem::path makeBareOrigin() {
        const std::filesystem::path origin = base_ / "origin.git";
        const std::filesystem::path scratch = base_ / "origin-scratch";
        std::filesystem::create_directories(scratch);

        auto run = [](const std::string& cmd) { ASSERT_EQ(std::system(cmd.c_str()), 0); };
        run("git init --quiet --bare --initial-branch=main \"" + origin.string() + "\"");
        run("git -C \"" + scratch.string() + "\" init --quiet --initial-branch=main");
        run("git -C \"" + scratch.string() + "\" config user.email test@example.com");
        run("git -C \"" + scratch.string() + "\" config user.name Test");
        {
            std::ofstream file(scratch / "README.md");
            file << "hello\n";
        }
        run("git -C \"" + scratch.string() + "\" add README.md");
        run("git -C \"" + scratch.string() + "\" commit --quiet -m initial");
        run("git -C \"" + scratch.string() + "\" push --quiet \"" + origin.string() + "\" main");
        return origin;
    }

    std::filesystem::path base_;
};

TEST_F(InitCloneApiTest, InitCreatesAUsableRepository) {
    const std::filesystem::path repo = base_ / "new-project";

    ASSERT_EQ(gbm_repo_init(repo.string().c_str()), 0);

    EXPECT_TRUE(std::filesystem::is_directory(repo / ".git"));
}

TEST_F(InitCloneApiTest, InitCreatesMissingParentDirectories) {
    const std::filesystem::path repo = base_ / "nested" / "deep" / "new-project";

    ASSERT_EQ(gbm_repo_init(repo.string().c_str()), 0);

    EXPECT_TRUE(std::filesystem::is_directory(repo / ".git"));
}

TEST_F(InitCloneApiTest, InitFailsCleanlyWithAnEmptyPath) {
    const int32_t result = gbm_repo_init("");

    EXPECT_LT(result, 0);
    EXPECT_NE(lastResultJson().find("InvalidArgument"), std::string::npos);
}

TEST_F(InitCloneApiTest, CloneCreatesAWorkingCopyWithTheOriginsHistory) {
    const std::filesystem::path origin = makeBareOrigin();
    const std::filesystem::path dest = base_ / "cloned";

    ASSERT_EQ(gbm_repo_clone(origin.string().c_str(), dest.string().c_str()), 0);

    EXPECT_TRUE(std::filesystem::is_directory(dest / ".git"));
    EXPECT_TRUE(std::filesystem::is_regular_file(dest / "README.md"));
}

TEST_F(InitCloneApiTest, CloneFailsCleanlyWhenTheSourceDoesNotExist) {
    const std::filesystem::path missing = base_ / "does-not-exist.git";
    const std::filesystem::path dest = base_ / "cloned";

    const int32_t result = gbm_repo_clone(missing.string().c_str(), dest.string().c_str());

    EXPECT_LT(result, 0);
    EXPECT_FALSE(std::filesystem::exists(dest));
}

TEST_F(InitCloneApiTest, CloneFailsCleanlyWithAnEmptyUrl) {
    const std::filesystem::path dest = base_ / "cloned";

    const int32_t result = gbm_repo_clone("", dest.string().c_str());

    EXPECT_LT(result, 0);
    EXPECT_NE(lastResultJson().find("InvalidArgument"), std::string::npos);
    EXPECT_FALSE(std::filesystem::exists(dest));
}

TEST_F(InitCloneApiTest, ANewlyClonedRepositoryOpensANormalSession) {
    const std::filesystem::path origin = makeBareOrigin();
    const std::filesystem::path dest = base_ / "cloned";
    ASSERT_EQ(gbm_repo_clone(origin.string().c_str(), dest.string().c_str()), 0);

    GbmSessionHandle session =
        gbm_session_open(dest.string().c_str(), (dest / ".git").string().c_str(), nullptr);
    ASSERT_NE(session, nullptr);
    gbm_session_close(session);
}

}  // namespace
}  // namespace gbm::capi
