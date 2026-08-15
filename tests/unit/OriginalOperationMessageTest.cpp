// M6 commit 7: the conflict resolution window's Continue step (commit 9)
// needs git's own proposed commit message so it can show an editable
// pre-fill instead of relying on git's silent preserve-on-`--continue`
// behavior. These fixtures encode file shapes verified empirically against
// real git (a throwaway repo driven into each conflict state, then `.git`
// inspected directly) -- not assumed from documentation:
//   - conflicted merge:       MERGE_MSG has subject + "# Conflicts:" listing.
//   - conflicted cherry-pick: MERGE_MSG has the same shape (the source
//     commit's subject); CHERRY_PICK_HEAD holds only a 40-char OID, never
//     message text.
//   - conflicted revert:      MERGE_MSG again has the same shape ("Revert
//     "..."" + reason line); REVERT_HEAD likewise holds only an OID.
//   - conflicted rebase:      rebase-merge/message has the same content as
//     MERGE_MSG (git writes both), so it is checked first as the more
//     specific source.
#include "core/git/OriginalOperationMessage.h"

#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

/// Mirrors PreparedCommitMessageTest.cpp's TempTree-style fixture -- a
/// throwaway directory per test, named after the test itself so parallel
/// ctest jobs never collide.
class OriginalOperationMessage : public ::testing::Test {
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
        std::filesystem::create_directories(path.parent_path());
        std::ofstream out(path, std::ios::binary | std::ios::trunc);
        out << contents;
    }

    RepoPaths paths() const { return RepoPaths(root_, root_, root_); }

    std::filesystem::path root_;
};

TEST_F(OriginalOperationMessage, ReadsMergeMsgForAConflictedMerge) {
    writeFile(root_ / "MERGE_MSG", "Merge branch 'branchA'\n\n# Conflicts:\n#\tf.txt\n");

    EXPECT_EQ(readOriginalOperationMessage(paths()), "Merge branch 'branchA'\n\n# Conflicts:\n#\tf.txt\n");
}

TEST_F(OriginalOperationMessage, ReadsMergeMsgForAConflictedCherryPick) {
    // CHERRY_PICK_HEAD only ever holds the source commit's OID (never
    // message text), so it is deliberately not read here.
    writeFile(root_ / "CHERRY_PICK_HEAD", "bafb1d968c561f7707ac24d13f08fa84608fd130\n");
    writeFile(root_ / "MERGE_MSG", "A changes f.txt\n\n# Conflicts:\n#\tf.txt\n");

    EXPECT_EQ(readOriginalOperationMessage(paths()), "A changes f.txt\n\n# Conflicts:\n#\tf.txt\n");
}

TEST_F(OriginalOperationMessage, ReadsMergeMsgForAConflictedRevert) {
    // REVERT_HEAD, like CHERRY_PICK_HEAD, only holds an OID.
    writeFile(root_ / "REVERT_HEAD", "3466b519216df1720b25523bf4695459e688a98f\n");
    writeFile(root_ / "MERGE_MSG",
              "Revert \"main changes f.txt\"\n\n"
              "This reverts commit 3466b519216df1720b25523bf4695459e688a98f.\n\n"
              "# Conflicts:\n#\tf.txt\n");

    EXPECT_EQ(readOriginalOperationMessage(paths()),
              "Revert \"main changes f.txt\"\n\n"
              "This reverts commit 3466b519216df1720b25523bf4695459e688a98f.\n\n"
              "# Conflicts:\n#\tf.txt\n");
}

TEST_F(OriginalOperationMessage, PrefersRebaseMergeMessageOverMergeMsgWhenBothExist) {
    // Git mirrors the same content into both during a conflicted rebase;
    // rebase-merge/message is the more specific source and wins.
    writeFile(root_ / "rebase-merge" / "message", "A changes f.txt\n\n# Conflicts:\n#\tf.txt\n");
    writeFile(root_ / "MERGE_MSG", "A changes f.txt\n\n# Conflicts:\n#\tf.txt\n");

    EXPECT_EQ(readOriginalOperationMessage(paths()), "A changes f.txt\n\n# Conflicts:\n#\tf.txt\n");
}

TEST_F(OriginalOperationMessage, FallsBackToMergeMsgWhenNoRebaseMergeMessageExists) {
    writeFile(root_ / "MERGE_MSG", "Merge branch 'branchA'\n\n# Conflicts:\n#\tf.txt\n");

    EXPECT_EQ(readOriginalOperationMessage(paths()), "Merge branch 'branchA'\n\n# Conflicts:\n#\tf.txt\n");
}

TEST_F(OriginalOperationMessage, PreservesConflictsCommentLinesVerbatim) {
    // Stripping "#"-prefixed lines is a UI rendering concern (rendered in a
    // distinct/tertiary color per the conflict window's MSGS step), not a
    // read concern -- the caller needs the raw text to know which lines to
    // render that way.
    writeFile(root_ / "MERGE_MSG", "subject\n\n# Conflicts:\n#\tf.txt\n#\tg.txt\n");

    EXPECT_EQ(readOriginalOperationMessage(paths()), "subject\n\n# Conflicts:\n#\tf.txt\n#\tg.txt\n");
}

TEST_F(OriginalOperationMessage, ReturnsEmptyStringWhenNoOperationIsInProgress) {
    EXPECT_EQ(readOriginalOperationMessage(paths()), "");
}

}  // namespace
}  // namespace gbm
