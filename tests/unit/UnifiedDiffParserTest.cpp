// The diff parser is new surface area created by the CLI-only backend: with no
// in-process diff library, `git diff -p` text is the only source of hunk data. A
// bug here shows up as a *wrong diff* rather than a crash, so the awkward cases
// get explicit coverage.
#include "core/git/UnifiedDiffParser.h"

#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

TEST(UnifiedDiffParser, ParsesASimpleModification) {
    const std::string diff =
        "diff --git a/src/main.cpp b/src/main.cpp\n"
        "index 1234567..89abcde 100644\n"
        "--- a/src/main.cpp\n"
        "+++ b/src/main.cpp\n"
        "@@ -10,7 +10,8 @@ int main() {\n"
        " context one\n"
        "-removed line\n"
        "+added line\n"
        "+another added\n"
        " context two\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);

    ASSERT_EQ(parsed.files.size(), 1u);
    const DiffFile& file = parsed.files[0];
    EXPECT_EQ(file.oldPath, "src/main.cpp");
    EXPECT_EQ(file.newPath, "src/main.cpp");
    EXPECT_EQ(file.kind, FileChangeKind::Modified);
    EXPECT_EQ(file.addedLines, 2u);
    EXPECT_EQ(file.removedLines, 1u);
    EXPECT_EQ(file.oldBlob, "1234567");
    EXPECT_EQ(file.newBlob, "89abcde");

    ASSERT_EQ(file.hunks.size(), 1u);
    const DiffHunk& hunk = file.hunks[0];
    EXPECT_EQ(hunk.oldStart, 10u);
    EXPECT_EQ(hunk.oldCount, 7u);
    EXPECT_EQ(hunk.newStart, 10u);
    EXPECT_EQ(hunk.newCount, 8u);
    EXPECT_EQ(hunk.heading, "int main() {");
    ASSERT_EQ(hunk.lines.size(), 5u);

    // Line numbering has to advance independently on each side, or side-by-side
    // rendering and hunk staging both land on the wrong lines.
    EXPECT_EQ(hunk.lines[0].kind, DiffLineKind::Context);
    EXPECT_EQ(hunk.lines[0].oldLine, 10u);
    EXPECT_EQ(hunk.lines[0].newLine, 10u);
    EXPECT_EQ(hunk.lines[1].kind, DiffLineKind::Removed);
    EXPECT_EQ(hunk.lines[1].oldLine, 11u);
    EXPECT_EQ(hunk.lines[1].newLine, 0u);
    EXPECT_EQ(hunk.lines[2].kind, DiffLineKind::Added);
    EXPECT_EQ(hunk.lines[2].newLine, 11u);
    EXPECT_EQ(hunk.lines[2].oldLine, 0u);
    EXPECT_EQ(hunk.lines[4].oldLine, 12u);
    EXPECT_EQ(hunk.lines[4].newLine, 13u);
}

TEST(UnifiedDiffParser, ParsesNewAndDeletedFiles) {
    const std::string diff =
        "diff --git a/added.txt b/added.txt\n"
        "new file mode 100644\n"
        "index 0000000..e69de29\n"
        "--- /dev/null\n"
        "+++ b/added.txt\n"
        "@@ -0,0 +1 @@\n"
        "+hello\n"
        "diff --git a/gone.txt b/gone.txt\n"
        "deleted file mode 100644\n"
        "index e69de29..0000000\n"
        "--- a/gone.txt\n"
        "+++ /dev/null\n"
        "@@ -1 +0,0 @@\n"
        "-goodbye\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);

    ASSERT_EQ(parsed.files.size(), 2u);
    EXPECT_EQ(parsed.files[0].kind, FileChangeKind::Added);
    EXPECT_EQ(parsed.files[0].newPath, "added.txt");
    EXPECT_EQ(parsed.files[0].displayPath(), "added.txt");

    EXPECT_EQ(parsed.files[1].kind, FileChangeKind::Deleted);
    EXPECT_EQ(parsed.files[1].oldPath, "gone.txt");
    // For a deleted file the *old* path is what should be shown; the new side is
    // /dev/null and would render as an empty name.
    EXPECT_EQ(parsed.files[1].displayPath(), "gone.txt");
}

TEST(UnifiedDiffParser, OmittedHunkCountMeansExactlyOneLine) {
    // "@@ -1 +1 @@" is valid and means a single line on each side. Defaulting to
    // zero here would silently drop the line.
    const std::string diff =
        "diff --git a/one.txt b/one.txt\n"
        "--- a/one.txt\n"
        "+++ b/one.txt\n"
        "@@ -1 +1 @@\n"
        "-old\n"
        "+new\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    ASSERT_EQ(parsed.files[0].hunks.size(), 1u);
    EXPECT_EQ(parsed.files[0].hunks[0].oldCount, 1u);
    EXPECT_EQ(parsed.files[0].hunks[0].newCount, 1u);
}

TEST(UnifiedDiffParser, ParsesRenamesWithSimilarity) {
    const std::string diff =
        "diff --git a/old/name.txt b/new/name.txt\n"
        "similarity index 87%\n"
        "rename from old/name.txt\n"
        "rename to new/name.txt\n"
        "index 1111111..2222222 100644\n"
        "--- a/old/name.txt\n"
        "+++ b/new/name.txt\n"
        "@@ -1,2 +1,2 @@\n"
        " same\n"
        "-before\n"
        "+after\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    EXPECT_EQ(parsed.files[0].kind, FileChangeKind::Renamed);
    EXPECT_EQ(parsed.files[0].oldPath, "old/name.txt");
    EXPECT_EQ(parsed.files[0].newPath, "new/name.txt");
    EXPECT_EQ(parsed.files[0].similarity, 87);
}

TEST(UnifiedDiffParser, DetectsBinaryFiles) {
    const std::string diff =
        "diff --git a/logo.png b/logo.png\n"
        "index 1111111..2222222 100644\n"
        "Binary files a/logo.png and b/logo.png differ\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    EXPECT_TRUE(parsed.files[0].binary);
    EXPECT_TRUE(parsed.files[0].hunks.empty());
}

TEST(UnifiedDiffParser, ParsesModeOnlyChangeWithNoHunks) {
    const std::string diff =
        "diff --git a/script.sh b/script.sh\n"
        "old mode 100644\n"
        "new mode 100755\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    EXPECT_EQ(parsed.files[0].kind, FileChangeKind::ModeChanged);
    EXPECT_EQ(parsed.files[0].oldMode, "100644");
    EXPECT_EQ(parsed.files[0].newMode, "100755");
    EXPECT_TRUE(parsed.files[0].hunks.empty());
}

TEST(UnifiedDiffParser, HandlesMissingTrailingNewline) {
    const std::string diff =
        "diff --git a/f.txt b/f.txt\n"
        "--- a/f.txt\n"
        "+++ b/f.txt\n"
        "@@ -1 +1 @@\n"
        "-old\n"
        "\\ No newline at end of file\n"
        "+new\n"
        "\\ No newline at end of file\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    const DiffHunk& hunk = parsed.files[0].hunks[0];

    int markers = 0;
    for (const DiffLine& line : hunk.lines) {
        if (line.kind == DiffLineKind::NoNewlineMarker) {
            ++markers;
        }
    }
    EXPECT_EQ(markers, 2);
    // The markers must not be counted as content, or the hunk's line counts drift.
    EXPECT_EQ(parsed.files[0].addedLines, 1u);
    EXPECT_EQ(parsed.files[0].removedLines, 1u);
}

TEST(UnifiedDiffParser, StripsCarriageReturnsFromLineEndings) {
    // git on Windows can emit CRLF around the diff structure itself.
    const std::string diff =
        "diff --git a/f.txt b/f.txt\r\n"
        "--- a/f.txt\r\n"
        "+++ b/f.txt\r\n"
        "@@ -1,1 +1,1 @@\r\n"
        "-old\r\n"
        "+new\r\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    ASSERT_EQ(parsed.files[0].hunks.size(), 1u);
    ASSERT_EQ(parsed.files[0].hunks[0].lines.size(), 2u);
    EXPECT_EQ(parsed.files[0].hunks[0].lines[0].text, "old");
    EXPECT_EQ(parsed.files[0].hunks[0].lines[1].text, "new");
}

TEST(UnifiedDiffParser, UnquotesPathsWithSpecialCharacters) {
    const std::string diff =
        "diff --git \"a/dir/file with \\\"quotes\\\".txt\" \"b/dir/file with \\\"quotes\\\".txt\"\n"
        "--- \"a/dir/file with \\\"quotes\\\".txt\"\n"
        "+++ \"b/dir/file with \\\"quotes\\\".txt\"\n"
        "@@ -1 +1 @@\n"
        "-a\n"
        "+b\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    EXPECT_EQ(parsed.files[0].newPath, "dir/file with \"quotes\".txt");
}

TEST(UnifiedDiffParser, DecodesOctalEscapedUtf8Paths) {
    // "café.txt" as git escapes it when it decides to quote.
    const std::string diff =
        "diff --git \"a/caf\\303\\251.txt\" \"b/caf\\303\\251.txt\"\n"
        "--- \"a/caf\\303\\251.txt\"\n"
        "+++ \"b/caf\\303\\251.txt\"\n"
        "@@ -1 +1 @@\n"
        "-a\n"
        "+b\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    EXPECT_EQ(parsed.files[0].newPath, "café.txt");
}

TEST(UnifiedDiffParser, HandlesMultipleHunksPerFile) {
    const std::string diff =
        "diff --git a/f.txt b/f.txt\n"
        "--- a/f.txt\n"
        "+++ b/f.txt\n"
        "@@ -1,3 +1,3 @@\n"
        " a\n"
        "-b\n"
        "+B\n"
        "@@ -20,3 +20,3 @@\n"
        " x\n"
        "-y\n"
        "+Y\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    ASSERT_EQ(parsed.files[0].hunks.size(), 2u);
    EXPECT_EQ(parsed.files[0].hunks[1].oldStart, 20u);
    EXPECT_EQ(parsed.files[0].addedLines, 2u);
}

TEST(UnifiedDiffParser, ClipsPathologicallyLongLines) {
    // Minified JavaScript arrives as one enormous line and would otherwise be
    // handed to the renderer verbatim.
    UnifiedDiffParser::Options options;
    options.maxLineLength = 32;

    std::string longLine(5000, 'x');
    const std::string diff =
        "diff --git a/min.js b/min.js\n"
        "--- a/min.js\n"
        "+++ b/min.js\n"
        "@@ -1 +1 @@\n"
        "+" +
        longLine + "\n";

    const ParsedDiff parsed = UnifiedDiffParser{options}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    EXPECT_EQ(parsed.files[0].hunks[0].lines[0].text.size(), 32u);
}

TEST(UnifiedDiffParser, ReportsTruncationInsteadOfParsingHugeInput) {
    UnifiedDiffParser::Options options;
    options.maxBytes = 256;

    std::string diff =
        "diff --git a/big.txt b/big.txt\n"
        "--- a/big.txt\n"
        "+++ b/big.txt\n"
        "@@ -1,1000 +1,1000 @@\n";
    for (int i = 0; i < 500; ++i) {
        diff += "+line " + std::to_string(i) + "\n";
    }

    const ParsedDiff parsed = UnifiedDiffParser{options}.parse(diff);
    EXPECT_TRUE(parsed.truncated);
    // The file list still populates, so the UI can offer to open the file.
    ASSERT_EQ(parsed.files.size(), 1u);
}

TEST(UnifiedDiffParser, ToleratesEmptyAndGarbageInput) {
    EXPECT_TRUE(UnifiedDiffParser{}.parse("").files.empty());
    EXPECT_TRUE(UnifiedDiffParser{}.parse("not a diff at all\n").files.empty());
    // A header with no body must not produce a phantom hunk.
    const ParsedDiff headerOnly = UnifiedDiffParser{}.parse("diff --git a/x b/x\n");
    ASSERT_EQ(headerOnly.files.size(), 1u);
    EXPECT_TRUE(headerOnly.files[0].hunks.empty());
}

TEST(UnifiedDiffParser, BuildHunkPatchRoundTripsCountsExactly) {
    const std::string diff =
        "diff --git a/f.txt b/f.txt\n"
        "--- a/f.txt\n"
        "+++ b/f.txt\n"
        "@@ -5,4 +5,5 @@\n"
        " keep\n"
        "-drop\n"
        "+add one\n"
        "+add two\n"
        " keep2\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    ASSERT_EQ(parsed.files.size(), 1u);
    const std::string patch =
        UnifiedDiffParser::buildHunkPatch(parsed.files[0], parsed.files[0].hunks[0]);

    // git apply refuses a patch whose declared counts do not match its body, so
    // the counts are recomputed from the emitted lines rather than copied.
    EXPECT_NE(patch.find("@@ -5,3 +5,4 @@"), std::string::npos) << patch;
    EXPECT_NE(patch.find("--- a/f.txt"), std::string::npos);
    EXPECT_NE(patch.find("+add two"), std::string::npos);
}

TEST(UnifiedDiffParser, BuildHunkPatchSwapsSidesWhenReversed) {
    const std::string diff =
        "diff --git a/f.txt b/f.txt\n"
        "--- a/f.txt\n"
        "+++ b/f.txt\n"
        "@@ -10,2 +20,3 @@\n"
        " keep\n"
        "+added\n"
        " keep2\n";

    const ParsedDiff parsed = UnifiedDiffParser{}.parse(diff);
    const std::string reversed =
        UnifiedDiffParser::buildHunkPatch(parsed.files[0], parsed.files[0].hunks[0], true);

    // Reversing swaps the two sides; flipping only the line markers would produce
    // a patch git rejects.
    EXPECT_NE(reversed.find("@@ -20,3 +10,2 @@"), std::string::npos) << reversed;
    EXPECT_NE(reversed.find("-added"), std::string::npos) << reversed;
}

}  // namespace
}  // namespace gbm
