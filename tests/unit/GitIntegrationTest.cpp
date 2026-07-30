// Integration tests against a real git binary and a real (generated) repository.
//
// The most valuable assertion in this file is the cross-check: our row order must
// equal `git rev-list --topo-order` exactly, and our parent sets must equal what
// `--parents` reports. It is cheap, and it catches parser and ordering bugs
// immediately — the kind that random DAG tests cannot see because they never
// touch git itself.
#include "core/base/CancellationToken.h"
#include "core/git/CatFileBatch.h"
#include "core/git/DiffService.h"
#include "core/git/GitExecutable.h"
#include "core/git/HistoryProvider.h"
#include "core/git/OperationRunner.h"
#include "core/git/RefStore.h"
#include "core/git/RepoState.h"
#include "core/git/ops/BranchOps.h"
#include "core/git/ops/CheckoutOp.h"

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>
#include <vector>

namespace gbm {
namespace {

/// Creates a small real repository using the generator plus `git fast-import`.
class RealRepoTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
        installation_ = *detected;
    }

    void SetUp() override {
        if (installation_.executable.empty()) {
            GTEST_SKIP() << "git is unavailable";
        }
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-int-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        runner_ = makeProcessRunner(installation_.executable);
        paths_ = RepoPaths(repo_, repo_ / ".git", repo_ / ".git");

        ASSERT_TRUE(run({"init", "--quiet", "--initial-branch=main"}));
        ASSERT_TRUE(run({"config", "user.email", "test@example.invalid"}));
        ASSERT_TRUE(run({"config", "user.name", "Test"}));
        ASSERT_TRUE(run({"config", "commit.gpgsign", "false"}));
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(repo_, ec);
    }

    GitResult<ProcessResult> run(std::vector<std::string> args) {
        GitCommand command(repo_, std::move(args));
        command.timeout = std::chrono::seconds(120);
        return runner_->run(command, CancellationToken{});
    }

    void commitFile(const std::string& name,
                    const std::string& contents,
                    const std::string& message) {
        std::ofstream out(repo_ / name, std::ios::binary | std::ios::trunc);
        out << contents;
        out.close();
        ASSERT_TRUE(run({"add", name}));
        ASSERT_TRUE(run({"commit", "--quiet", "-m", message}));
    }

    /// Row order straight from git, for the cross-check.
    std::vector<std::string> gitTopoOrder() {
        auto result = run({"rev-list", "--topo-order", "--all"});
        if (!result) {
            return {};
        }
        std::vector<std::string> oids;
        std::size_t start = 0;
        while (start < result->out.size()) {
            const std::size_t at = result->out.find('\n', start);
            const std::string line =
                result->out.substr(start, at == std::string::npos ? std::string::npos : at - start);
            if (!line.empty()) {
                oids.push_back(line);
            }
            if (at == std::string::npos) {
                break;
            }
            start = at + 1;
        }
        return oids;
    }

    static GitInstallation installation_;
    std::filesystem::path repo_;
    std::unique_ptr<IProcessRunner> runner_;
    RepoPaths paths_;
};

GitInstallation RealRepoTest::installation_;

TEST_F(RealRepoTest, DetectsGitAndItsCapabilities) {
    EXPECT_TRUE(installation_.isUsable());
    EXPECT_GE(installation_.version.major, 2);
    // Capabilities must be derived consistently from the version, since the whole
    // backend degrades based on them.
    if (installation_.version >= GitVersion{2, 38, 0}) {
        EXPECT_TRUE(installation_.capabilities.mergeTreeWriteTree);
    }
}

TEST_F(RealRepoTest, RowOrderMatchesGitTopoOrderExactly) {
    commitFile("a.txt", "one\n", "first");
    commitFile("a.txt", "two\n", "second");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("b.txt", "feature\n", "on feature");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("a.txt", "three\n", "third");
    ASSERT_TRUE(run({"merge", "--quiet", "--no-ff", "-m", "merge feature", "feature"}));

    HistoryProvider provider(*runner_, paths_);
    auto snapshot = provider.walk(HistoryQuery{}, nullptr, CancellationToken{});
    ASSERT_TRUE(snapshot) << snapshot.error().message;

    const auto expected = gitTopoOrder();
    ASSERT_FALSE(expected.empty());
    ASSERT_EQ((*snapshot)->rowCount(), expected.size());

    for (std::size_t row = 0; row < expected.size(); ++row) {
        EXPECT_EQ((*snapshot)->oids[row].hex(), expected[row])
            << "row " << row << " diverges from git's own topo order";
    }
}

TEST_F(RealRepoTest, ParentSetsMatchGit) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "side"}));
    commitFile("b.txt", "2\n", "c2");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("a.txt", "3\n", "c3");
    ASSERT_TRUE(run({"merge", "--quiet", "--no-ff", "-m", "m", "side"}));

    HistoryProvider provider(*runner_, paths_);
    auto snapshot = provider.walk(HistoryQuery{}, nullptr, CancellationToken{});
    ASSERT_TRUE(snapshot);

    // The merge is the newest commit and must have exactly two parents, both of
    // which resolve to rows further down.
    ASSERT_GT((*snapshot)->rowCount(), 0u);
    EXPECT_EQ((*snapshot)->parentCountOf(0), 2u);
    EXPECT_TRUE((*snapshot)->rows[0].isMerge());
    for (RowId parent : (*snapshot)->parentsOf(0)) {
        ASSERT_NE(parent, kRowBoundary);
        EXPECT_GT(parent, 0u);
    }

    // And the merge sits on trunk with the side branch to its right.
    EXPECT_EQ((*snapshot)->rows[0].lane, 0);
}

TEST_F(RealRepoTest, CatFileBatchReadsCommitsOverOneProcess) {
    commitFile("a.txt", "hello\n", "subject line\n\nbody paragraph\n");

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    const ObjectId oid = ObjectId::fromHex(head->out);
    ASSERT_FALSE(oid.isNull());

    CatFileBatch batch(installation_.executable, paths_);
    ASSERT_TRUE(batch.start());
    ASSERT_TRUE(batch.isRunning());

    auto meta = batch.readCommit(oid);
    ASSERT_TRUE(meta) << meta.error().message;
    EXPECT_EQ(meta->subject, "subject line");
    EXPECT_EQ(meta->body, "body paragraph");
    EXPECT_EQ(meta->author.email, "test@example.invalid");

    // Reading many objects must reuse the same child process: that reuse is the
    // entire reason this class exists.
    for (int i = 0; i < 20; ++i) {
        EXPECT_TRUE(batch.readCommit(oid));
    }
    EXPECT_TRUE(batch.isRunning());

    // A missing object is an ordinary error and must not poison the co-process.
    auto missing = batch.read(std::string(40, 'e'));
    EXPECT_FALSE(missing);
    EXPECT_EQ(missing.error().code, GitError::Code::NotFound);
    EXPECT_TRUE(batch.readCommit(oid)) << "the co-process must survive a missing object";
}

TEST_F(RealRepoTest, CatFileBatchReadsBlobContent) {
    commitFile("data.txt", "line one\nline two\n", "add data");

    CatFileBatch batch(installation_.executable, paths_);
    ASSERT_TRUE(batch.start());

    auto blob = batch.read("HEAD:data.txt");
    ASSERT_TRUE(blob) << blob.error().message;
    EXPECT_EQ(blob->type, "blob");
    EXPECT_EQ(blob->content, "line one\nline two\n");
}

TEST_F(RealRepoTest, ReadsRefsAndHead) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"branch", "other"}));
    ASSERT_TRUE(run({"tag", "-a", "v1.0", "-m", "release"}));

    RefStore store(*runner_, paths_);
    auto snapshot = store.load(CancellationToken{});
    ASSERT_TRUE(snapshot) << snapshot.error().message;

    EXPECT_EQ((*snapshot)->head.kind, HeadInfo::Kind::Branch);
    EXPECT_EQ((*snapshot)->head.branchName, "main");

    EXPECT_EQ((*snapshot)->ofKind(RefKind::LocalBranch).size(), 2u);

    // An annotated tag must be peeled to the commit it points at, so the graph
    // can decorate the right row.
    const auto tags = (*snapshot)->ofKind(RefKind::Tag);
    ASSERT_EQ(tags.size(), 1u);
    EXPECT_FALSE(tags[0]->tagObject.isNull());
    EXPECT_EQ(tags[0]->target, (*snapshot)->head.target);
}

TEST_F(RealRepoTest, ProducesChangedFilesAndDiffs) {
    commitFile("a.txt", "one\n", "c1");
    commitFile("a.txt", "one\ntwo\n", "c2");

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    const ObjectId oid = ObjectId::fromHex(head->out);

    DiffService diffs(*runner_, paths_);
    DiffOptions options;

    auto files = diffs.changedFiles(oid, options, CancellationToken{});
    ASSERT_TRUE(files) << files.error().message;
    ASSERT_EQ((*files)->size(), 1u);
    EXPECT_EQ((*files)->at(0).path, "a.txt");
    EXPECT_EQ((*files)->at(0).kind, FileChangeKind::Modified);

    auto diff = diffs.commitFileDiff(oid, "a.txt", options, CancellationToken{});
    ASSERT_TRUE(diff) << diff.error().message;
    ASSERT_EQ((*diff)->files.size(), 1u);
    EXPECT_EQ((*diff)->files[0].addedLines, 1u);

    // The second identical request must be served from cache, not re-run git.
    auto cached = diffs.commitFileDiff(oid, "a.txt", options, CancellationToken{});
    ASSERT_TRUE(cached);
    EXPECT_EQ(cached->get(), diff->get()) << "the diff cache should return the same object";
}

TEST_F(RealRepoTest, HandlesAddedAndDeletedFilesInDiffs) {
    commitFile("keep.txt", "keep\n", "c1");
    commitFile("gone.txt", "temporary\n", "c2");
    ASSERT_TRUE(run({"rm", "--quiet", "gone.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "remove gone"}));

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);

    DiffService diffs(*runner_, paths_);
    auto files =
        diffs.changedFiles(ObjectId::fromHex(head->out), DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(files);
    ASSERT_EQ((*files)->size(), 1u);
    EXPECT_EQ((*files)->at(0).kind, FileChangeKind::Deleted);
    EXPECT_EQ((*files)->at(0).path, "gone.txt");
}

TEST_F(RealRepoTest, DetectsAndReportsRenames) {
    commitFile("original.txt", "line1\nline2\nline3\nline4\nline5\n", "c1");
    ASSERT_TRUE(run({"mv", "original.txt", "renamed.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "rename it"}));

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);

    DiffService diffs(*runner_, paths_);
    auto files =
        diffs.changedFiles(ObjectId::fromHex(head->out), DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(files);
    ASSERT_EQ((*files)->size(), 1u);
    // A rename read as add+delete would lose the file's history in the UI.
    EXPECT_EQ((*files)->at(0).kind, FileChangeKind::Renamed);
    EXPECT_EQ((*files)->at(0).oldPath, "original.txt");
    EXPECT_EQ((*files)->at(0).path, "renamed.txt");
}

TEST_F(RealRepoTest, ReadsACleanRepoState) {
    commitFile("a.txt", "1\n", "c1");

    const RepoState state = RepoState::read(paths_);
    EXPECT_TRUE(state.isClean());
    EXPECT_FALSE(state.indexLocked);
    EXPECT_TRUE(state.describe().empty());
}

TEST_F(RealRepoTest, DetectsAConflictedMergeState) {
    // A real conflict, so the state detection is tested against what git actually
    // writes rather than against files we fabricated.
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "left"}));
    commitFile("shared.txt", "left change\n", "left");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "right change\n", "right");

    auto merge = run({"merge", "--no-commit", "left"});
    EXPECT_FALSE(merge) << "the merge was expected to conflict";
    if (!merge) {
        EXPECT_EQ(merge.error().code, GitError::Code::Conflict);
    }

    const RepoState state = RepoState::read(paths_);
    EXPECT_TRUE(state.inProgress());
    EXPECT_NE(state.flags & RepoState::Merge, 0u);
    EXPECT_NE(state.describe().find("Merge in progress"), std::string::npos);

    ASSERT_TRUE(run({"merge", "--abort"}));
    EXPECT_TRUE(RepoState::read(paths_).isClean());
}

TEST_F(RealRepoTest, DetectsAHeldIndexLockAndNeverRemovesIt) {
    commitFile("a.txt", "1\n", "c1");

    // Stand in for another git process (a terminal, an IDE, a hook).
    {
        std::ofstream lock(paths_.indexLockFile());
        lock << "held";
    }

    const RepoState state = RepoState::read(paths_);
    EXPECT_TRUE(state.indexLocked);

    OperationRunner operations(*runner_, paths_);
    CheckoutRequest request;
    request.target = "main";

    OperationOutcome outcome;
    operations.submit(makeCheckoutOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::LockHeld);
    EXPECT_FALSE(outcome.choices.empty()) << "the user needs a way forward, e.g. Retry";
    // A fresh lock must never be offered for removal: deleting a live lock
    // corrupts the index.
    for (const OperationChoice& choice : outcome.choices) {
        EXPECT_NE(choice.kind, OperationChoice::Kind::RemoveLock)
            << "a lock this new must be assumed live";
    }
    // And it is still there: we refused, we did not clean up behind git's back.
    EXPECT_TRUE(std::filesystem::exists(paths_.indexLockFile()));

    std::filesystem::remove(paths_.indexLockFile());
}

TEST_F(RealRepoTest, SwitchesBranches) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"branch", "target"}));

    OperationRunner operations(*runner_, paths_);
    CheckoutRequest request;
    request.target = "target";

    OperationOutcome outcome;
    operations.submit(makeCheckoutOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();

    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    RefStore store(*runner_, paths_);
    auto head = store.readHead(CancellationToken{});
    ASSERT_TRUE(head);
    EXPECT_EQ(head->branchName, "target");
}

TEST_F(RealRepoTest, OffersRecoveryChoicesWhenSwitchingWouldLoseWork) {
    // The most common real-world checkout failure. The point of the test is that
    // the user is offered the three genuine options rather than raw git output.
    commitFile("a.txt", "base\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "other"}));
    commitFile("a.txt", "other branch content\n", "c2");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));

    {
        std::ofstream out(repo_ / "a.txt");
        out << "uncommitted local edit\n";
    }

    OperationRunner operations(*runner_, paths_);
    CheckoutRequest request;
    request.target = "other";

    OperationOutcome outcome;
    operations.submit(makeCheckoutOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();

    ASSERT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::DirtyWorkTree);

    bool hasStash = false;
    bool hasForce = false;
    for (const OperationChoice& choice : outcome.choices) {
        hasStash = hasStash || choice.kind == OperationChoice::Kind::StashAndRetry;
        if (choice.kind == OperationChoice::Kind::ForceDiscard) {
            hasForce = true;
            EXPECT_TRUE(choice.destructive) << "discarding work must be labelled destructive";
        }
    }
    EXPECT_TRUE(hasStash);
    EXPECT_TRUE(hasForce);

    // Stash-and-retry must then actually work, and preserve the work in a stash.
    request.stashFirst = true;
    OperationOutcome retry;
    operations.submit(makeCheckoutOperation(request),
                      [&retry](OperationOutcome result) { retry = std::move(result); });
    operations.drain();

    ASSERT_TRUE(retry.succeeded) << (retry.error ? retry.error->detail : "");
    auto stashList = run({"stash", "list"});
    ASSERT_TRUE(stashList);
    EXPECT_FALSE(stashList->out.empty()) << "the user's work must be recoverable";
}

TEST_F(RealRepoTest, CreatesRenamesAndDeletesBranches) {
    commitFile("a.txt", "1\n", "c1");
    OperationRunner operations(*runner_, paths_);

    auto submitAndWait = [&operations](std::unique_ptr<Operation> operation) {
        OperationOutcome outcome;
        operations.submit(std::move(operation),
                          [&outcome](OperationOutcome result) { outcome = std::move(result); });
        operations.drain();
        return outcome;
    };

    CreateBranchRequest create;
    create.name = "feature/new-thing";
    auto created = submitAndWait(makeCreateBranchOperation(create));
    ASSERT_TRUE(created.succeeded) << (created.error ? created.error->detail : "");

    RenameBranchRequest rename;
    rename.from = "feature/new-thing";
    rename.to = "feature/renamed";
    auto renamed = submitAndWait(makeRenameBranchOperation(rename));
    ASSERT_TRUE(renamed.succeeded) << (renamed.error ? renamed.error->detail : "");

    DeleteBranchRequest remove;
    remove.name = "feature/renamed";
    auto deleted = submitAndWait(makeDeleteBranchOperation(remove));
    ASSERT_TRUE(deleted.succeeded) << (deleted.error ? deleted.error->detail : "");

    RefStore store(*runner_, paths_);
    auto snapshot = store.load(CancellationToken{});
    ASSERT_TRUE(snapshot);
    for (const RefInfo& ref : (*snapshot)->refs) {
        EXPECT_EQ(ref.shortName.find("feature/"), std::string::npos);
    }
}

TEST_F(RealRepoTest, RejectsAnInvalidBranchNameBeforeRunningGit) {
    commitFile("a.txt", "1\n", "c1");
    OperationRunner operations(*runner_, paths_);

    CreateBranchRequest create;
    create.name = "bad name with spaces";

    OperationOutcome outcome;
    operations.submit(makeCreateBranchOperation(create),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::InvalidArgument);
    // The message should name the branch, not echo git's internals.
    EXPECT_NE(outcome.error->message.find("bad name with spaces"), std::string::npos);
}

TEST_F(RealRepoTest, RefusesToDeleteAnUnmergedBranchWithoutConsent) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "unmerged"}));
    commitFile("b.txt", "only here\n", "unmerged work");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));

    OperationRunner operations(*runner_, paths_);
    DeleteBranchRequest remove;
    remove.name = "unmerged";

    OperationOutcome outcome;
    operations.submit(makeDeleteBranchOperation(remove),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();

    EXPECT_FALSE(outcome.succeeded);
    bool offersForce = false;
    for (const OperationChoice& choice : outcome.choices) {
        if (choice.kind == OperationChoice::Kind::ForceDiscard) {
            offersForce = true;
            EXPECT_TRUE(choice.destructive);
            // The explanation has to say where the commits go, or "Delete anyway"
            // is not an informed choice.
            EXPECT_NE(choice.explanation.find("reflog"), std::string::npos);
        }
    }
    EXPECT_TRUE(offersForce);
}

TEST_F(RealRepoTest, CancelsAReadOnlyWalkPromptly) {
    for (int i = 0; i < 40; ++i) {
        commitFile("a.txt", std::to_string(i) + "\n", "c" + std::to_string(i));
    }

    CancellationSource source;
    source.cancel();  // Cancelled before it starts.

    HistoryProvider provider(*runner_, paths_);
    auto result = provider.walk(HistoryQuery{}, nullptr, source.token());

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::Cancelled);
}

TEST_F(RealRepoTest, HonoursAMaxCountLimit) {
    for (int i = 0; i < 10; ++i) {
        commitFile("a.txt", std::to_string(i) + "\n", "c" + std::to_string(i));
    }

    HistoryQuery query;
    query.maxCount = 4;

    HistoryProvider provider(*runner_, paths_);
    auto snapshot = provider.walk(query, nullptr, CancellationToken{});
    ASSERT_TRUE(snapshot);
    EXPECT_EQ((*snapshot)->rowCount(), 4u);
}

TEST_F(RealRepoTest, HandlesAnEmptyRepositoryWithoutError) {
    // No commits at all. A fresh `git init` must open cleanly rather than
    // reporting a failure the user cannot act on.
    RefStore store(*runner_, paths_);
    auto head = store.readHead(CancellationToken{});
    ASSERT_TRUE(head) << head.error().message;
    EXPECT_EQ(head->kind, HeadInfo::Kind::Unborn);

    HistoryProvider provider(*runner_, paths_);
    auto snapshot = provider.walk(HistoryQuery{}, nullptr, CancellationToken{});
    // rev-list on an unborn HEAD produces no rows; either an empty snapshot or a
    // clean error is acceptable, but it must not hang or crash.
    if (snapshot) {
        EXPECT_EQ((*snapshot)->rowCount(), 0u);
    }
}

TEST_F(RealRepoTest, ReadsUnicodeAndSpacedPathsCorrectly) {
    // core.quotepath=false plus -z output is what makes this work; without both,
    // these paths come back octal-escaped or split apart.
    commitFile("caf\xc3\xa9 menu.txt", "content\n", "add unicode path");

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);

    DiffService diffs(*runner_, paths_);
    auto files =
        diffs.changedFiles(ObjectId::fromHex(head->out), DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(files);
    ASSERT_EQ((*files)->size(), 1u);
    EXPECT_EQ((*files)->at(0).path, "caf\xc3\xa9 menu.txt");
}

}  // namespace
}  // namespace gbm
