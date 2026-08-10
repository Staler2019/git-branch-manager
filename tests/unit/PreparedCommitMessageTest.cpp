// Design C3: git prepares a commit message before the user ever opens a
// commit dialog -- MERGE_MSG for a merge (with a "# Conflicts:" listing once
// conflicts are involved), SQUASH_MSG for `git merge --squash`. These pin
// readPreparedCommitMessage()'s priority order and its "neither exists" case
// (e.g. conflicts from `git apply --3way`, which prepares no message at all).
#include "core/git/PreparedCommitMessage.h"

#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

/// Mirrors DiscoveryTest.cpp's TempTree fixture -- a throwaway directory per
/// test, named after the test itself so parallel ctest jobs never collide.
class PreparedCommitMessage : public ::testing::Test {
protected:
    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        root_ = std::filesystem::temp_directory_path() /
                ("gbm-test-" + std::string(info->test_suite_name()) + "-" + std::string(info->name()));
        std::filesystem::remove_all(root_);
        std::filesystem::create_directories(root_);
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(root_, ec);
    }

    void writeFile(const std::filesystem::path& path, const std::string& contents) {
        std::ofstream out(path, std::ios::binary | std::ios::trunc);
        out << contents;
    }

    RepoPaths paths() const { return RepoPaths(root_, root_, root_); }

    std::filesystem::path root_;
};

TEST_F(PreparedCommitMessage, ReadsMergeMsgWhenPresent) {
    writeFile(root_ / "MERGE_MSG", "Merge branch 'feature'\n\n# Conflicts:\n#\tsrc/a.cpp\n");

    EXPECT_EQ(readPreparedCommitMessage(paths()), "Merge branch 'feature'\n\n# Conflicts:\n#\tsrc/a.cpp\n");
}

TEST_F(PreparedCommitMessage, FallsBackToSquashMsgWhenNoMergeMsgExists) {
    writeFile(root_ / "SQUASH_MSG", "Squashed commit of the following:\n");

    EXPECT_EQ(readPreparedCommitMessage(paths()), "Squashed commit of the following:\n");
}

TEST_F(PreparedCommitMessage, PrefersMergeMsgOverSquashMsgWhenBothSomehowExist) {
    writeFile(root_ / "MERGE_MSG", "merge message");
    writeFile(root_ / "SQUASH_MSG", "squash message");

    EXPECT_EQ(readPreparedCommitMessage(paths()), "merge message");
}

TEST_F(PreparedCommitMessage, ReturnsEmptyStringWhenNeitherFileExists) {
    EXPECT_EQ(readPreparedCommitMessage(paths()), "");
}

TEST(ShouldApplyPreparedCommitMessage, TrueWhenTheMessageBoxIsEmpty) {
    EXPECT_TRUE(shouldApplyPreparedCommitMessage("", "anything, or nothing"));
}

TEST(ShouldApplyPreparedCommitMessage, TrueWhenTheBoxStillHoldsTheLastAutofilledValue) {
    EXPECT_TRUE(shouldApplyPreparedCommitMessage("Merge branch 'x'", "Merge branch 'x'"));
}

TEST(ShouldApplyPreparedCommitMessage, FalseWhenTheUserHasTypedSomethingOfTheirOwn) {
    EXPECT_FALSE(shouldApplyPreparedCommitMessage("my own message", "Merge branch 'x'"));
}

TEST(ShouldApplyPreparedCommitMessage, FalseWhenTheUserEditedAwayFromWhatWasAutofilled) {
    // Not just "non-empty" -- specifically diverged from the autofilled
    // value, e.g. the user tweaked the prepared message rather than
    // replacing it wholesale.
    EXPECT_FALSE(shouldApplyPreparedCommitMessage("Merge branch 'x' (fixed typo)", "Merge branch 'x'"));
}

}  // namespace
}  // namespace gbm
