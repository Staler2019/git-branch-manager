#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"

#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>

namespace gbm::capi {
namespace {

class DiscoveryApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        base_ = std::filesystem::temp_directory_path() / ("gbm-capi-discovery-" + std::string(info->name()));
        repo_ = base_ / "repo";
        std::filesystem::remove_all(base_);
        std::filesystem::create_directories(repo_);

        const std::string cmd = "git -C \"" + repo_.string() +
                                "\" init --quiet --initial-branch=main >/dev/null 2>&1";
        ASSERT_EQ(std::system(cmd.c_str()), 0);
    }

    void TearDown() override {
        if (discovery_ != nullptr) {
            gbm_discovery_close(discovery_);
        }
        std::error_code ec;
        std::filesystem::remove_all(base_, ec);
    }

    std::filesystem::path base_;
    std::filesystem::path repo_;
    GbmDiscoveryHandle discovery_ = nullptr;
};

TEST_F(DiscoveryApiTest, ScanFindsRepositoryUnderBaseFolder) {
    discovery_ = gbm_discovery_open("");  // in-memory
    ASSERT_NE(discovery_, nullptr);

    const int64_t folderId = gbm_discovery_add_base_folder(discovery_, base_.string().c_str(), 2, 0);
    ASSERT_GE(folderId, 0);

    ASSERT_EQ(gbm_discovery_scan_all(discovery_), 0);

    ASSERT_EQ(gbm_discovery_list_repos_json(discovery_), 0);
    std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));

    EXPECT_NE(json.find(repo_.string()), std::string::npos) << json;
}

}  // namespace
}  // namespace gbm::capi
