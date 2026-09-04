#include "capi/JsonCodec.h"

#include <gtest/gtest.h>

namespace gbm::capi {
namespace {

TEST(JsonCodecTest, GitErrorEscapesAndEncodesEveryField) {
    GitError error(GitError::Code::Conflict, "merge conflict", "CONFLICT (content): \"quote\"\nline2");
    error.argv = {"git", "merge", "feature"};
    error.exitCode = 1;

    const std::string json = toJson(error);

    EXPECT_NE(json.find("\"code\":3"), std::string::npos);
    EXPECT_NE(json.find("\"codeName\":\"Conflict\""), std::string::npos);
    EXPECT_NE(json.find("\"message\":\"merge conflict\""), std::string::npos);
    // The embedded quote and newline in `detail` must be escaped, not raw.
    EXPECT_NE(json.find("\\\"quote\\\""), std::string::npos);
    EXPECT_NE(json.find("\\n"), std::string::npos);
    EXPECT_NE(json.find("\"argv\":[\"git\",\"merge\",\"feature\"]"), std::string::npos);
    EXPECT_NE(json.find("\"exitCode\":1"), std::string::npos);
}

TEST(JsonCodecTest, RepoStateEncodesCleanState) {
    RepoState state;
    const std::string json = toJson(state);

    EXPECT_NE(json.find("\"flags\":0"), std::string::npos);
    EXPECT_NE(json.find("\"isClean\":true"), std::string::npos);
    EXPECT_NE(json.find("\"indexLockAgeSeconds\":null"), std::string::npos);
}

TEST(JsonCodecTest, RepoStateEncodesInProgressMerge) {
    RepoState state;
    state.flags = RepoState::Merge;
    state.indexLockAgeSeconds = 42;

    const std::string json = toJson(state);

    EXPECT_NE(json.find("\"isClean\":false"), std::string::npos);
    EXPECT_NE(json.find("\"indexLockAgeSeconds\":42"), std::string::npos);
}

TEST(JsonCodecTest, CommitMetaEncodesParentsAndSignatures) {
    CommitMeta meta;
    meta.oid = ObjectId::fromHex(std::string(40, 'a'));
    meta.parents.push_back(ObjectId::fromHex(std::string(40, 'b')));
    meta.author.name = "Ada";
    meta.author.email = "ada@example.invalid";
    meta.subject = "Initial commit";

    const std::string json = toJson(meta);

    EXPECT_NE(json.find("\"oid\":\"" + std::string(40, 'a') + "\""), std::string::npos);
    EXPECT_NE(json.find("\"parents\":[\"" + std::string(40, 'b') + "\"]"), std::string::npos);
    EXPECT_NE(json.find("\"name\":\"Ada\""), std::string::npos);
    EXPECT_NE(json.find("\"subject\":\"Initial commit\""), std::string::npos);
}

TEST(JsonCodecTest, OperationOutcomeEncodesFailureWithChoices) {
    OperationOutcome outcome;
    outcome.succeeded = false;
    outcome.error = GitError(GitError::Code::DirtyWorkTree, "dirty work tree");
    outcome.choices.push_back(
        OperationChoice{OperationChoice::Kind::StashAndRetry, "Stash and retry", "explain", false});
    outcome.summary = "checkout failed";

    const std::string json = toJson(outcome);

    EXPECT_NE(json.find("\"succeeded\":false"), std::string::npos);
    EXPECT_NE(json.find("\"code\":8"), std::string::npos);  // DirtyWorkTree ordinal
    // kind=0 is StashAndRetry's ordinal; the wire carries only kind and
    // destructive now -- label/explanation are composed on the Flutter side
    // instead (recovery_choice_copy.dart), and never reach the wire at all,
    // even though the OperationChoice struct that produced this entry still
    // carries them (still-live construction fields above; the struct itself
    // is narrowed in a later, separate commit).
    EXPECT_NE(json.find("\"kind\":0,\"destructive\":false"), std::string::npos);
    EXPECT_EQ(json.find("\"label\""), std::string::npos);
    EXPECT_EQ(json.find("\"explanation\""), std::string::npos);
    EXPECT_NE(json.find("\"summary\":\"checkout failed\""), std::string::npos);
}

// The four line-count fields are independent on purpose: a partially staged
// file has real numbers on *both* sides at once, and that pair of pairs is
// exactly what the file list uses to say "part of this file is staged". A
// serializer that emitted one shared pair, or that reused another struct's
// `addedLines` key, would still look right in a repository-backed test where
// only one side is ever non-zero.
TEST(JsonCodecTest, WorkingCopyEntryEncodesAllFourLineCountsIndependently) {
    WorkingCopyEntry partiallyStaged;
    partiallyStaged.path = "both-sides.txt";
    partiallyStaged.staged = true;
    partiallyStaged.hasUnstagedChange = true;
    partiallyStaged.unstagedAdded = 34;
    partiallyStaged.unstagedRemoved = 12;
    partiallyStaged.stagedAdded = 7;
    partiallyStaged.stagedRemoved = 3;

    WorkingCopyStatus status;
    status.entries.push_back(partiallyStaged);

    const std::string json = toJson(status);

    EXPECT_NE(json.find("\"unstagedAdded\":34"), std::string::npos) << json;
    EXPECT_NE(json.find("\"unstagedRemoved\":12"), std::string::npos) << json;
    EXPECT_NE(json.find("\"stagedAdded\":7"), std::string::npos) << json;
    EXPECT_NE(json.find("\"stagedRemoved\":3"), std::string::npos) << json;
}

// Zero is "not measured", never "measured zero" -- binary files, mode-only
// changes and oversized untracked files all arrive here as 0 and the UI draws
// no badge for them. The keys still have to be present: a missing key becomes
// `null as int` on the Dart side, which is a crash rather than a blank badge.
TEST(JsonCodecTest, WorkingCopyEntryStillEmitsTheKeysWhenEveryCountIsZero) {
    WorkingCopyEntry binary;
    binary.path = "logo.png";
    binary.hasUnstagedChange = true;

    WorkingCopyStatus status;
    status.entries.push_back(binary);

    const std::string json = toJson(status);

    EXPECT_NE(json.find("\"unstagedAdded\":0"), std::string::npos) << json;
    EXPECT_NE(json.find("\"unstagedRemoved\":0"), std::string::npos) << json;
    EXPECT_NE(json.find("\"stagedAdded\":0"), std::string::npos) << json;
    EXPECT_NE(json.find("\"stagedRemoved\":0"), std::string::npos) << json;
}

TEST(JsonCodecTest, RepoRecordArrayEncodesMultipleEntries) {
    RepoRecord a;
    a.id = 1;
    a.workDir = "/repos/a";
    a.name = "a";
    RepoRecord b;
    b.id = 2;
    b.workDir = "/repos/b";
    b.name = "b";

    const std::string json = toJson(std::vector<RepoRecord>{a, b});

    EXPECT_EQ(json.front(), '[');
    EXPECT_EQ(json.back(), ']');
    EXPECT_NE(json.find("\"workDir\":\"/repos/a\""), std::string::npos);
    EXPECT_NE(json.find("\"workDir\":\"/repos/b\""), std::string::npos);
}

TEST(JsonCodecTest, EmptyRepoRecordArrayEncodesAsEmptyArray) {
    EXPECT_EQ(toJson(std::vector<RepoRecord>{}), "[]");
}


// A worktree's pending-change count is a **tri-state**, not a sentinel
// number. `0` here has to mean "measured, and genuinely clean" -- that is
// the answer the user sees most often and most needs to trust -- so "not
// measured" lives in a separate field rather than borrowing a value from
// the number's own range.
//
// This is deliberately the inverse of WorkingCopyEntry's four line-count
// fields, where 0 means "not measured": there, a path with no matching
// numstat record and a path with a genuine zero are indistinguishable by
// construction, so 0 had to absorb both. Here the command either ran or it
// did not, and "did not" has somewhere else to live.
TEST(JsonCodecTest, WorktreeMeasuredZeroIsNotUnmeasured) {
    WorktreeInfo worktree;
    worktree.path = "/repo";
    worktree.pendingChanges = 0;
    worktree.pendingCountState = WorktreePendingCountState::Measured;

    const std::string json = toJson(worktree);

    EXPECT_NE(json.find("\"pendingChanges\":0"), std::string::npos);
    EXPECT_NE(json.find("\"pendingCountState\":\"measured\""), std::string::npos);
}

TEST(JsonCodecTest, WorktreePendingCountDefaultsToUnmeasured) {
    WorktreeInfo worktree;
    worktree.path = "/repo";

    const std::string json = toJson(worktree);

    EXPECT_NE(json.find("\"pendingCountState\":\"unmeasured\""), std::string::npos);
}

TEST(JsonCodecTest, WorktreeEncodesEverySkipAndFailureState) {
    WorktreeInfo bare;
    bare.pendingCountState = WorktreePendingCountState::NotApplicable;
    EXPECT_NE(toJson(bare).find("\"pendingCountState\":\"notApplicable\""),
              std::string::npos);

    WorktreeInfo failed;
    failed.pendingCountState = WorktreePendingCountState::Failed;
    EXPECT_NE(toJson(failed).find("\"pendingCountState\":\"failed\""),
              std::string::npos);
}

// git records no creation time for a worktree; this is the unix timestamp of
// the first entry in its own `logs/HEAD`, and 0 means "git did not record
// one" rather than the epoch.
TEST(JsonCodecTest, WorktreeCreatedAtIsAbsentAsZero) {
    WorktreeInfo worktree;
    EXPECT_NE(toJson(worktree).find("\"createdAtUnix\":0"), std::string::npos);

    worktree.createdAtUnix = 1780000000;
    EXPECT_NE(toJson(worktree).find("\"createdAtUnix\":1780000000"),
              std::string::npos);
}

}  // namespace
}  // namespace gbm::capi
