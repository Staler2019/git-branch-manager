#include "core/git/RepoPaths.h"
#include "core/git/ops/MaintenanceOps.h"

#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

// --- shouldOfferCommitGraph -------------------------------------------------
// Pure decision table, no repository needed -- see the header comment on why
// this logic was pulled out of RepositorySession instead of living there.

TEST(MaintenanceOps, NeverOffersWhenAGraphAlreadyExists) {
    EXPECT_FALSE(shouldOfferCommitGraph(
        /*hasGraph=*/true, kCommitGraphAdviceMinRows * 10, CommitGraphPreference::Unset));
}

TEST(MaintenanceOps, NeverOffersAfterTheUserDeclined) {
    EXPECT_FALSE(shouldOfferCommitGraph(
        /*hasGraph=*/false, kCommitGraphAdviceMinRows * 10, CommitGraphPreference::Declined));
}

TEST(MaintenanceOps, NeverOffersOnceEnabledEvenIfTheGraphIsMissing) {
    // Enabled means "keep this maintained", not "ask every time it happens to
    // be missing" -- e.g. right after a `git gc` pruned an out-of-date graph,
    // before the next write runs. Re-prompting here would be nagging, not
    // helping; the app is expected to just rebuild it, not ask again.
    EXPECT_FALSE(shouldOfferCommitGraph(
        /*hasGraph=*/false, kCommitGraphAdviceMinRows * 10, CommitGraphPreference::Enabled));
}

TEST(MaintenanceOps, DoesNotOfferBelowTheAdviceThreshold) {
    EXPECT_FALSE(shouldOfferCommitGraph(
        /*hasGraph=*/false, kCommitGraphAdviceMinRows - 1, CommitGraphPreference::Unset));
}

TEST(MaintenanceOps, OffersAtOrAboveTheAdviceThresholdWhenUnset) {
    EXPECT_TRUE(shouldOfferCommitGraph(
        /*hasGraph=*/false, kCommitGraphAdviceMinRows, CommitGraphPreference::Unset));
}

// --- hasCommitGraph ----------------------------------------------------------

/// A throwaway `objects/` tree, mirroring DiscoveryTest's TempTree: enough
/// directory structure for RepoPaths::commitGraphFile()/commitGraphChainFile()
/// to resolve against, without a real git repository.
class CommitGraphDetection : public ::testing::Test {
protected:
    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        root_ = std::filesystem::temp_directory_path() /
                ("gbm-test-" + std::string(info->test_suite_name()) + "-" +
                 std::string(info->name()));
        std::filesystem::remove_all(root_);
        const auto gitDir = root_ / ".git";
        std::filesystem::create_directories(gitDir / "objects" / "info");
        paths_ = RepoPaths(root_, gitDir, gitDir);
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(root_, ec);
    }

    static void touch(const std::filesystem::path& file) {
        std::filesystem::create_directories(file.parent_path());
        std::ofstream(file).put('\0');
    }

    std::filesystem::path root_;
    RepoPaths paths_;
};

TEST_F(CommitGraphDetection, FalseWhenNeitherFormExists) {
    EXPECT_FALSE(hasCommitGraph(paths_));
}

TEST_F(CommitGraphDetection, TrueForTheSingleFileForm) {
    touch(paths_.commitGraphFile());
    EXPECT_TRUE(hasCommitGraph(paths_));
}

TEST_F(CommitGraphDetection, TrueForTheSplitChainForm) {
    touch(paths_.commitGraphChainFile());
    EXPECT_TRUE(hasCommitGraph(paths_));
}

}  // namespace
}  // namespace gbm
