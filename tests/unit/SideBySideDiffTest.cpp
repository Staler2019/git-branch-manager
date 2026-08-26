// Pairing logic only; UnifiedDiffParser already has its own coverage for the
// text -> DiffHunk parsing this builds on.
#include "core/git/SideBySideDiff.h"
#include "core/git/UnifiedDiffParser.h"

#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

const DiffHunk& firstHunk(const ParsedDiff& parsed) {
    return parsed.files.at(0).hunks.at(0);
}

TEST(SideBySideDiff, ContextLinesPassStraightAcrossUnchanged) {
    const std::string diff =
        "diff --git a/a.txt b/a.txt\n"
        "index 1111111..2222222 100644\n"
        "--- a/a.txt\n"
        "+++ b/a.txt\n"
        "@@ -1,3 +1,3 @@\n"
        " one\n"
        "-two\n"
        "+TWO\n"
        " three\n";
    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    const auto rows = pairHunkForSideBySide(firstHunk(parsed));

    ASSERT_EQ(rows.size(), 3u);
    EXPECT_EQ(rows[0].left, rows[0].right);
    EXPECT_EQ(rows[0].left->text, "one");
    EXPECT_EQ(rows[2].left, rows[2].right);
    EXPECT_EQ(rows[2].left->text, "three");
}

TEST(SideBySideDiff, PairsAnEqualLengthReplaceLineByLine) {
    const std::string diff =
        "diff --git a/a.txt b/a.txt\n"
        "index 1111111..2222222 100644\n"
        "--- a/a.txt\n"
        "+++ b/a.txt\n"
        "@@ -1,2 +1,2 @@\n"
        "-old1\n"
        "-old2\n"
        "+new1\n"
        "+new2\n";
    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    const auto rows = pairHunkForSideBySide(firstHunk(parsed));

    ASSERT_EQ(rows.size(), 2u);
    EXPECT_EQ(rows[0].left->text, "old1");
    EXPECT_EQ(rows[0].right->text, "new1");
    EXPECT_EQ(rows[1].left->text, "old2");
    EXPECT_EQ(rows[1].right->text, "new2");
}

TEST(SideBySideDiff, APureAdditionLeavesTheLeftSideBlank) {
    const std::string diff =
        "diff --git a/a.txt b/a.txt\n"
        "index 1111111..2222222 100644\n"
        "--- a/a.txt\n"
        "+++ b/a.txt\n"
        "@@ -1,1 +1,3 @@\n"
        " keep\n"
        "+added1\n"
        "+added2\n";
    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    const auto rows = pairHunkForSideBySide(firstHunk(parsed));

    ASSERT_EQ(rows.size(), 3u);
    EXPECT_EQ(rows[1].left, nullptr);
    ASSERT_NE(rows[1].right, nullptr);
    EXPECT_EQ(rows[1].right->text, "added1");
    EXPECT_EQ(rows[2].left, nullptr);
    ASSERT_NE(rows[2].right, nullptr);
    EXPECT_EQ(rows[2].right->text, "added2");
}

TEST(SideBySideDiff, APureDeletionLeavesTheRightSideBlank) {
    const std::string diff =
        "diff --git a/a.txt b/a.txt\n"
        "index 1111111..2222222 100644\n"
        "--- a/a.txt\n"
        "+++ b/a.txt\n"
        "@@ -1,3 +1,1 @@\n"
        " keep\n"
        "-removed1\n"
        "-removed2\n";
    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    const auto rows = pairHunkForSideBySide(firstHunk(parsed));

    ASSERT_EQ(rows.size(), 3u);
    ASSERT_NE(rows[1].left, nullptr);
    EXPECT_EQ(rows[1].left->text, "removed1");
    EXPECT_EQ(rows[1].right, nullptr);
    ASSERT_NE(rows[2].left, nullptr);
    EXPECT_EQ(rows[2].left->text, "removed2");
    EXPECT_EQ(rows[2].right, nullptr);
}

TEST(SideBySideDiff, AnUnequalReplacePadsTheShorterSideRatherThanMisaligning) {
    const std::string diff =
        "diff --git a/a.txt b/a.txt\n"
        "index 1111111..2222222 100644\n"
        "--- a/a.txt\n"
        "+++ b/a.txt\n"
        "@@ -1,3 +1,1 @@\n"
        "-old1\n"
        "-old2\n"
        "-old3\n"
        "+new1\n";
    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    const auto rows = pairHunkForSideBySide(firstHunk(parsed));

    ASSERT_EQ(rows.size(), 3u);
    EXPECT_EQ(rows[0].left->text, "old1");
    EXPECT_EQ(rows[0].right->text, "new1");
    EXPECT_EQ(rows[1].left->text, "old2");
    EXPECT_EQ(rows[1].right, nullptr);
    EXPECT_EQ(rows[2].left->text, "old3");
    EXPECT_EQ(rows[2].right, nullptr);
}

TEST(SideBySideDiff, HandlesMultipleChangedRegionsInOneHunkIndependently) {
    const std::string diff =
        "diff --git a/a.txt b/a.txt\n"
        "index 1111111..2222222 100644\n"
        "--- a/a.txt\n"
        "+++ b/a.txt\n"
        "@@ -1,5 +1,5 @@\n"
        " ctx1\n"
        "-a\n"
        "+A\n"
        " ctx2\n"
        "-b\n"
        "+B\n";
    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    const auto rows = pairHunkForSideBySide(firstHunk(parsed));

    ASSERT_EQ(rows.size(), 4u);
    EXPECT_EQ(rows[0].left->text, "ctx1");
    EXPECT_EQ(rows[1].left->text, "a");
    EXPECT_EQ(rows[1].right->text, "A");
    EXPECT_EQ(rows[2].left->text, "ctx2");
    EXPECT_EQ(rows[3].left->text, "b");
    EXPECT_EQ(rows[3].right->text, "B");
}

// The two cases below are this suite's newest, added together with their
// mirrors in side_by_side_diff_test.dart. The NoNewlineMarker arm was the one
// branch neither suite reached, and it is the arm most likely to be
// "simplified" into the `{&line, &line}` of the Context case just above it.

TEST(SideBySideDiff, ANoNewlineMarkerAfterARemovalStaysOnTheLeftSideOnly) {
    const std::string diff =
        "diff --git a/a.txt b/a.txt\n"
        "index 1111111..2222222 100644\n"
        "--- a/a.txt\n"
        "+++ b/a.txt\n"
        "@@ -1,2 +1,2 @@\n"
        " keep\n"
        "-old\n"
        "\\ No newline at end of file\n"
        "+new\n";
    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    const auto rows = pairHunkForSideBySide(firstHunk(parsed));

    ASSERT_EQ(rows.size(), 3u);
    ASSERT_NE(rows[1].left, nullptr);
    ASSERT_NE(rows[1].right, nullptr);
    EXPECT_EQ(rows[1].left->text, "old");
    EXPECT_EQ(rows[1].right->text, "new");
    // The marker says the *old* file had no trailing newline. Putting it on
    // both sides would claim the new file agrees, which is the opposite of
    // what it means.
    ASSERT_NE(rows[2].left, nullptr);
    EXPECT_EQ(rows[2].left->kind, DiffLineKind::NoNewlineMarker);
    EXPECT_EQ(rows[2].right, nullptr);
}

TEST(SideBySideDiff, ANoNewlineMarkerAfterAnAdditionStaysOnTheRightSideOnly) {
    const std::string diff =
        "diff --git a/a.txt b/a.txt\n"
        "index 1111111..2222222 100644\n"
        "--- a/a.txt\n"
        "+++ b/a.txt\n"
        "@@ -1,2 +1,2 @@\n"
        " keep\n"
        "-old\n"
        "+new\n"
        "\\ No newline at end of file\n";
    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    const auto rows = pairHunkForSideBySide(firstHunk(parsed));

    ASSERT_EQ(rows.size(), 3u);
    ASSERT_NE(rows[1].left, nullptr);
    ASSERT_NE(rows[1].right, nullptr);
    EXPECT_EQ(rows[1].left->text, "old");
    EXPECT_EQ(rows[1].right->text, "new");
    EXPECT_EQ(rows[2].left, nullptr);
    ASSERT_NE(rows[2].right, nullptr);
    EXPECT_EQ(rows[2].right->kind, DiffLineKind::NoNewlineMarker);
}

}  // namespace
}  // namespace gbm
