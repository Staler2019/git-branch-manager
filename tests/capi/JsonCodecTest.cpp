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
    EXPECT_NE(json.find("\"label\":\"Stash and retry\""), std::string::npos);
    EXPECT_NE(json.find("\"summary\":\"checkout failed\""), std::string::npos);
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

}  // namespace
}  // namespace gbm::capi
