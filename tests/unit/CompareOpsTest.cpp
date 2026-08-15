// Tests for CompareOps, the M6 Compare-tab query layer (spec page 12):
// merge-base, the commit lists unique to each side of a two-ref comparison,
// the changed-file summary, and a single file's full diff. Uses
// FakeProcessRunner throughout, same convention as BranchOpsTest.cpp --
// these are read-only queries, so there is no Operation subclass to drive.
#include "core/git/ops/CompareOps.h"
#include "support/FakeProcessRunner.h"

#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

RepoPaths testPaths() {
    return RepoPaths("/repo", "/repo/.git", "/repo/.git");
}

const std::string kMergeBaseOid(40, 'c');
const std::string kLeftOnlyOid(40, 'a');
const std::string kRightOnlyOid(40, 'b');

TEST(CompareStore, ThreeDotCompareReturnsMergeBaseCommitsAndFiles) {
    FakeProcessRunner runner;

    FakeProcessRunner::Response mergeBaseResponse;
    mergeBaseResponse.exitCode = 0;
    mergeBaseResponse.out = kMergeBaseOid + "\n";
    runner.whenArgsContain({"merge-base", "main", "feature"}, mergeBaseResponse);

    FakeProcessRunner::Response logResponse;
    logResponse.exitCode = 0;
    logResponse.out = "<\x01" + kLeftOnlyOid + "\tAlice\t1700000000\tOld fix on main\n" + ">\x01" +
                      kRightOnlyOid + "\tBob\t1700000100\tNew fix on feature\n";
    runner.whenArgsContain({"log", "--left-right", "main...feature"}, logResponse);

    FakeProcessRunner::Response statusResponse;
    statusResponse.exitCode = 0;
    statusResponse.out = std::string("M", 1) + '\0' + "src/app.cpp" + '\0' + "A" + '\0' +
                         "src/new_file.cpp" + '\0';
    runner.whenArgsContain({"diff", "--name-status", "-M", "-z", "main...feature"}, statusResponse);

    FakeProcessRunner::Response numstatResponse;
    numstatResponse.exitCode = 0;
    numstatResponse.out =
        std::string("5\t2\tsrc/app.cpp") + '\0' + "10\t0\tsrc/new_file.cpp" + '\0';
    runner.whenArgsContain({"diff", "--numstat", "-M", "-z", "main...feature"}, numstatResponse);

    CompareStore store(runner, testPaths());
    CompareRequest request;
    request.leftRef = "main";
    request.rightRef = "feature";
    request.threeDot = true;

    GitResult<CompareResult> result = store.compare(request, CancellationToken{});

    ASSERT_TRUE(result);
    EXPECT_FALSE(result->mergeBase.isNull());
    EXPECT_EQ(result->mergeBase.hex(), kMergeBaseOid);

    ASSERT_EQ(result->commits.size(), 2u);
    EXPECT_FALSE(result->commits[0].onRightOnly);
    EXPECT_EQ(result->commits[0].oid.hex(), kLeftOnlyOid);
    EXPECT_EQ(result->commits[0].authorName, "Alice");
    EXPECT_EQ(result->commits[0].authorDate, 1700000000);
    EXPECT_EQ(result->commits[0].subject, "Old fix on main");
    EXPECT_TRUE(result->commits[1].onRightOnly);
    EXPECT_EQ(result->commits[1].oid.hex(), kRightOnlyOid);
    EXPECT_EQ(result->commits[1].authorName, "Bob");
    EXPECT_EQ(result->commits[1].subject, "New fix on feature");

    ASSERT_EQ(result->files.size(), 2u);
    EXPECT_EQ(result->files[0].kind, FileChangeKind::Modified);
    EXPECT_EQ(result->files[0].newPath, "src/app.cpp");
    EXPECT_EQ(result->files[0].addedLines, 5u);
    EXPECT_EQ(result->files[0].removedLines, 2u);
    EXPECT_FALSE(result->files[0].binary);
    EXPECT_EQ(result->files[1].kind, FileChangeKind::Added);
    EXPECT_EQ(result->files[1].newPath, "src/new_file.cpp");
    EXPECT_TRUE(result->files[1].oldPath.empty());
    EXPECT_EQ(result->files[1].addedLines, 10u);
}

TEST(CompareStore, ReturnsNullMergeBaseWhenHistoriesAreUnrelated) {
    FakeProcessRunner runner;

    // git merge-base exits 1 with empty stderr when there is no common
    // ancestor -- that is the documented "no merge base" signal, not an
    // error to propagate.
    FakeProcessRunner::Response noAncestor;
    noAncestor.exitCode = 1;
    runner.whenArgsContain({"merge-base", "orphan-a", "orphan-b"}, noAncestor);

    FakeProcessRunner::Response empty;
    empty.exitCode = 0;
    runner.whenArgsContain({"log", "--left-right", "orphan-a...orphan-b"}, empty);
    runner.whenArgsContain({"diff", "--name-status", "-M", "-z", "orphan-a...orphan-b"}, empty);
    runner.whenArgsContain({"diff", "--numstat", "-M", "-z", "orphan-a...orphan-b"}, empty);

    CompareStore store(runner, testPaths());
    CompareRequest request;
    request.leftRef = "orphan-a";
    request.rightRef = "orphan-b";

    GitResult<CompareResult> result = store.compare(request, CancellationToken{});

    ASSERT_TRUE(result);
    EXPECT_TRUE(result->mergeBase.isNull());
    EXPECT_TRUE(result->commits.empty());
    EXPECT_TRUE(result->files.empty());
}

TEST(CompareStore, TwoDotCompareOnlyReportsRightOnlyCommits) {
    FakeProcessRunner runner;

    FakeProcessRunner::Response mergeBaseResponse;
    mergeBaseResponse.exitCode = 0;
    mergeBaseResponse.out = kMergeBaseOid + "\n";
    runner.whenArgsContain({"merge-base", "main", "feature"}, mergeBaseResponse);

    // Two-dot (left..right) never yields a '<' entry: the range itself
    // excludes anything reachable from left before --left-right ever sees
    // it.
    FakeProcessRunner::Response logResponse;
    logResponse.exitCode = 0;
    logResponse.out = ">\x01" + kRightOnlyOid + "\tBob\t1700000100\tNew fix on feature\n";
    runner.whenArgsContain({"log", "--left-right", "main..feature"}, logResponse);

    FakeProcessRunner::Response empty;
    empty.exitCode = 0;
    runner.whenArgsContain({"diff", "--name-status", "-M", "-z", "main..feature"}, empty);
    runner.whenArgsContain({"diff", "--numstat", "-M", "-z", "main..feature"}, empty);

    CompareStore store(runner, testPaths());
    CompareRequest request;
    request.leftRef = "main";
    request.rightRef = "feature";
    request.threeDot = false;

    GitResult<CompareResult> result = store.compare(request, CancellationToken{});

    ASSERT_TRUE(result);
    ASSERT_EQ(result->commits.size(), 1u);
    EXPECT_TRUE(result->commits[0].onRightOnly);
    EXPECT_EQ(result->commits[0].oid.hex(), kRightOnlyOid);
}

TEST(CompareStore, RenamedFileMergesStatusAndNumstatRecords) {
    FakeProcessRunner runner;

    FakeProcessRunner::Response mergeBaseResponse;
    mergeBaseResponse.exitCode = 0;
    mergeBaseResponse.out = kMergeBaseOid + "\n";
    runner.whenArgsContain({"merge-base", "main", "feature"}, mergeBaseResponse);

    FakeProcessRunner::Response empty;
    empty.exitCode = 0;
    runner.whenArgsContain({"log", "--left-right", "main...feature"}, empty);

    FakeProcessRunner::Response statusResponse;
    statusResponse.exitCode = 0;
    statusResponse.out = std::string("R100") + '\0' + "src/old_name.cpp" + '\0' +
                         "src/new_name.cpp" + '\0';
    runner.whenArgsContain({"diff", "--name-status", "-M", "-z", "main...feature"}, statusResponse);

    // -z numstat rename record: added, removed, then an empty path field
    // (signalling "see the next two NUL records"), followed by old and new
    // path as separate records.
    FakeProcessRunner::Response numstatResponse;
    numstatResponse.exitCode = 0;
    numstatResponse.out = std::string("3\t1\t") + '\0' + "src/old_name.cpp" + '\0' +
                          "src/new_name.cpp" + '\0';
    runner.whenArgsContain({"diff", "--numstat", "-M", "-z", "main...feature"}, numstatResponse);

    CompareStore store(runner, testPaths());
    CompareRequest request;
    request.leftRef = "main";
    request.rightRef = "feature";

    GitResult<CompareResult> result = store.compare(request, CancellationToken{});

    ASSERT_TRUE(result);
    ASSERT_EQ(result->files.size(), 1u);
    EXPECT_EQ(result->files[0].kind, FileChangeKind::Renamed);
    EXPECT_EQ(result->files[0].similarity, 100);
    EXPECT_EQ(result->files[0].oldPath, "src/old_name.cpp");
    EXPECT_EQ(result->files[0].newPath, "src/new_name.cpp");
    EXPECT_EQ(result->files[0].addedLines, 3u);
    EXPECT_EQ(result->files[0].removedLines, 1u);
}

TEST(CompareStore, FailsWithInvalidArgumentWhenARefIsEmpty) {
    FakeProcessRunner runner;
    CompareStore store(runner, testPaths());
    CompareRequest request;
    request.leftRef = "main";
    request.rightRef = "";

    GitResult<CompareResult> result = store.compare(request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

TEST(CompareStore, CompareFileDiffParsesGitDiffOutputForOneFile) {
    FakeProcessRunner runner;

    FakeProcessRunner::Response diffResponse;
    diffResponse.exitCode = 0;
    diffResponse.out =
        "diff --git a/src/app.cpp b/src/app.cpp\n"
        "index 1111111..2222222 100644\n"
        "--- a/src/app.cpp\n"
        "+++ b/src/app.cpp\n"
        "@@ -1,2 +1,3 @@\n"
        " context line\n"
        "+added line\n"
        " another context line\n";
    runner.whenArgsContain({"diff", "main...feature", "--", "src/app.cpp"}, diffResponse);

    CompareStore store(runner, testPaths());
    CompareFileDiffRequest request;
    request.leftRef = "main";
    request.rightRef = "feature";
    request.path = "src/app.cpp";

    GitResult<ParsedDiff> result = store.compareFileDiff(request, CancellationToken{});

    ASSERT_TRUE(result);
    ASSERT_EQ(result->files.size(), 1u);
    EXPECT_EQ(result->files[0].newPath, "src/app.cpp");
    ASSERT_EQ(result->files[0].hunks.size(), 1u);
    EXPECT_EQ(result->files[0].hunks[0].lines.size(), 3u);
}

TEST(CompareStore, CompareFileDiffFailsWithInvalidArgumentWhenPathIsEmpty) {
    FakeProcessRunner runner;
    CompareStore store(runner, testPaths());
    CompareFileDiffRequest request;
    request.leftRef = "main";
    request.rightRef = "feature";

    GitResult<ParsedDiff> result = store.compareFileDiff(request, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::InvalidArgument);
    EXPECT_EQ(runner.invocationCount(), 0u);
}

}  // namespace
}  // namespace gbm
