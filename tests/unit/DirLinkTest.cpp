// makeDirectoryLink replaced the capi tests' `cmd /c mklink /J` shell-out
// (cq.yml forbids std::system in tests). It is test infrastructure that a
// deletion-safety test leans on -- "a link out of the destination is never
// followed" proves nothing if the link was never made -- so what it makes is
// asserted here: the target is reachable through it, and removing the link
// leaves the target alone.
#include "support/DirLink.h"

#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <iterator>
#include <string>

namespace gbm::testing {
namespace {

class DirLinkTest : public ::testing::Test {
protected:
    void SetUp() override {
        // One directory per test: ctest runs each test as its own process, in
        // parallel.
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        base_ =
            std::filesystem::temp_directory_path() / ("gbm-dirlink-" + std::string(info->name()));
        std::filesystem::remove_all(base_);
        std::filesystem::create_directories(base_ / "target");
        std::ofstream(base_ / "target" / "sentinel.txt") << "keep";
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(base_, ec);
    }

    std::filesystem::path base_;
};

TEST_F(DirLinkTest, TheTargetIsReachableThroughTheLink) {
    const std::filesystem::path link = base_ / "link";
    std::error_code ec;
    ASSERT_TRUE(makeDirectoryLink(base_ / "target", link, ec)) << ec.message();

    std::ifstream in(link / "sentinel.txt");
    const std::string text((std::istreambuf_iterator<char>(in)), {});
    EXPECT_EQ(text, "keep");
}

TEST_F(DirLinkTest, RemovingTheLinkLeavesTheTarget) {
    const std::filesystem::path link = base_ / "link";
    std::error_code ec;
    ASSERT_TRUE(makeDirectoryLink(base_ / "target", link, ec)) << ec.message();

    std::filesystem::remove(link);

    EXPECT_FALSE(std::filesystem::exists(link));
    EXPECT_TRUE(std::filesystem::exists(base_ / "target" / "sentinel.txt"));
}

TEST_F(DirLinkTest, AnExistingPathIsAnError) {
    const std::filesystem::path link = base_ / "taken";
    std::filesystem::create_directories(link / "inside");
    std::error_code ec;

    EXPECT_FALSE(makeDirectoryLink(base_ / "target", link, ec));
    EXPECT_TRUE(ec);
}

}  // namespace
}  // namespace gbm::testing
