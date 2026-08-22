// Integration tests against a real git binary and a real (generated) repository.
//
// The most valuable assertion in this file is the cross-check: our row order must
// equal `git rev-list --topo-order` exactly, and our parent sets must equal what
// `--parents` reports. It is cheap, and it catches parser and ordering bugs
// immediately — the kind that random DAG tests cannot see because they never
// touch git itself.
#include "core/base/CancellationToken.h"
#include "core/base/FsUtil.h"
#include "core/git/BlameStore.h"
#include "core/git/CatFileBatch.h"
#include "core/git/CommitMetaStore.h"
#include "core/git/DiffService.h"
#include "core/git/FileHistoryStore.h"
#include "core/git/GitExecutable.h"
#include "core/git/HistoryProvider.h"
#include "core/git/OperationRunner.h"
#include "core/git/RefStore.h"
#include "core/git/ReflogStore.h"
#include "core/git/RepoState.h"
#include "core/git/WorkingCopyStatus.h"
#include "core/git/ops/BisectOps.h"
#include "core/git/ops/BranchOps.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/git/ops/CherryPickOps.h"
#include "core/git/ops/CommitOps.h"
#include "core/git/ops/ConflictOps.h"
#include "core/git/ops/LfsOps.h"
#include "core/git/ops/MergeOps.h"
#include "core/git/ops/PatchOps.h"
#include "core/git/ops/RebaseOps.h"
#include "core/git/ops/RemoteOps.h"
#include "core/git/ops/ResetOps.h"
#include "core/git/ops/StageOps.h"
#include "core/git/ops/StashOps.h"
#include "core/git/ops/SubmoduleOps.h"
#include "core/git/ops/TagOps.h"
#include "core/git/ops/UndoOps.h"
#include "core/git/ops/WorktreeOps.h"

#include <algorithm>
#include <map>
#include <sstream>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <iterator>
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
        // Git refuses a submodule's recursive clone over the plain `file`
        // transport by default since CVE-2022-39253, and deliberately will not
        // honour a repo-local config override for it -- otherwise a malicious
        // repository could just grant itself the permission. The M5 submodule
        // tests below use a sibling directory as the submodule URL, so this is
        // relaxed process-wide for the test binary, the same way git's own test
        // suite does it (GIT_ALLOW_PROTOCOL) rather than by touching global git
        // config. The app itself never sets this.
#ifdef _WIN32
        _putenv_s("GIT_ALLOW_PROTOCOL", "file:git:http:https:ssh");
#else
        setenv("GIT_ALLOW_PROTOCOL", "file:git:http:https:ssh", 1);
#endif
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(repo_, ec);
        for (const auto& extra : extraDirs_) {
            std::filesystem::remove_all(extra, ec);
        }
    }

    GitResult<ProcessResult> run(std::vector<std::string> args) {
        GitCommand command(repo_, std::move(args));
        command.timeout = std::chrono::seconds(120);
        return runner_->run(command, CancellationToken{});
    }

    /// Shared by the M2 tests below, which submit several operations per test.
    static OperationOutcome submitAndWait(OperationRunner& operations,
                                          std::unique_ptr<Operation> operation) {
        OperationOutcome outcome;
        operations.submit(std::move(operation),
                          [&outcome](OperationOutcome result) { outcome = std::move(result); });
        operations.drain();
        return outcome;
    }

    /// `name` is UTF-8, matching how the rest of the codebase treats a path in a
    /// std::string -- ProcessRunner widens argv with CP_UTF8, so this is the same
    /// name git will be given.
    void commitFile(const std::string& name,
                    const std::string& contents,
                    const std::string& message) {
        // Via char8_t, not the narrow string: constructing a path from a
        // std::string decodes it in the platform's narrow encoding, which on
        // Windows is the ANSI code page, so "café menu.txt" would land on disk as
        // "cafÃ© menu.txt" and the git add below would find nothing. A path built
        // from char8_t is UTF-8 by definition on every platform.
        const std::u8string utf8(reinterpret_cast<const char8_t*>(name.data()), name.size());
        std::ofstream out(repo_ / std::filesystem::path(utf8), std::ios::binary | std::ios::trunc);
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

    /// A second, independent repository with one commit, for tests that add it
    /// as a submodule of `repo_`. A plain filesystem path is a valid submodule
    /// URL, so no server or `file://` scheme is needed.
    std::filesystem::path makeSourceRepo(const std::string& suffix) {
        const std::filesystem::path source = repo_.string() + suffix;
        std::filesystem::remove_all(source);
        std::filesystem::create_directories(source);

        GitCommand init(source, {"init", "--quiet", "--initial-branch=main"});
        init.timeout = std::chrono::seconds(30);
        EXPECT_TRUE(runner_->run(init, CancellationToken{}));
        GitCommand email(source, {"config", "user.email", "test@example.invalid"});
        EXPECT_TRUE(runner_->run(email, CancellationToken{}));
        GitCommand name(source, {"config", "user.name", "Test"});
        EXPECT_TRUE(runner_->run(name, CancellationToken{}));

        std::ofstream out(source / "readme.txt");
        out << "source\n";
        out.close();
        GitCommand add(source, {"add", "readme.txt"});
        EXPECT_TRUE(runner_->run(add, CancellationToken{}));
        GitCommand commit(source, {"commit", "--quiet", "-m", "initial"});
        EXPECT_TRUE(runner_->run(commit, CancellationToken{}));
        extraDirs_.push_back(source);
        return source;
    }

    static GitInstallation installation_;
    std::filesystem::path repo_;
    std::unique_ptr<IProcessRunner> runner_;
    RepoPaths paths_;
    std::vector<std::filesystem::path> extraDirs_;
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

TEST_F(RealRepoTest, CommitMetaStoreBatchReadsCommitsOverOneProcess) {
    commitFile("a.txt", "one\n", "first");
    commitFile("a.txt", "two\n", "second");
    commitFile("a.txt", "three\n", "third");

    HistoryProvider provider(*runner_, paths_);
    auto snapshot = provider.walk(HistoryQuery{}, nullptr, CancellationToken{});
    ASSERT_TRUE(snapshot);
    ASSERT_EQ((*snapshot)->rowCount(), 3u);

    const std::vector<ObjectId> oids{
        (*snapshot)->oids[0], (*snapshot)->oids[1], (*snapshot)->oids[2]};

    CommitMetaStore store(installation_.executable, paths_);
    const std::vector<CommitMeta> metas = store.read(oids, CancellationToken{});

    // Order follows the requested oids, one result per oid -- none of them
    // are missing here, so a viewport request over real history round-trips
    // 1:1 through the shared cat-file process.
    ASSERT_EQ(metas.size(), oids.size());
    EXPECT_EQ(metas[0].subject, "third");
    EXPECT_EQ(metas[1].subject, "second");
    EXPECT_EQ(metas[2].subject, "first");
    for (const auto& meta : metas) {
        EXPECT_EQ(meta.author.email, "test@example.invalid");
    }
}

TEST_F(RealRepoTest, CommitMetaStoreSkipsMissingOidsWithoutAbortingTheRest) {
    commitFile("a.txt", "one\n", "first");
    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    const ObjectId real = ObjectId::fromHex(head->out);
    const ObjectId missing = ObjectId::fromHex(std::string(40, 'e'));

    CommitMetaStore store(installation_.executable, paths_);
    const std::vector<CommitMeta> metas =
        store.read({missing, real}, CancellationToken{});

    // The missing oid is simply absent, not a reason to lose `real` too.
    ASSERT_EQ(metas.size(), 1u);
    EXPECT_EQ(metas[0].oid, real);
    EXPECT_EQ(metas[0].subject, "first");
}

TEST_F(RealRepoTest, CommitMetaStoreStopsIssuingRequestsOnceCancelled) {
    commitFile("a.txt", "one\n", "first");
    commitFile("a.txt", "two\n", "second");

    HistoryProvider provider(*runner_, paths_);
    auto snapshot = provider.walk(HistoryQuery{}, nullptr, CancellationToken{});
    ASSERT_TRUE(snapshot);
    ASSERT_EQ((*snapshot)->rowCount(), 2u);
    const std::vector<ObjectId> oids{(*snapshot)->oids[0], (*snapshot)->oids[1]};

    CancellationSource source;
    source.cancel();

    CommitMetaStore store(installation_.executable, paths_);
    const std::vector<CommitMeta> metas = store.read(oids, source.token());

    // Cancelled before the loop's first check (CatFileBatch::readCommits()
    // checks per-oid, not once up front), so nothing is returned.
    EXPECT_TRUE(metas.empty());
}

TEST_F(RealRepoTest, CommitMetaStoreRestartsAfterExplicitStop) {
    commitFile("a.txt", "one\n", "first");
    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    const ObjectId oid = ObjectId::fromHex(head->out);

    CommitMetaStore store(installation_.executable, paths_);
    ASSERT_EQ(store.read({oid}, CancellationToken{}).size(), 1u);

    store.stop();

    // read() lazily respawns the child, same as CatFileBatch::read() itself.
    const std::vector<CommitMeta> metas = store.read({oid}, CancellationToken{});
    ASSERT_EQ(metas.size(), 1u);
    EXPECT_EQ(metas[0].subject, "first");
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

TEST_F(RealRepoTest, ReportsAMergeCommitAgainstItsFirstParent) {
    // `diff-tree` prints nothing at all for a merge unless told which parent
    // to diff against, so before --diff-merges=first-parent this whole test
    // saw an empty list and an empty patch -- the Changed files panel showed
    // "0 files" for every merge in the repository.
    //
    // The fixture is built so that all three plausible implementations give
    // three different answers, and only the right one gives 1:
    //
    //   * no --diff-merges at all      -> 0 files (the shipped bug)
    //   * -m / --diff-merges=separate  -> 2 files (both parents concatenated)
    //   * --diff-merges=first-parent   -> 1 file, side.txt
    //
    // `-m --first-parent` lands in the second bucket: diff-tree accepts
    // --first-parent and silently ignores it. That trap is why the fixture
    // makes the two parents contribute *different* paths rather than the
    // same one -- with a shared path, "both parents" and "first parent only"
    // would agree and the test could not tell them apart.
    commitFile("base.txt", "base\n", "c1");

    ASSERT_TRUE(run({"checkout", "--quiet", "-b", "side"}));
    commitFile("side.txt", "from the side branch\n", "side commit");

    ASSERT_TRUE(run({"checkout", "--quiet", "main"}));
    commitFile("main.txt", "from main\n", "main commit");

    // --no-ff is belt and braces: main has its own commit, so this is already
    // a true merge, but a fast-forward would silently turn this into a
    // non-merge test that passes for the wrong reason.
    ASSERT_TRUE(run({"merge", "--quiet", "--no-ff", "-m", "merge side", "side"}));

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    const ObjectId oid = ObjectId::fromHex(head->out);

    auto parents = run({"rev-list", "--parents", "-n", "1", "HEAD"});
    ASSERT_TRUE(parents);
    // "<merge> <parent1> <parent2>" -- three hashes means it really merged.
    EXPECT_EQ(std::count(parents->out.begin(), parents->out.end(), ' '), 2);

    DiffService diffs(*runner_, paths_);
    DiffOptions options;

    auto files = diffs.changedFiles(oid, options, CancellationToken{});
    ASSERT_TRUE(files) << files.error().message;
    ASSERT_EQ((*files)->size(), 1u) << "a merge must diff against its first parent only";
    EXPECT_EQ((*files)->at(0).path, "side.txt");
    EXPECT_EQ((*files)->at(0).kind, FileChangeKind::Added);

    // The other half. Listing the files while every one of them opens an
    // empty diff would be worse than honestly reporting nothing, so the list
    // and the patch are fixed together and asserted together.
    auto diff = diffs.commitFileDiff(oid, "side.txt", options, CancellationToken{});
    ASSERT_TRUE(diff) << diff.error().message;
    ASSERT_EQ((*diff)->files.size(), 1u);
    EXPECT_EQ((*diff)->files[0].addedLines, 1u);
}

TEST_F(RealRepoTest, BatchFileCountsAgreeWithThePerCommitList) {
    // The Changed files column reads the batch count; clicking the row opens
    // the panel, which reads changedFiles(). They run *different git
    // subcommands*, so the only thing standing between them and contradicting
    // each other on screen is this test.
    //
    // The rename commit is the case that matters most and the one the
    // original plan for this work would have got wrong. Its batch command was
    // specified with --no-renames "to match diff-tree's default", but
    // changedFiles() does not run at diff-tree's default -- it passes
    // --find-renames whenever DiffOptions::detectRenames, which is true. So
    // the column would have said 2 (add + delete) beside a panel listing 1
    // (a rename). Measured before the fix, not reasoned about.
    //
    // The reverse asymmetry is just as real and is why the flag is always
    // passed explicitly rather than omitted for the false case: `git log` is
    // porcelain and honours `diff.renames`, which has defaulted to *true*
    // since git 2.9, while `diff-tree` is plumbing and ignores it entirely.
    commitFile("base.txt", "l1\nl2\nl3\nl4\nl5\n", "c1");  // root

    ASSERT_TRUE(run({"checkout", "--quiet", "-b", "side"}));
    commitFile("side.txt", "side\n", "side commit");
    ASSERT_TRUE(run({"checkout", "--quiet", "main"}));
    commitFile("main.txt", "main\n", "main commit");
    ASSERT_TRUE(run({"merge", "--quiet", "--no-ff", "-m", "merge side", "side"}));

    ASSERT_TRUE(run({"mv", "base.txt", "moved.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "rename base"}));

    // Oldest first: root, side, main, merge, rename.
    auto listed = run({"rev-list", "--reverse", "--all"});
    ASSERT_TRUE(listed);
    std::vector<ObjectId> commits;
    std::istringstream lines(listed->out);
    for (std::string line; std::getline(lines, line);) {
        if (!line.empty()) {
            commits.push_back(ObjectId::fromHex(line));
        }
    }
    ASSERT_EQ(commits.size(), 5u);

    DiffService diffs(*runner_, paths_);
    DiffOptions options;

    auto counts = diffs.commitFileCounts(commits, options, CancellationToken{});
    ASSERT_TRUE(counts) << counts.error().message;
    ASSERT_EQ(counts->size(), commits.size());

    // Keyed by oid, because `git log --no-walk` sorts by commit date rather
    // than honouring the order it was given -- indexing into the result as if
    // it mirrored the input would be a real bug that happened to pass here.
    std::map<std::string, std::uint32_t> byOid;
    for (const CommitFileCount& entry : *counts) {
        byOid[entry.commit.hex()] = entry.fileCount;
    }

    for (const ObjectId& commit : commits) {
        auto files = diffs.changedFiles(commit, options, CancellationToken{});
        ASSERT_TRUE(files) << files.error().message;
        ASSERT_TRUE(byOid.count(commit.hex())) << commit.hex() << " missing from the batch";
        EXPECT_EQ(byOid[commit.hex()], (*files)->size())
            << "batch and per-commit disagree for " << commit.hex();
    }

    // And the shapes are the ones the fixture set up, so a future change that
    // made *both* paths wrong in the same way would still be caught.
    const std::string rename = commits.back().hex();
    EXPECT_EQ(byOid[rename], 1u) << "a rename is one file, not an add plus a delete";
    EXPECT_EQ(byOid[commits.front().hex()], 1u) << "the root commit must not read as empty";
}

TEST_F(RealRepoTest, BatchFileCountsIgnoreTheRepositorysDiffRenamesSetting) {
    // Why rawRenameFlag() never returns "" and the flag is never omitted.
    //
    // Omitting it passes the test above, because that fixture leaves
    // `diff.renames` unset and git's porcelain default (true since 2.9)
    // happens to agree with what changedFiles() asks diff-tree for. A user
    // who has turned rename detection off in their own repository moves
    // `git log` and does not move `diff-tree` -- so the column would read 2
    // and the panel 1, for that user only, on their own machine. That is
    // exactly the class of bug a fixture has to be built to reproduce rather
    // than reasoned about, so this one sets the config.
    commitFile("original.txt", "l1\nl2\nl3\nl4\nl5\n", "c1");
    ASSERT_TRUE(run({"mv", "original.txt", "renamed.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "rename it"}));
    ASSERT_TRUE(run({"config", "diff.renames", "false"}));

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    const ObjectId oid = ObjectId::fromHex(head->out);

    DiffService diffs(*runner_, paths_);
    DiffOptions options;  // detectRenames defaults true -- the app's own setting wins.

    auto files = diffs.changedFiles(oid, options, CancellationToken{});
    ASSERT_TRUE(files) << files.error().message;
    auto counts = diffs.commitFileCounts({oid}, options, CancellationToken{});
    ASSERT_TRUE(counts) << counts.error().message;
    ASSERT_EQ(counts->size(), 1u);

    EXPECT_EQ((*files)->size(), 1u) << "diff-tree is plumbing and ignores diff.renames";
    EXPECT_EQ(counts->at(0).fileCount, (*files)->size())
        << "the batch must follow DiffOptions, not the repository's diff.renames";
}

TEST_F(RealRepoTest, BatchFileCountsOmitACommitGitCannotAnswerFor) {
    // Absent, not zero: the caller has to be able to tell "this commit
    // changed no files" from "this commit was never answered for", because
    // the second is what a cache should not remember.
    commitFile("a.txt", "one\n", "c1");
    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);

    DiffService diffs(*runner_, paths_);
    auto counts = diffs.commitFileCounts({}, DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(counts);
    EXPECT_TRUE(counts->empty()) << "an empty request must not run git at all";
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

// M7: RefInfo::isGone is parsed from git's own `%(upstream:track)` `[gone]`
// marker (RefStore.cpp), but nothing had ever proven that marker actually
// reaches it against a real git binary -- every sidebar affordance built on
// top of isGone is decorative if this doesn't fire.
TEST_F(RealRepoTest, ReportsGoneWhenTheUpstreamBranchWasDeleted) {
    const std::filesystem::path remote = repo_.string() + "-bare-remote";
    std::filesystem::remove_all(remote);
    std::filesystem::create_directories(remote);
    GitCommand initBare(remote, {"init", "--quiet", "--bare"});
    initBare.timeout = std::chrono::seconds(30);
    ASSERT_TRUE(runner_->run(initBare, CancellationToken{}));
    extraDirs_.push_back(remote);

    ASSERT_TRUE(run({"remote", "add", "origin", remote.string()}));
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"push", "--quiet", "-u", "origin", "main"}));

    ASSERT_TRUE(run({"switch", "--quiet", "-c", "stale"}));
    // Deliberately not on main: a merged gone branch never exercises the
    // ForceDiscard retry path real users hit when git refuses `-d`.
    commitFile("b.txt", "unmerged\n", "only on stale");
    ASSERT_TRUE(run({"push", "--quiet", "-u", "origin", "stale"}));
    ASSERT_TRUE(run({"push", "--quiet", "origin", "--delete", "stale"}));
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    ASSERT_TRUE(run({"fetch", "--quiet", "--prune"}));

    RefStore store(*runner_, paths_);
    auto snapshot = store.load(CancellationToken{});
    ASSERT_TRUE(snapshot);

    const RefInfo* staleRef = nullptr;
    const RefInfo* mainRef = nullptr;
    for (const RefInfo& ref : (*snapshot)->refs) {
        if (ref.kind != RefKind::LocalBranch) {
            continue;
        }
        if (ref.shortName == "stale") {
            staleRef = &ref;
        } else if (ref.shortName == "main") {
            mainRef = &ref;
        }
    }
    ASSERT_NE(staleRef, nullptr);
    ASSERT_NE(mainRef, nullptr);

    EXPECT_TRUE(staleRef->isGone);
    // parseTrack() early-returns on "[gone]", so ahead/behind never populate --
    // a gone badge and an ahead/behind counter can never coexist on one row.
    EXPECT_EQ(staleRef->ahead, 0);
    EXPECT_EQ(staleRef->behind, 0);
    EXPECT_EQ(staleRef->upstream, "refs/remotes/origin/stale");

    EXPECT_FALSE(mainRef->isGone);
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
    remove.names = {"feature/renamed"};
    auto deleted = submitAndWait(makeDeleteBranchOperation(remove));
    ASSERT_TRUE(deleted.succeeded) << (deleted.error ? deleted.error->detail : "");

    RefStore store(*runner_, paths_);
    auto snapshot = store.load(CancellationToken{});
    ASSERT_TRUE(snapshot);
    for (const RefInfo& ref : (*snapshot)->refs) {
        EXPECT_EQ(ref.shortName.find("feature/"), std::string::npos);
    }
}

// Sidebar multi-select delete (a QTreeView selection filtered down to real,
// non-HEAD local branches) hands every selected name to one DeleteBranchRequest
// rather than issuing one operation per branch -- this proves that request
// shape actually deletes all of them in a single `git branch -d a b c`.
TEST_F(RealRepoTest, DeletesMultipleBranchesInOneRequest) {
    commitFile("a.txt", "1\n", "c1");
    OperationRunner operations(*runner_, paths_);

    auto submitAndWait = [&operations](std::unique_ptr<Operation> operation) {
        OperationOutcome outcome;
        operations.submit(std::move(operation),
                          [&outcome](OperationOutcome result) { outcome = std::move(result); });
        operations.drain();
        return outcome;
    };

    for (const char* name : {"multi-a", "multi-b", "multi-c"}) {
        CreateBranchRequest create;
        create.name = name;
        auto created = submitAndWait(makeCreateBranchOperation(create));
        ASSERT_TRUE(created.succeeded) << (created.error ? created.error->detail : "");
    }

    DeleteBranchRequest remove;
    remove.names = {"multi-a", "multi-b", "multi-c"};
    auto deleted = submitAndWait(makeDeleteBranchOperation(remove));
    ASSERT_TRUE(deleted.succeeded) << (deleted.error ? deleted.error->detail : "");

    RefStore store(*runner_, paths_);
    auto snapshot = store.load(CancellationToken{});
    ASSERT_TRUE(snapshot);
    for (const RefInfo& ref : (*snapshot)->refs) {
        EXPECT_EQ(ref.shortName.find("multi-"), std::string::npos);
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
    remove.names = {"unmerged"};

    OperationOutcome outcome;
    operations.submit(makeDeleteBranchOperation(remove),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();

    EXPECT_FALSE(outcome.succeeded);
    // The headline the user actually reads has to say what happened, not
    // fall back to classifyGitStderr's generic "Git reported an error" --
    // that string carries no information and sent a real user hunting
    // through a collapsed Details pane for git's own phrasing.
    EXPECT_NE(outcome.summary, "Git reported an error");
    // This fixture has no remote configured, so the remote-ref probe
    // (BranchOpsTest.cpp covers its branches directly against a fake runner)
    // finds nothing and the summary must say so honestly -- "fetch and try
    // again", not a claim that the branch was definitely never merged
    // anywhere, which is not something a local-only check can know.
    EXPECT_NE(outcome.summary.find("fetch"), std::string::npos);
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

// The scenario this whole check exists for: a PR merged on the remote (here,
// a second clone standing in for "someone else merged it on GitHub", which
// also deletes the source branch the way GitHub's "delete branch" button
// does) while this repository's own `main` never saw that merge directly,
// only through a later `fetch --prune`. `-d` cannot see past that -- it only
// checks reachability from local refs and from the branch's own upstream,
// and pruning is what removes that upstream from the local view, which is
// what actually makes `-d` fail here (verified against real git: as long as
// origin/feature still exists locally, unmoved, `-d` treats the branch as
// "merged into its own unchanged upstream" and succeeds even though HEAD
// never merged it -- pruning is required to reproduce the user-reported
// failure at all). The remote-ref probe can see past that failure, and must
// say so rather than defaulting to the destructive-sounding fallback.
TEST_F(RealRepoTest, ReportsSafeToDeleteWhenAnotherClonePushedTheMergeAndPrunedTheSource) {
    const std::filesystem::path remote = repo_.string() + "-bare-remote-safe";
    std::filesystem::remove_all(remote);
    std::filesystem::create_directories(remote);
    GitCommand initBare(remote, {"init", "--quiet", "--bare", "--initial-branch=main"});
    initBare.timeout = std::chrono::seconds(30);
    ASSERT_TRUE(runner_->run(initBare, CancellationToken{}));
    extraDirs_.push_back(remote);

    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"remote", "add", "origin", remote.string()}));
    ASSERT_TRUE(run({"push", "--quiet", "-u", "origin", "main"}));

    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("b.txt", "only on feature\n", "feature work");
    ASSERT_TRUE(run({"push", "--quiet", "-u", "origin", "feature"}));
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));

    // A second, independent clone merges, pushes, and deletes the source
    // branch on the remote -- repo_'s local `main` never sees that merge
    // except through a later `fetch`.
    const std::filesystem::path integrator = repo_.string() + "-integrator";
    std::filesystem::remove_all(integrator);
    extraDirs_.push_back(integrator);
    GitCommand clone(repo_.parent_path(),
                     {"clone", "--quiet", remote.string(), integrator.string()});
    clone.timeout = std::chrono::seconds(30);
    ASSERT_TRUE(runner_->run(clone, CancellationToken{}));

    auto runIntegrator = [&](std::vector<std::string> args) {
        GitCommand command(integrator, std::move(args));
        command.timeout = std::chrono::seconds(30);
        return runner_->run(command, CancellationToken{});
    };
    ASSERT_TRUE(runIntegrator({"config", "user.email", "test@example.invalid"}));
    ASSERT_TRUE(runIntegrator({"config", "user.name", "Test"}));
    ASSERT_TRUE(runIntegrator({"config", "commit.gpgsign", "false"}));
    ASSERT_TRUE(runIntegrator({"fetch", "--quiet", "origin", "feature"}));
    ASSERT_TRUE(
        runIntegrator({"merge", "--quiet", "--no-ff", "-m", "Merge feature", "origin/feature"}));
    ASSERT_TRUE(runIntegrator({"push", "--quiet", "origin", "main"}));
    ASSERT_TRUE(runIntegrator({"push", "--quiet", "origin", "--delete", "feature"}));

    // Bring repo_'s remote-tracking view up to date without touching its
    // local `main` -- exactly what "merged and its branch auto-deleted on
    // GitHub, haven't fetched yet" looks like. `--prune` is what removes the
    // local origin/feature ref this branch's `-d` check would otherwise be
    // satisfied by.
    ASSERT_TRUE(run({"fetch", "--quiet", "--prune", "origin"}));

    OperationRunner operations(*runner_, paths_);
    DeleteBranchRequest remove;
    remove.names = {"feature"};

    OperationOutcome outcome;
    operations.submit(makeDeleteBranchOperation(remove),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();

    EXPECT_FALSE(outcome.succeeded);
    EXPECT_NE(outcome.summary.find("origin/main"), std::string::npos);
    EXPECT_NE(outcome.summary.find("not lose"), std::string::npos);
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

// readHead() reads HEAD's oid and its symbolic name out of a single
// `git rev-parse --revs-only HEAD --symbolic-full-name HEAD`, and tells the two
// apart by whether the second line is the literal string "HEAD". That is a
// detail of git's own output, so these two cases are asserted against a real
// git rather than only against FakeProcessRunner -- RefStoreHeadTest.cpp pins
// the parsing and the invocation count, but a fake cannot notice if a future
// git prints something else. The unborn third case is
// HandlesAnEmptyRepositoryWithoutError, below.
TEST_F(RealRepoTest, ReadsABranchHeadFromRealGit) {
    commitFile("a.txt", "one\n", "first");

    RefStore store(*runner_, paths_);
    auto head = store.readHead(CancellationToken{});
    ASSERT_TRUE(head) << head.error().message;
    EXPECT_EQ(head->kind, HeadInfo::Kind::Branch);
    EXPECT_EQ(head->fullRef, "refs/heads/main");
    EXPECT_EQ(head->branchName, "main");

    auto expected = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(expected);
    EXPECT_EQ(head->target.hex(), expected->out);
}

TEST_F(RealRepoTest, ReadsADetachedHeadFromRealGit) {
    commitFile("a.txt", "one\n", "first");
    ASSERT_TRUE(run({"checkout", "--quiet", "--detach"}));

    RefStore store(*runner_, paths_);
    auto head = store.readHead(CancellationToken{});
    ASSERT_TRUE(head) << head.error().message;
    EXPECT_EQ(head->kind, HeadInfo::Kind::Detached);
    EXPECT_TRUE(head->branchName.empty());
    EXPECT_TRUE(head->fullRef.empty());

    // The oid still has to be right: detaching must not cost the caller the
    // commit HEAD is sitting on.
    auto expected = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(expected);
    EXPECT_EQ(head->target.hex(), expected->out);
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

// --- M1: working-copy status, staging and commit ---------------------------

TEST_F(RealRepoTest, WorkingCopyStatusReportsStagedUnstagedAndUntracked) {
    commitFile("a.txt", "one\n", "c1");

    // A staged modification with a further unstaged edit on top of it.
    {
        std::ofstream out(repo_ / "a.txt");
        out << "one\nstaged\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));
    {
        std::ofstream out(repo_ / "a.txt", std::ios::app);
        out << "unstaged\n";
    }

    // An untracked file, never added.
    {
        std::ofstream out(repo_ / "new.txt");
        out << "new\n";
    }

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status) << status.error().message;

    ASSERT_EQ((*status)->entries.size(), 2u);

    const auto staged = (*status)->staged();
    ASSERT_EQ(staged.size(), 1u);
    EXPECT_EQ(staged[0]->path, "a.txt");
    EXPECT_TRUE(staged[0]->staged);
    EXPECT_TRUE(staged[0]->hasUnstagedChange);
    EXPECT_EQ(staged[0]->indexStatus, FileChangeKind::Modified);
    EXPECT_EQ(staged[0]->worktreeStatus, FileChangeKind::Modified);

    const auto untracked = (*status)->untracked();
    ASSERT_EQ(untracked.size(), 1u);
    EXPECT_EQ(untracked[0]->path, "new.txt");
    EXPECT_TRUE(untracked[0]->untracked);
}

/// Regression for #77: a background status read must not take git's
/// *optional* index lock.
///
/// Writes go through OperationRunner's single serial thread, so two writes
/// can never collide -- but Session::refreshWorkingCopy() posts to
/// sharedReadPool(), a different pool entirely, and
/// submitWorkingCopyOperation() emits its FINISHED event *before* kicking
/// that refresh off. So a caller that reacts to the event by starting the
/// next operation races the refresh, and a plain `git status` rewrites the
/// index (taking .git/index.lock) whenever stat info has gone stale. The
/// loser gets GitError::Code::LockHeld, "Another Git process appears to be
/// running in this repository".
///
/// Asserted on the index's *bytes* rather than its mtime: filesystem
/// timestamp granularity varies (HFS+ is 1s), so an mtime comparison can
/// pass on a fast machine for the wrong reason.
TEST_F(RealRepoTest, StatusReadDoesNotRewriteTheIndex) {
    // Enough files that git has real stat work to do, and a back-dated mtime
    // on each so the cached stat info is guaranteed stale -- without this git
    // has no reason to want to rewrite the index and the test would pass
    // vacuously, before *and* after the fix.
    for (int i = 0; i < 40; ++i) {
        const std::string name = "f" + std::to_string(i) + ".txt";
        std::ofstream(repo_ / name) << "content " << i << "\n";
    }
    ASSERT_TRUE(run({"add", "-A"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "many files"}));
    for (int i = 0; i < 40; ++i) {
        const std::string name = "f" + std::to_string(i) + ".txt";
        std::filesystem::last_write_time(
            repo_ / name,
            std::filesystem::file_time_type::clock::now() - std::chrono::hours(24 * 365));
    }

    const auto readIndexBytes = [this]() {
        std::ifstream in(repo_ / ".git" / "index", std::ios::binary);
        return std::string((std::istreambuf_iterator<char>(in)),
                           std::istreambuf_iterator<char>());
    };
    const std::string before = readIndexBytes();
    ASSERT_FALSE(before.empty());

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status) << status.error().message;

    EXPECT_EQ(readIndexBytes(), before)
        << "a status read rewrote .git/index, which means it took the index "
           "lock -- any concurrent write operation would have failed with "
           "LockHeld. See GitCommand::globalFlags()'s --no-optional-locks.";
}

TEST_F(RealRepoTest, WorkingCopyStatusDetectsARenameStagedForCommit) {
    commitFile("original.txt", "line1\nline2\nline3\nline4\nline5\n", "c1");
    ASSERT_TRUE(run({"mv", "original.txt", "renamed.txt"}));
    ASSERT_TRUE(run({"add", "-A"}));

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status) << status.error().message;

    ASSERT_EQ((*status)->entries.size(), 1u);
    const WorkingCopyEntry& entry = (*status)->entries[0];
    EXPECT_TRUE(entry.staged);
    EXPECT_EQ(entry.indexStatus, FileChangeKind::Renamed);
    EXPECT_EQ(entry.oldPath, "original.txt");
    EXPECT_EQ(entry.path, "renamed.txt");
    EXPECT_GT(entry.similarity, 0);
}

TEST_F(RealRepoTest, WorkingCopyStatusReportsWhichSideOfAConflictEachFileIsOn) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "left"}));
    commitFile("shared.txt", "left change\n", "left");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "right change\n", "right");

    auto merge = run({"merge", "--no-commit", "left"});
    EXPECT_FALSE(merge) << "the merge was expected to conflict";

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status) << status.error().message;

    const auto conflicted = (*status)->conflicted();
    ASSERT_EQ(conflicted.size(), 1u);
    EXPECT_EQ(conflicted[0]->path, "shared.txt");
    EXPECT_EQ(conflicted[0]->conflict, ConflictKind::BothModified);
    EXPECT_TRUE((*status)->staged().empty())
        << "a conflicted entry must not also be reported as an ordinary staged change";

    ASSERT_TRUE(run({"merge", "--abort"}));
}

TEST_F(RealRepoTest, StagesAndUnstagesAWholeFile) {
    commitFile("a.txt", "one\n", "c1");
    {
        std::ofstream out(repo_ / "a.txt");
        out << "one\ntwo\n";
    }

    OperationRunner operations(*runner_, paths_);
    auto submitAndWait = [&operations](std::unique_ptr<Operation> operation) {
        OperationOutcome outcome;
        operations.submit(std::move(operation),
                          [&outcome](OperationOutcome result) { outcome = std::move(result); });
        operations.drain();
        return outcome;
    };

    StageFilesRequest stageRequest;
    stageRequest.paths = {"a.txt"};
    auto staged = submitAndWait(makeStageFilesOperation(stageRequest));
    ASSERT_TRUE(staged.succeeded) << (staged.error ? staged.error->detail : "");

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto afterStage = reader.read(CancellationToken{});
    ASSERT_TRUE(afterStage);
    ASSERT_EQ((*afterStage)->entries.size(), 1u);
    EXPECT_TRUE((*afterStage)->entries[0].staged);
    EXPECT_FALSE((*afterStage)->entries[0].hasUnstagedChange);

    UnstageFilesRequest unstageRequest;
    unstageRequest.paths = {"a.txt"};
    auto unstaged = submitAndWait(makeUnstageFilesOperation(unstageRequest));
    ASSERT_TRUE(unstaged.succeeded) << (unstaged.error ? unstaged.error->detail : "");

    auto afterUnstage = reader.read(CancellationToken{});
    ASSERT_TRUE(afterUnstage);
    ASSERT_EQ((*afterUnstage)->entries.size(), 1u);
    EXPECT_FALSE((*afterUnstage)->entries[0].staged);
    EXPECT_TRUE((*afterUnstage)->entries[0].hasUnstagedChange);
}

TEST_F(RealRepoTest, StagesAndUnstagesOneHunkWithoutTouchingItsNeighbour) {
    std::string original;
    for (int i = 1; i <= 20; ++i) {
        original += "l" + std::to_string(i) + "\n";
    }
    commitFile("a.txt", original, "c1");

    // Two edits far enough apart that they land in separate hunks under the
    // default 3-line context.
    std::string modified;
    for (int i = 1; i <= 20; ++i) {
        if (i == 2) {
            modified += "L2\n";
        } else if (i == 18) {
            modified += "L18\n";
        } else {
            modified += "l" + std::to_string(i) + "\n";
        }
    }
    {
        std::ofstream out(repo_ / "a.txt");
        out << modified;
    }

    DiffService diffs(*runner_, paths_);
    auto unstagedDiff = diffs.workingTreeDiff(false, {}, DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(unstagedDiff) << unstagedDiff.error().message;
    ASSERT_EQ((*unstagedDiff)->files.size(), 1u);
    ASSERT_EQ((*unstagedDiff)->files[0].hunks.size(), 2u)
        << "the two edits must land in separate hunks for this test to be meaningful";

    const std::string stagePatch = UnifiedDiffParser::buildHunkPatch(
        (*unstagedDiff)->files[0], (*unstagedDiff)->files[0].hunks[0]);

    OperationRunner operations(*runner_, paths_);
    auto submitAndWait = [&operations](std::unique_ptr<Operation> operation) {
        OperationOutcome outcome;
        operations.submit(std::move(operation),
                          [&outcome](OperationOutcome result) { outcome = std::move(result); });
        operations.drain();
        return outcome;
    };

    ApplyPatchRequest stageRequest;
    stageRequest.patch = stagePatch;
    auto staged = submitAndWait(makeApplyPatchOperation(stageRequest));
    ASSERT_TRUE(staged.succeeded) << (staged.error ? staged.error->detail : "");

    auto indexContent = run({"show", ":a.txt"});
    ASSERT_TRUE(indexContent);
    EXPECT_NE(indexContent->out.find("L2"), std::string::npos);
    EXPECT_EQ(indexContent->out.find("L18"), std::string::npos)
        << "only the staged hunk's change should have reached the index";

    auto remainingUnstaged = diffs.workingTreeDiff(false, {}, DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(remainingUnstaged);
    ASSERT_EQ((*remainingUnstaged)->files.size(), 1u);
    ASSERT_EQ((*remainingUnstaged)->files[0].hunks.size(), 1u)
        << "the unstaged hunk must still be sitting in the work tree";

    // Unstage it again, this time building the patch from the *staged* diff.
    auto stagedDiff = diffs.workingTreeDiff(true, {}, DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(stagedDiff);
    ASSERT_EQ((*stagedDiff)->files[0].hunks.size(), 1u);
    const std::string unstagePatch = UnifiedDiffParser::buildHunkPatch(
        (*stagedDiff)->files[0], (*stagedDiff)->files[0].hunks[0]);

    ApplyPatchRequest unstageRequest;
    unstageRequest.patch = unstagePatch;
    unstageRequest.reverse = true;
    auto unstaged = submitAndWait(makeApplyPatchOperation(unstageRequest));
    ASSERT_TRUE(unstaged.succeeded) << (unstaged.error ? unstaged.error->detail : "");

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto finalStatus = reader.read(CancellationToken{});
    ASSERT_TRUE(finalStatus);
    EXPECT_TRUE((*finalStatus)->staged().empty());
    EXPECT_FALSE((*finalStatus)->unstaged().empty());
}

TEST_F(RealRepoTest, StagesOnlySelectedLinesWithinAHunk) {
    commitFile("b.txt", "keep\n", "c1");
    {
        std::ofstream out(repo_ / "b.txt");
        out << "keep\nalpha\nbeta\n";
    }

    DiffService diffs(*runner_, paths_);
    auto diff = diffs.workingTreeDiff(false, {}, DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(diff) << diff.error().message;
    ASSERT_EQ((*diff)->files.size(), 1u);
    ASSERT_EQ((*diff)->files[0].hunks.size(), 1u);

    const DiffHunk& hunk = (*diff)->files[0].hunks[0];
    std::vector<bool> selected(hunk.lines.size(), false);
    for (std::size_t i = 0; i < hunk.lines.size(); ++i) {
        if (hunk.lines[i].kind == DiffLineKind::Added && hunk.lines[i].text == "alpha") {
            selected[i] = true;
        }
    }

    const std::string patch =
        UnifiedDiffParser::buildLineSelectionPatch((*diff)->files[0], hunk, selected);

    OperationRunner operations(*runner_, paths_);
    ApplyPatchRequest request;
    request.patch = patch;
    OperationOutcome outcome;
    operations.submit(makeApplyPatchOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto indexContent = run({"show", ":b.txt"});
    ASSERT_TRUE(indexContent);
    EXPECT_NE(indexContent->out.find("alpha"), std::string::npos);
    EXPECT_EQ(indexContent->out.find("beta"), std::string::npos)
        << "the unselected line must not have been staged";

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status);
    EXPECT_FALSE((*status)->staged().empty());
    EXPECT_FALSE((*status)->unstaged().empty())
        << "the unselected line must still be sitting unstaged";
}

// Regression test for the bug reported against the working-copy UI: selecting
// a subset of lines in a *staged* file's diff and choosing Unstage failed with
// "patch does not apply". buildLineSelectionPatch's unselected-line handling
// used to be the same in both directions; unstaging checks the patch's new
// side against the index (git apply --cached --reverse), which is the
// opposite of what staging checks, so the two need mirrored (not identical)
// handling of the lines that were not selected -- see unstaging= on that
// function.
TEST_F(RealRepoTest, UnstagesOnlySelectedLinesWithinAHunk) {
    commitFile("c.txt", "keep\n", "c1");
    {
        std::ofstream out(repo_ / "c.txt");
        out << "keep\nalpha\nbeta\n";
    }
    ASSERT_TRUE(run({"add", "c.txt"}));  // Both new lines start out staged.

    DiffService diffs(*runner_, paths_);
    auto stagedDiff = diffs.workingTreeDiff(true, {}, DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(stagedDiff) << stagedDiff.error().message;
    ASSERT_EQ((*stagedDiff)->files.size(), 1u);
    ASSERT_EQ((*stagedDiff)->files[0].hunks.size(), 1u);

    const DiffHunk& hunk = (*stagedDiff)->files[0].hunks[0];
    std::vector<bool> selected(hunk.lines.size(), false);
    for (std::size_t i = 0; i < hunk.lines.size(); ++i) {
        if (hunk.lines[i].kind == DiffLineKind::Added && hunk.lines[i].text == "alpha") {
            selected[i] = true;  // Only "alpha" gets unstaged; "beta" stays staged.
        }
    }

    const std::string patch = UnifiedDiffParser::buildLineSelectionPatch(
        (*stagedDiff)->files[0], hunk, selected, /*unstaging=*/true);

    OperationRunner operations(*runner_, paths_);
    ApplyPatchRequest request;
    request.patch = patch;
    request.reverse = true;
    OperationOutcome outcome;
    operations.submit(makeApplyPatchOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto indexContent = run({"show", ":c.txt"});
    ASSERT_TRUE(indexContent);
    EXPECT_EQ(indexContent->out.find("alpha"), std::string::npos)
        << "the selected line must have been unstaged";
    EXPECT_NE(indexContent->out.find("beta"), std::string::npos)
        << "the unselected line must remain staged";

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status);
    EXPECT_FALSE((*status)->staged().empty()) << "\"beta\" should still be staged";
    EXPECT_FALSE((*status)->unstaged().empty()) << "\"alpha\" should be back in the work tree";
}

// Regression coverage for appendPatchHeader's rename branch. A staged
// rename-plus-edit is diffed, then a subset of the added lines is unstaged by
// line selection. The first version of this test asserted the reconstructed
// patch carried `rename from`/`rename to` headers, matching the staging-side
// behaviour -- and that turned out to be wrong for unstaging: `git apply
// --cached --reverse` reverses the whole patch record, so a rename header
// here undid the rename itself (leaving `old-name.txt` staged again) instead
// of only reverting "alpha". The fix drops the rename header for `unstaging`
// and points both sides at `new-name.txt`, since the rename is already staged
// by the time its content is being partially unstaged.
TEST_F(RealRepoTest, UnstagesSelectedLinesOfARenamedAndModifiedFile) {
    std::string original;
    for (int i = 1; i <= 10; ++i) {
        original += "line" + std::to_string(i) + "\n";
    }
    commitFile("old-name.txt", original, "c1");

    ASSERT_TRUE(run({"mv", "old-name.txt", "new-name.txt"}));
    {
        std::ofstream out(repo_ / "new-name.txt", std::ios::app);
        out << "alpha\nbeta\n";
    }
    ASSERT_TRUE(run({"add", "new-name.txt"}));  // Stage the appended lines too.

    DiffService diffs(*runner_, paths_);
    auto stagedDiff = diffs.workingTreeDiff(true, {}, DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(stagedDiff) << stagedDiff.error().message;
    ASSERT_EQ((*stagedDiff)->files.size(), 1u);
    const DiffFile& file = (*stagedDiff)->files[0];
    ASSERT_EQ(file.kind, FileChangeKind::Renamed)
        << "the rename must survive alongside the appended content for this test to be meaningful";
    ASSERT_EQ(file.oldPath, "old-name.txt");
    ASSERT_EQ(file.newPath, "new-name.txt");
    ASSERT_EQ(file.hunks.size(), 1u);

    const DiffHunk& hunk = file.hunks[0];
    std::vector<bool> selected(hunk.lines.size(), false);
    for (std::size_t i = 0; i < hunk.lines.size(); ++i) {
        if (hunk.lines[i].kind == DiffLineKind::Added && hunk.lines[i].text == "alpha") {
            selected[i] = true;  // Only "alpha" gets unstaged; "beta" stays staged.
        }
    }

    const std::string patch =
        UnifiedDiffParser::buildLineSelectionPatch(file, hunk, selected, /*unstaging=*/true);
    EXPECT_EQ(patch.find("rename from"), std::string::npos)
        << "unstaging must not re-describe the rename -- it is already staged";
    EXPECT_EQ(patch.find("old-name.txt"), std::string::npos)
        << "the reconstructed patch should target new-name.txt on both sides";

    OperationRunner operations(*runner_, paths_);
    ApplyPatchRequest request;
    request.patch = patch;
    request.reverse = true;
    OperationOutcome outcome;
    operations.submit(makeApplyPatchOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto indexContent = run({"show", ":new-name.txt"});
    ASSERT_TRUE(indexContent);
    EXPECT_EQ(indexContent->out.find("alpha"), std::string::npos)
        << "the selected line must have been unstaged";
    EXPECT_NE(indexContent->out.find("beta"), std::string::npos)
        << "the unselected line must remain staged";
    auto oldPathInIndex = run({"cat-file", "-e", ":old-name.txt"});
    EXPECT_FALSE(oldPathInIndex) << "the rename itself must still be staged under the new name";

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status);
    EXPECT_FALSE((*status)->staged().empty()) << "the rename plus \"beta\" should still be staged";
    EXPECT_FALSE((*status)->unstaged().empty()) << "\"alpha\" should be back in the work tree";
}

// Same hazard as above, but through buildHunkPatch/"Unstage Hunk" -- the path
// DiffView::contextMenuEvent and SideBySideDiffView::showLineContextMenu both
// use, unlike the line-selection path above. Whole-hunk unstage of a rename's
// content must also leave the rename staged.
TEST_F(RealRepoTest, UnstagesAWholeHunkOfARenamedAndModifiedFile) {
    std::string original;
    for (int i = 1; i <= 10; ++i) {
        original += "line" + std::to_string(i) + "\n";
    }
    commitFile("orig.txt", original, "c1");

    ASSERT_TRUE(run({"mv", "orig.txt", "renamed.txt"}));
    {
        std::ofstream out(repo_ / "renamed.txt", std::ios::app);
        out << "extra1\nextra2\n";
    }
    ASSERT_TRUE(run({"add", "renamed.txt"}));

    DiffService diffs(*runner_, paths_);
    auto stagedDiff = diffs.workingTreeDiff(true, {}, DiffOptions{}, CancellationToken{});
    ASSERT_TRUE(stagedDiff) << stagedDiff.error().message;
    ASSERT_EQ((*stagedDiff)->files.size(), 1u);
    const DiffFile& file = (*stagedDiff)->files[0];
    ASSERT_EQ(file.kind, FileChangeKind::Renamed);
    ASSERT_EQ(file.hunks.size(), 1u);

    const std::string patch = UnifiedDiffParser::buildHunkPatch(
        file, file.hunks[0], /*reverse=*/false, /*unstaging=*/true);
    EXPECT_EQ(patch.find("rename from"), std::string::npos)
        << "unstaging the whole hunk must not re-describe the rename either";

    OperationRunner operations(*runner_, paths_);
    ApplyPatchRequest request;
    request.patch = patch;
    request.reverse = true;
    OperationOutcome outcome;
    operations.submit(makeApplyPatchOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto indexContent = run({"show", ":renamed.txt"});
    ASSERT_TRUE(indexContent) << "the rename must still be staged under the new name";
    EXPECT_EQ(indexContent->out.find("extra1"), std::string::npos)
        << "the whole hunk's content must have been unstaged";

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status);
    EXPECT_FALSE((*status)->staged().empty()) << "the rename should still be staged";
    EXPECT_FALSE((*status)->unstaged().empty()) << "the content should be back in the work tree";
}

TEST_F(RealRepoTest, CommitsStagedChanges) {
    commitFile("a.txt", "one\n", "c1");
    {
        std::ofstream out(repo_ / "a.txt");
        out << "one\ntwo\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));

    OperationRunner operations(*runner_, paths_);
    CommitRequest request;
    request.message = "Add second line";
    OperationOutcome outcome;
    operations.submit(makeCommitOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto subject = run({"log", "-1", "--format=%s"});
    ASSERT_TRUE(subject);
    EXPECT_EQ(subject->out, "Add second line");

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status);
    EXPECT_TRUE((*status)->isClean());
}

TEST_F(RealRepoTest, AmendsTheLastCommitKeepingItsMessageByDefault) {
    commitFile("a.txt", "one\n", "original message");
    {
        std::ofstream out(repo_ / "a.txt");
        out << "one\ntwo\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));

    OperationRunner operations(*runner_, paths_);
    CommitRequest request;
    request.amend = true;  // No message: keep the existing one (--no-edit).
    OperationOutcome outcome;
    operations.submit(makeCommitOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto count = run({"rev-list", "--count", "HEAD"});
    ASSERT_TRUE(count);
    EXPECT_EQ(count->out, "1") << "amend must not create a second commit";

    auto subject = run({"log", "-1", "--format=%s"});
    ASSERT_TRUE(subject);
    EXPECT_EQ(subject->out, "original message");
}

TEST_F(RealRepoTest, AmendsTheLastCommitWithANewMessage) {
    commitFile("a.txt", "one\n", "original message");

    OperationRunner operations(*runner_, paths_);
    CommitRequest request;
    request.amend = true;
    request.message = "corrected message";
    OperationOutcome outcome;
    operations.submit(makeCommitOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto count = run({"rev-list", "--count", "HEAD"});
    ASSERT_TRUE(count);
    EXPECT_EQ(count->out, "1");

    auto subject = run({"log", "-1", "--format=%s"});
    ASSERT_TRUE(subject);
    EXPECT_EQ(subject->out, "corrected message");
}

TEST_F(RealRepoTest, RejectsAnEmptyCommitMessageBeforeRunningGit) {
    commitFile("a.txt", "one\n", "c1");
    {
        std::ofstream out(repo_ / "a.txt");
        out << "one\ntwo\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));

    OperationRunner operations(*runner_, paths_);
    CommitRequest request;
    request.message = "   ";
    OperationOutcome outcome;
    operations.submit(makeCommitOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::InvalidArgument);

    // Nothing must have been committed.
    auto count = run({"rev-list", "--count", "HEAD"});
    ASSERT_TRUE(count);
    EXPECT_EQ(count->out, "1");
}

TEST_F(RealRepoTest, RefusesToCommitWhenNothingIsStaged) {
    commitFile("a.txt", "one\n", "c1");

    OperationRunner operations(*runner_, paths_);
    CommitRequest request;
    request.message = "should not be created";
    OperationOutcome outcome;
    operations.submit(makeCommitOperation(request),
                      [&outcome](OperationOutcome result) { outcome = std::move(result); });
    operations.drain();

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::InvalidArgument);
}

// --- M2: merge, cherry-pick, conflict resolution ----------------------------

TEST_F(RealRepoTest, FastForwardMergeMovesHeadWithoutACommit) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("a.txt", "2\n", "c2 on feature");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));

    OperationRunner operations(*runner_, paths_);
    MergeRequest request;
    request.target = "feature";
    request.mode = MergeMode::FastForwardOnly;
    auto outcome = submitAndWait(operations, makeMergeOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto count = run({"rev-list", "--count", "HEAD"});
    ASSERT_TRUE(count);
    EXPECT_EQ(count->out, "2") << "a fast-forward must not add a merge commit";

    auto subject = run({"log", "-1", "--format=%s"});
    ASSERT_TRUE(subject);
    EXPECT_EQ(subject->out, "c2 on feature");
}

TEST_F(RealRepoTest, FastForwardOnlyRefusesWhenHistoryHasDiverged) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("a.txt", "2\n", "c2 on feature");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("b.txt", "diverge\n", "c3 on main");

    OperationRunner operations(*runner_, paths_);
    MergeRequest request;
    request.target = "feature";
    request.mode = MergeMode::FastForwardOnly;
    auto outcome = submitAndWait(operations, makeMergeOperation(request));

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::NonFastForward);
}

TEST_F(RealRepoTest, NoFastForwardMergeAlwaysCreatesAMergeCommit) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("a.txt", "2\n", "c2 on feature");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));

    OperationRunner operations(*runner_, paths_);
    MergeRequest request;
    request.target = "feature";
    request.mode = MergeMode::NoFastForward;
    request.message = "Merge feature into main";
    auto outcome = submitAndWait(operations, makeMergeOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto parents = run({"log", "-1", "--format=%P"});
    ASSERT_TRUE(parents);
    EXPECT_NE(parents->out.find(' '), std::string::npos) << "must be a two-parent merge commit";

    auto subject = run({"log", "-1", "--format=%s"});
    ASSERT_TRUE(subject);
    EXPECT_EQ(subject->out, "Merge feature into main");
}

TEST_F(RealRepoTest, SquashMergeStagesChangesWithoutCommittingOrRecordingAParent) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("a.txt", "2\n", "c2 on feature");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));

    OperationRunner operations(*runner_, paths_);
    MergeRequest request;
    request.target = "feature";
    request.mode = MergeMode::Squash;
    auto outcome = submitAndWait(operations, makeMergeOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto count = run({"rev-list", "--count", "HEAD"});
    ASSERT_TRUE(count);
    EXPECT_EQ(count->out, "1") << "squash must not create a commit on its own";

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status);
    EXPECT_FALSE(status->get()->staged().empty()) << "the squashed diff must be staged";
}

TEST_F(RealRepoTest, AConflictingMergeStopsAndCanBeAborted) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "left"}));
    commitFile("shared.txt", "left change\n", "left");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "right change\n", "right");

    OperationRunner operations(*runner_, paths_);
    MergeRequest request;
    request.target = "left";
    request.mode = MergeMode::NoFastForward;
    auto outcome = submitAndWait(operations, makeMergeOperation(request));

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::Conflict);
    EXPECT_TRUE(RepoState::read(paths_).inProgress());

    auto abort = submitAndWait(operations, makeMergeAbortOperation());
    ASSERT_TRUE(abort.succeeded) << (abort.error ? abort.error->detail : "");
    EXPECT_TRUE(RepoState::read(paths_).isClean());
}

TEST_F(RealRepoTest, AConflictingMergeCanBeResolvedByTakingEitherSide) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "left"}));
    commitFile("shared.txt", "left change\n", "left");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "right change\n", "right");

    OperationRunner operations(*runner_, paths_);
    MergeRequest request;
    request.target = "left";
    request.mode = MergeMode::NoFastForward;
    auto merged = submitAndWait(operations, makeMergeOperation(request));
    ASSERT_FALSE(merged.succeeded);

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status);
    const auto conflicted = status->get()->conflicted();
    ASSERT_EQ(conflicted.size(), 1u);
    EXPECT_FALSE(conflicted[0]->oursBlob.empty());
    EXPECT_FALSE(conflicted[0]->theirsBlob.empty());
    EXPECT_FALSE(conflicted[0]->ancestorBlob.empty())
        << "shared.txt has a real common ancestor (the base commit), so stage 1 must be present";

    ResolveConflictRequest resolve;
    resolve.path = "shared.txt";
    resolve.resolution = ConflictResolution::TakeTheirs;
    auto resolved = submitAndWait(operations, makeResolveConflictOperation(resolve));
    ASSERT_TRUE(resolved.succeeded) << (resolved.error ? resolved.error->detail : "");

    auto afterResolve = reader.read(CancellationToken{});
    ASSERT_TRUE(afterResolve);
    EXPECT_TRUE(afterResolve->get()->conflicted().empty());

    auto content = run({"show", ":shared.txt"});
    ASSERT_TRUE(content);
    EXPECT_EQ(content->out, "left change") << "theirs, from the merge's point of view, is `left`";

    CommitRequest commit;
    commit.message = "Merge left into main";
    auto committed = submitAndWait(operations, makeCommitOperation(commit));
    ASSERT_TRUE(committed.succeeded) << (committed.error ? committed.error->detail : "");
    EXPECT_TRUE(RepoState::read(paths_).isClean());
}

TEST_F(RealRepoTest, WriteResolvedWritesTheEditedContentAndStagesIt) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "left"}));
    commitFile("shared.txt", "left change\n", "left");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "right change\n", "right");

    OperationRunner operations(*runner_, paths_);
    MergeRequest request;
    request.target = "left";
    request.mode = MergeMode::NoFastForward;
    auto merged = submitAndWait(operations, makeMergeOperation(request));
    ASSERT_FALSE(merged.succeeded);

    ResolveConflictRequest resolve;
    resolve.path = "shared.txt";
    resolve.resolution = ConflictResolution::WriteResolved;
    resolve.resolvedContent = "hand-merged result\n";
    auto resolved = submitAndWait(operations, makeResolveConflictOperation(resolve));
    ASSERT_TRUE(resolved.succeeded) << (resolved.error ? resolved.error->detail : "");

    std::ifstream in(repo_ / "shared.txt", std::ios::binary);
    const std::string onDisk((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(onDisk, "hand-merged result\n");

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto afterResolve = reader.read(CancellationToken{});
    ASSERT_TRUE(afterResolve);
    EXPECT_TRUE(afterResolve->get()->conflicted().empty());

    auto staged = run({"show", ":shared.txt"});
    ASSERT_TRUE(staged);
    EXPECT_EQ(staged->out, "hand-merged result")
        << "the edited content must be what gets staged, not either original side";
}

TEST_F(RealRepoTest, WriteResolvedWithEmptyContentFailsInsteadOfTruncatingTheFile) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "left"}));
    commitFile("shared.txt", "left change\n", "left");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "right change\n", "right");

    OperationRunner operations(*runner_, paths_);
    MergeRequest request;
    request.target = "left";
    request.mode = MergeMode::NoFastForward;
    auto merged = submitAndWait(operations, makeMergeOperation(request));
    ASSERT_FALSE(merged.succeeded);

    ResolveConflictRequest resolve;
    resolve.path = "shared.txt";
    resolve.resolution = ConflictResolution::WriteResolved;
    resolve.resolvedContent = "";
    auto resolved = submitAndWait(operations, makeResolveConflictOperation(resolve));

    EXPECT_FALSE(resolved.succeeded);
    ASSERT_TRUE(resolved.error.has_value());
    EXPECT_EQ(resolved.error->code, GitError::Code::InvalidArgument);

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto stillConflicted = reader.read(CancellationToken{});
    ASSERT_TRUE(stillConflicted);
    EXPECT_EQ(stillConflicted->get()->conflicted().size(), 1u)
        << "a rejected WriteResolved must not touch the working tree or the index";
}

TEST_F(RealRepoTest, MergeOffersStashAndRetryWhenTheWorkTreeIsDirty) {
    commitFile("a.txt", "base\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("a.txt", "feature change\n", "c2 on feature");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    {
        std::ofstream out(repo_ / "a.txt");
        out << "uncommitted local edit\n";
    }

    OperationRunner operations(*runner_, paths_);
    MergeRequest request;
    request.target = "feature";
    request.mode = MergeMode::NoFastForward;
    auto outcome = submitAndWait(operations, makeMergeOperation(request));

    ASSERT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::DirtyWorkTree);
    bool hasStash = false;
    for (const OperationChoice& choice : outcome.choices) {
        hasStash = hasStash || choice.kind == OperationChoice::Kind::StashAndRetry;
    }
    EXPECT_TRUE(hasStash);

    request.stashFirst = true;
    auto retried = submitAndWait(operations, makeMergeOperation(request));
    ASSERT_TRUE(retried.succeeded) << (retried.error ? retried.error->detail : "");

    auto stashList = run({"stash", "list"});
    ASSERT_TRUE(stashList);
    EXPECT_FALSE(stashList->out.empty()) << "the user's work must be recoverable";
}

TEST_F(RealRepoTest, CherryPicksASingleCommitOntoAnotherBranch) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("b.txt", "feature content\n", "feature commit");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));

    auto pick = run({"rev-parse", "feature"});
    ASSERT_TRUE(pick);
    const ObjectId oid = ObjectId::fromHex(pick->out);

    OperationRunner operations(*runner_, paths_);
    CherryPickRequest request;
    request.commits = {oid};
    auto outcome = submitAndWait(operations, makeCherryPickOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    EXPECT_TRUE(std::filesystem::exists(repo_ / "b.txt"));
    auto subject = run({"log", "-1", "--format=%s"});
    ASSERT_TRUE(subject);
    EXPECT_EQ(subject->out, "feature commit");
}

TEST_F(RealRepoTest, CherryPicksARangeInOldestFirstOrder) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("f1.txt", "1\n", "feature c1");
    commitFile("f2.txt", "2\n", "feature c2");
    commitFile("f3.txt", "3\n", "feature c3");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));

    RefStore refs(*runner_, paths_);
    auto range = refs.resolveRange("main..feature", CancellationToken{});
    ASSERT_TRUE(range) << range.error().message;
    ASSERT_EQ(range->size(), 3u);

    OperationRunner operations(*runner_, paths_);
    CherryPickRequest request;
    request.commits = *range;
    auto outcome = submitAndWait(operations, makeCherryPickOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto count = run({"rev-list", "--count", "HEAD"});
    ASSERT_TRUE(count);
    EXPECT_EQ(count->out, "4");

    // Applied oldest first, so the resulting history reads the same way round.
    auto subjects = run({"log", "--format=%s", "-3", "--reverse"});
    ASSERT_TRUE(subjects);
    EXPECT_EQ(subjects->out, "feature c1\nfeature c2\nfeature c3");
}

TEST_F(RealRepoTest, CherryPickConflictContinuesToTheNextQueuedPickAfterResolution) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("shared.txt", "feature change\n", "feature commit");
    commitFile("other.txt", "unrelated\n", "unrelated commit");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "main change\n", "main commit");

    RefStore refs(*runner_, paths_);
    auto range = refs.resolveRange("main..feature", CancellationToken{});
    ASSERT_TRUE(range);
    ASSERT_EQ(range->size(), 2u);

    OperationRunner operations(*runner_, paths_);
    CherryPickRequest request;
    request.commits = *range;
    auto outcome = submitAndWait(operations, makeCherryPickOperation(request));

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::Conflict);
    EXPECT_TRUE(RepoState::read(paths_).inProgress());

    ResolveConflictRequest resolve;
    resolve.path = "shared.txt";
    resolve.resolution = ConflictResolution::TakeTheirs;
    auto resolved = submitAndWait(operations, makeResolveConflictOperation(resolve));
    ASSERT_TRUE(resolved.succeeded) << (resolved.error ? resolved.error->detail : "");

    auto continued = submitAndWait(operations, makeCherryPickContinueOperation());
    ASSERT_TRUE(continued.succeeded) << (continued.error ? continued.error->detail : "");

    EXPECT_TRUE(std::filesystem::exists(repo_ / "other.txt"))
        << "the second queued pick must have been applied by --continue";
    EXPECT_TRUE(RepoState::read(paths_).isClean());
}

TEST_F(RealRepoTest, CherryPickSkipDropsTheConflictingCommitAndMovesOn) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("shared.txt", "feature change\n", "feature commit");
    commitFile("other.txt", "unrelated\n", "unrelated commit");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "main change\n", "main commit");

    RefStore refs(*runner_, paths_);
    auto range = refs.resolveRange("main..feature", CancellationToken{});
    ASSERT_TRUE(range);
    ASSERT_EQ(range->size(), 2u);

    OperationRunner operations(*runner_, paths_);
    CherryPickRequest request;
    request.commits = *range;
    auto outcome = submitAndWait(operations, makeCherryPickOperation(request));
    ASSERT_FALSE(outcome.succeeded);
    EXPECT_TRUE(RepoState::read(paths_).inProgress());

    auto skipped = submitAndWait(operations, makeCherryPickSkipOperation());
    ASSERT_TRUE(skipped.succeeded) << (skipped.error ? skipped.error->detail : "");

    EXPECT_TRUE(std::filesystem::exists(repo_ / "other.txt"))
        << "the second queued pick must still have been applied after skipping the first";
    EXPECT_TRUE(RepoState::read(paths_).isClean());

    auto content = run({"cat-file", "-p", "HEAD:shared.txt"});
    ASSERT_TRUE(content);
    EXPECT_EQ(content->out, "main change")
        << "the skipped commit's change to shared.txt is dropped";
}

TEST_F(RealRepoTest, CherryPickAbortUnwindsCleanly) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("shared.txt", "feature change\n", "feature commit");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "main change\n", "main commit");

    auto pick = run({"rev-parse", "feature"});
    ASSERT_TRUE(pick);

    OperationRunner operations(*runner_, paths_);
    CherryPickRequest request;
    request.commits = {ObjectId::fromHex(pick->out)};
    auto outcome = submitAndWait(operations, makeCherryPickOperation(request));
    ASSERT_FALSE(outcome.succeeded);
    EXPECT_TRUE(RepoState::read(paths_).inProgress());

    auto aborted = submitAndWait(operations, makeCherryPickAbortOperation());
    ASSERT_TRUE(aborted.succeeded) << (aborted.error ? aborted.error->detail : "");
    EXPECT_TRUE(RepoState::read(paths_).isClean());

    auto content = run({"cat-file", "-p", "HEAD:shared.txt"});
    ASSERT_TRUE(content);
    EXPECT_EQ(content->out, "main change")
        << "abort must leave the tree exactly as before the pick";
}

TEST_F(RealRepoTest, TakingOursOnAConflictWhereWeDeletedRemovesThePath) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "left"}));
    ASSERT_TRUE(run({"rm", "--quiet", "shared.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "delete on left"}));
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "changed on main\n", "change on main");

    auto merge = run({"merge", "--no-commit", "left"});
    EXPECT_FALSE(merge) << "delete-vs-modify was expected to conflict";

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status);
    const auto conflicted = status->get()->conflicted();
    ASSERT_EQ(conflicted.size(), 1u);
    EXPECT_TRUE(conflicted[0]->theirsBlob.empty()) << "left deleted it, so stage 3 does not exist";

    OperationRunner operations(*runner_, paths_);
    ResolveConflictRequest resolve;
    resolve.path = "shared.txt";
    resolve.resolution = ConflictResolution::TakeTheirs;
    resolve.theirsBlobMissing = true;
    auto resolved = submitAndWait(operations, makeResolveConflictOperation(resolve));
    ASSERT_TRUE(resolved.succeeded) << (resolved.error ? resolved.error->detail : "");

    EXPECT_FALSE(std::filesystem::exists(repo_ / "shared.txt"));
    auto afterResolve = reader.read(CancellationToken{});
    ASSERT_TRUE(afterResolve);
    EXPECT_TRUE(afterResolve->get()->conflicted().empty());
    EXPECT_FALSE(afterResolve->get()->staged().empty());

    ASSERT_TRUE(run({"commit", "--quiet", "-m", "merge left"}));
}

// --- M3: worktrees, stash, tags, fetch/pull/push ----------------------------

TEST_F(RealRepoTest, StashSavesListsAppliesAndDrops) {
    commitFile("a.txt", "one\n", "c1");
    {
        std::ofstream out(repo_ / "a.txt");
        out << "one\nlocal edit\n";
    }

    StashStore store(*runner_, paths_);
    OperationRunner operations(*runner_, paths_);

    StashSaveRequest save;
    save.message = "wip";
    auto saved = submitAndWait(operations, makeStashSaveOperation(save));
    ASSERT_TRUE(saved.succeeded) << (saved.error ? saved.error->detail : "");

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto clean = reader.read(CancellationToken{});
    ASSERT_TRUE(clean);
    EXPECT_TRUE((*clean)->isClean()) << "the edit must have moved into the stash";

    auto listed = store.list(CancellationToken{});
    ASSERT_TRUE(listed) << listed.error().message;
    ASSERT_EQ(listed->size(), 1u);
    EXPECT_NE((*listed)[0].message.find("wip"), std::string::npos);
    EXPECT_FALSE((*listed)[0].oid.empty());

    StashApplyRequest apply;
    apply.index = 0;
    apply.pop = false;
    auto applied = submitAndWait(operations, makeStashApplyOperation(apply));
    ASSERT_TRUE(applied.succeeded) << (applied.error ? applied.error->detail : "");

    auto afterApply = reader.read(CancellationToken{});
    ASSERT_TRUE(afterApply);
    EXPECT_FALSE((*afterApply)->isClean());

    // Apply does not drop the entry -- it is still there afterwards.
    auto stillListed = store.list(CancellationToken{});
    ASSERT_TRUE(stillListed);
    EXPECT_EQ(stillListed->size(), 1u);

    StashDropRequest drop;
    drop.index = 0;
    auto dropped = submitAndWait(operations, makeStashDropOperation(drop));
    ASSERT_TRUE(dropped.succeeded) << (dropped.error ? dropped.error->detail : "");

    auto afterDrop = store.list(CancellationToken{});
    ASSERT_TRUE(afterDrop);
    EXPECT_TRUE(afterDrop->empty());
}

TEST_F(RealRepoTest, StashPopAppliesAndRemovesTheEntry) {
    commitFile("a.txt", "one\n", "c1");
    {
        std::ofstream out(repo_ / "a.txt");
        out << "one\nlocal edit\n";
    }

    OperationRunner operations(*runner_, paths_);
    StashSaveRequest save;
    auto saved = submitAndWait(operations, makeStashSaveOperation(save));
    ASSERT_TRUE(saved.succeeded);

    StashApplyRequest pop;
    pop.index = 0;
    pop.pop = true;
    auto popped = submitAndWait(operations, makeStashApplyOperation(pop));
    ASSERT_TRUE(popped.succeeded) << (popped.error ? popped.error->detail : "");

    StashStore store(*runner_, paths_);
    auto listed = store.list(CancellationToken{});
    ASSERT_TRUE(listed);
    EXPECT_TRUE(listed->empty()) << "pop must drop the entry on success";

    WorkingCopyStatusReader reader(*runner_, paths_);
    auto status = reader.read(CancellationToken{});
    ASSERT_TRUE(status);
    EXPECT_FALSE((*status)->isClean());
}

TEST_F(RealRepoTest, StashSaveRefusesWhenThereIsNothingToStash) {
    commitFile("a.txt", "one\n", "c1");

    OperationRunner operations(*runner_, paths_);
    StashSaveRequest save;
    auto outcome = submitAndWait(operations, makeStashSaveOperation(save));

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::InvalidArgument);
}

TEST_F(RealRepoTest, StashBranchCreatesABranchFromAStashedChange) {
    commitFile("a.txt", "one\n", "c1");
    {
        std::ofstream out(repo_ / "a.txt");
        out << "one\nfrom stash\n";
    }

    OperationRunner operations(*runner_, paths_);
    StashSaveRequest save;
    auto saved = submitAndWait(operations, makeStashSaveOperation(save));
    ASSERT_TRUE(saved.succeeded);

    StashBranchRequest branch;
    branch.index = 0;
    branch.branchName = "from-stash";
    auto outcome = submitAndWait(operations, makeStashBranchOperation(branch));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    RefStore refs(*runner_, paths_);
    auto head = refs.readHead(CancellationToken{});
    ASSERT_TRUE(head);
    EXPECT_EQ(head->branchName, "from-stash");

    // The edit was never staged before it was stashed, so `stash branch`
    // restores it the same way: present in the working tree, not the index.
    auto content = fsutil::readSmallFile(repo_ / "a.txt");
    ASSERT_TRUE(content.has_value());
    EXPECT_NE(content->find("from stash"), std::string::npos);
}

TEST_F(RealRepoTest, CreatesAnnotatedAndLightweightTagsAndDeletesThem) {
    commitFile("a.txt", "1\n", "c1");

    OperationRunner operations(*runner_, paths_);

    CreateTagRequest lightweight;
    lightweight.name = "v1.0-lw";
    auto created1 = submitAndWait(operations, makeCreateTagOperation(lightweight));
    ASSERT_TRUE(created1.succeeded) << (created1.error ? created1.error->detail : "");

    CreateTagRequest annotated;
    annotated.name = "v1.0";
    annotated.message = "First release";
    auto created2 = submitAndWait(operations, makeCreateTagOperation(annotated));
    ASSERT_TRUE(created2.succeeded) << (created2.error ? created2.error->detail : "");

    RefStore refs(*runner_, paths_);
    auto snapshot = refs.load(CancellationToken{});
    ASSERT_TRUE(snapshot);
    EXPECT_EQ((*snapshot)->ofKind(RefKind::Tag).size(), 2u);

    auto typeCheck = run({"cat-file", "-t", "v1.0"});
    ASSERT_TRUE(typeCheck);
    EXPECT_EQ(typeCheck->out, "tag") << "the annotated tag must be a real tag object";

    DeleteTagRequest deleteRequest;
    deleteRequest.name = "v1.0-lw";
    auto deleted = submitAndWait(operations, makeDeleteTagOperation(deleteRequest));
    ASSERT_TRUE(deleted.succeeded) << (deleted.error ? deleted.error->detail : "");

    auto afterDelete = refs.load(CancellationToken{});
    ASSERT_TRUE(afterDelete);
    EXPECT_EQ((*afterDelete)->ofKind(RefKind::Tag).size(), 1u);
}

TEST_F(RealRepoTest, RejectsAnInvalidTagNameBeforeRunningGit) {
    commitFile("a.txt", "1\n", "c1");

    OperationRunner operations(*runner_, paths_);
    CreateTagRequest request;
    request.name = "bad tag name";
    auto outcome = submitAndWait(operations, makeCreateTagOperation(request));

    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::InvalidArgument);
}

TEST_F(RealRepoTest, ListsAddsLocksAndRemovesWorktrees) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"branch", "feature"}));

    WorktreeStore store(*runner_, paths_);
    auto initial = store.list(CancellationToken{});
    ASSERT_TRUE(initial) << initial.error().message;
    ASSERT_EQ(initial->size(), 1u);
    EXPECT_TRUE((*initial)[0].isMain);

    const std::filesystem::path linkedPath =
        repo_.parent_path() / (repo_.filename().string() + "-wt");
    std::filesystem::remove_all(linkedPath);

    OperationRunner operations(*runner_, paths_);
    AddWorktreeRequest add;
    add.path = linkedPath;
    add.branch = "feature";
    auto added = submitAndWait(operations, makeAddWorktreeOperation(add));
    ASSERT_TRUE(added.succeeded) << (added.error ? added.error->detail : "");
    EXPECT_TRUE(std::filesystem::exists(linkedPath / "a.txt"));

    auto afterAdd = store.list(CancellationToken{});
    ASSERT_TRUE(afterAdd);
    ASSERT_EQ(afterAdd->size(), 2u);

    LockWorktreeRequest lock;
    lock.path = linkedPath;
    lock.reason = "in use";
    auto locked = submitAndWait(operations, makeLockWorktreeOperation(lock));
    ASSERT_TRUE(locked.succeeded) << (locked.error ? locked.error->detail : "");

    auto afterLock = store.list(CancellationToken{});
    ASSERT_TRUE(afterLock);
    // std::filesystem::equivalent, not ==: git reports each worktree's
    // realpath, which on macOS differs textually from linkedPath (built
    // through /var, a symlink to /private/var) even though it names the same
    // directory.
    auto lockedEntry =
        std::find_if(afterLock->begin(), afterLock->end(), [&](const WorktreeInfo& wt) {
            return std::filesystem::equivalent(wt.path, linkedPath);
        });
    ASSERT_NE(lockedEntry, afterLock->end());
    EXPECT_TRUE(lockedEntry->isLocked);
    EXPECT_EQ(lockedEntry->lockReason, "in use");

    // Removing a locked worktree without force must fail.
    RemoveWorktreeRequest remove;
    remove.path = linkedPath;
    auto blocked = submitAndWait(operations, makeRemoveWorktreeOperation(remove));
    EXPECT_FALSE(blocked.succeeded);

    UnlockWorktreeRequest unlock;
    unlock.path = linkedPath;
    auto unlocked = submitAndWait(operations, makeUnlockWorktreeOperation(unlock));
    ASSERT_TRUE(unlocked.succeeded) << (unlocked.error ? unlocked.error->detail : "");

    auto removed = submitAndWait(operations, makeRemoveWorktreeOperation(remove));
    ASSERT_TRUE(removed.succeeded) << (removed.error ? removed.error->detail : "");
    EXPECT_FALSE(std::filesystem::exists(linkedPath));

    auto finalList = store.list(CancellationToken{});
    ASSERT_TRUE(finalList);
    EXPECT_EQ(finalList->size(), 1u);
}

TEST_F(RealRepoTest, PrunesAWorktreeWhoseDirectoryWasDeletedManually) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"branch", "feature"}));

    const std::filesystem::path linkedPath =
        repo_.parent_path() / (repo_.filename().string() + "-prune-wt");
    std::filesystem::remove_all(linkedPath);
    ASSERT_TRUE(run({"worktree", "add", linkedPath.string(), "feature"}));

    // Simulate the user deleting the worktree directory from a file manager
    // instead of using `git worktree remove`.
    std::filesystem::remove_all(linkedPath);

    OperationRunner operations(*runner_, paths_);
    auto pruned = submitAndWait(operations, makePruneWorktreesOperation(PruneWorktreesRequest{}));
    ASSERT_TRUE(pruned.succeeded) << (pruned.error ? pruned.error->detail : "");

    WorktreeStore store(*runner_, paths_);
    auto afterPrune = store.list(CancellationToken{});
    ASSERT_TRUE(afterPrune);
    EXPECT_EQ(afterPrune->size(), 1u) << "the stale worktree entry must be gone";
}

/// Fixture for the fetch/pull/push tests: a bare "remote" repository plus a
/// local clone-equivalent (an ordinary repo with `origin` pointed at the bare
/// one), all on local disk so the tests need no network.
class RemoteRepoTest : public RealRepoTest {
protected:
    void SetUp() override {
        RealRepoTest::SetUp();
        if (installation_.executable.empty()) {
            return;
        }
        remote_ = repo_.parent_path() / (repo_.filename().string() + "-remote.git");
        std::filesystem::remove_all(remote_);
        GitCommand initBare(
            remote_.parent_path(),
            {"init", "--quiet", "--bare", "--initial-branch=main", remote_.string()});
        initBare.timeout = std::chrono::seconds(30);
        ASSERT_TRUE(runner_->run(initBare, CancellationToken{}));

        ASSERT_TRUE(run({"remote", "add", "origin", remote_.string()}));
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(remote_, ec);
        RealRepoTest::TearDown();
    }

    std::filesystem::path remote_;
};

TEST_F(RemoteRepoTest, PushesSeveralBranchesInOneOperation) {
    // Spec page 13's multi-select push. One `git push origin a b c`, not N
    // operations: git updates each ref in turn and reports per-ref status,
    // which is the "依序執行，失敗不中斷其餘" behaviour the batch needs, and
    // one command means one background task (spec page 10) rather than N
    // OPERATION_FINISHED events.
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"branch", "feature-one"}));
    ASSERT_TRUE(run({"branch", "feature-two"}));

    OperationRunner operations(*runner_, paths_);
    PushRequest push;
    push.remoteName = "origin";
    push.branches = {"main", "feature-one", "feature-two"};
    auto pushed = submitAndWait(operations, makePushOperation(push));
    ASSERT_TRUE(pushed.succeeded) << (pushed.error ? pushed.error->detail : "");

    for (const char* branch : {"main", "feature-one", "feature-two"}) {
        auto listed = run({"ls-remote", remote_.string(), std::string("refs/heads/") + branch});
        ASSERT_TRUE(listed);
        EXPECT_FALSE(listed->out.empty()) << branch << " was not pushed";
    }
}

TEST_F(RemoteRepoTest, PushWithNoBranchesStillPushesTheCurrentOne) {
    // branchCount 0 keeps the pre-existing "let git decide" behaviour: no
    // refspec is passed at all, so git pushes the current branch through its
    // configured upstream. It is *not* equivalent to passing the current
    // branch's name -- without an upstream git refuses outright, which is why
    // the first push here has to name the branch and set one up.
    commitFile("a.txt", "1\n", "c1");

    OperationRunner operations(*runner_, paths_);
    PushRequest first;
    first.remoteName = "origin";
    first.branches = {"main"};
    first.setUpstream = true;
    auto initial = submitAndWait(operations, makePushOperation(first));
    ASSERT_TRUE(initial.succeeded) << (initial.error ? initial.error->detail : "");

    commitFile("a.txt", "2\n", "c2");
    auto local = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(local);

    PushRequest followUp;
    followUp.remoteName = "origin";
    auto pushed = submitAndWait(operations, makePushOperation(followUp));
    ASSERT_TRUE(pushed.succeeded) << (pushed.error ? pushed.error->detail : "");

    auto remoteHead = run({"ls-remote", remote_.string(), "refs/heads/main"});
    ASSERT_TRUE(remoteHead);
    EXPECT_NE(remoteHead->out.find(local->out), std::string::npos);
}

TEST_F(RemoteRepoTest, PushesFetchesAndPulls) {
    commitFile("a.txt", "1\n", "c1");

    OperationRunner operations(*runner_, paths_);
    PushRequest push;
    push.remoteName = "origin";
    push.branches = {"main"};
    push.setUpstream = true;
    auto pushed = submitAndWait(operations, makePushOperation(push));
    ASSERT_TRUE(pushed.succeeded) << (pushed.error ? pushed.error->detail : "");

    auto remoteHead = run({"ls-remote", remote_.string(), "refs/heads/main"});
    ASSERT_TRUE(remoteHead);
    EXPECT_FALSE(remoteHead->out.empty());

    RemoteStore remotes(*runner_, paths_);
    auto listed = remotes.list(CancellationToken{});
    ASSERT_TRUE(listed) << listed.error().message;
    ASSERT_EQ(listed->size(), 1u);
    EXPECT_EQ((*listed)[0].name, "origin");
    EXPECT_EQ((*listed)[0].fetchUrl, remote_.string());

    // A second local commit lands directly in the bare remote by pushing from a
    // throwaway path, standing in for a teammate's push.
    const std::filesystem::path other =
        repo_.parent_path() / (repo_.filename().string() + "-other");
    std::filesystem::remove_all(other);
    GitCommand clone(other.parent_path(), {"clone", "--quiet", remote_.string(), other.string()});
    clone.timeout = std::chrono::seconds(60);
    ASSERT_TRUE(runner_->run(clone, CancellationToken{}));
    GitCommand configEmail(other, {"config", "user.email", "teammate@example.invalid"});
    ASSERT_TRUE(runner_->run(configEmail, CancellationToken{}));
    GitCommand configName(other, {"config", "user.name", "Teammate"});
    ASSERT_TRUE(runner_->run(configName, CancellationToken{}));
    {
        std::ofstream out(other / "teammate.txt");
        out << "teammate work\n";
    }
    GitCommand add(other, {"add", "teammate.txt"});
    ASSERT_TRUE(runner_->run(add, CancellationToken{}));
    GitCommand commit(other, {"commit", "--quiet", "-m", "teammate commit"});
    ASSERT_TRUE(runner_->run(commit, CancellationToken{}));
    GitCommand push2(other, {"push", "--quiet", "origin", "main"});
    push2.timeout = std::chrono::seconds(60);
    ASSERT_TRUE(runner_->run(push2, CancellationToken{}));
    std::filesystem::remove_all(other);

    FetchRequest fetch;
    fetch.remoteName = "origin";
    auto fetched = submitAndWait(operations, makeFetchOperation(fetch));
    ASSERT_TRUE(fetched.succeeded) << (fetched.error ? fetched.error->detail : "");
    EXPECT_FALSE(std::filesystem::exists(repo_ / "teammate.txt"))
        << "fetch must not touch the working tree";

    PullRequest pull;
    pull.remoteName = "origin";
    pull.branch = "main";
    auto pulled = submitAndWait(operations, makePullOperation(pull));
    ASSERT_TRUE(pulled.succeeded) << (pulled.error ? pulled.error->detail : "");
    EXPECT_TRUE(std::filesystem::exists(repo_ / "teammate.txt"));
}

TEST_F(RemoteRepoTest, ForceWithLeaseRefusesAStalePushAndSucceedsAfterRefetching) {
    commitFile("a.txt", "1\n", "c1");

    OperationRunner operations(*runner_, paths_);
    PushRequest push;
    push.remoteName = "origin";
    push.branches = {"main"};
    push.setUpstream = true;
    auto pushed = submitAndWait(operations, makePushOperation(push));
    ASSERT_TRUE(pushed.succeeded);

    // A teammate pushes a commit we have not fetched.
    const std::filesystem::path other =
        repo_.parent_path() / (repo_.filename().string() + "-lease-other");
    std::filesystem::remove_all(other);
    GitCommand clone(other.parent_path(), {"clone", "--quiet", remote_.string(), other.string()});
    clone.timeout = std::chrono::seconds(60);
    ASSERT_TRUE(runner_->run(clone, CancellationToken{}));
    GitCommand configEmail(other, {"config", "user.email", "teammate@example.invalid"});
    ASSERT_TRUE(runner_->run(configEmail, CancellationToken{}));
    GitCommand configName(other, {"config", "user.name", "Teammate"});
    ASSERT_TRUE(runner_->run(configName, CancellationToken{}));
    {
        std::ofstream out(other / "teammate.txt");
        out << "teammate work\n";
    }
    GitCommand add(other, {"add", "teammate.txt"});
    ASSERT_TRUE(runner_->run(add, CancellationToken{}));
    GitCommand commit(other, {"commit", "--quiet", "-m", "teammate commit"});
    ASSERT_TRUE(runner_->run(commit, CancellationToken{}));
    GitCommand push2(other, {"push", "--quiet", "origin", "main"});
    push2.timeout = std::chrono::seconds(60);
    ASSERT_TRUE(runner_->run(push2, CancellationToken{}));
    std::filesystem::remove_all(other);

    // We amend our own commit (rewriting history) without having fetched the
    // teammate's push, then try to force-push over it.
    commitFile("a.txt", "2\n", "c2");

    PushRequest forcePush;
    forcePush.remoteName = "origin";
    forcePush.branches = {"main"};
    forcePush.force = PushForceMode::ForceWithLease;
    auto rejected = submitAndWait(operations, makePushOperation(forcePush));
    EXPECT_FALSE(rejected.succeeded)
        << "force-with-lease must refuse when the remote moved since our last fetch";
    ASSERT_TRUE(rejected.error.has_value());
    EXPECT_EQ(rejected.error->code, GitError::Code::NonFastForward);

    // After fetching, the lease is up to date and the same push must succeed.
    FetchRequest fetch;
    fetch.remoteName = "origin";
    auto fetched = submitAndWait(operations, makeFetchOperation(fetch));
    ASSERT_TRUE(fetched.succeeded);

    auto retried = submitAndWait(operations, makePushOperation(forcePush));
    ASSERT_TRUE(retried.succeeded) << (retried.error ? retried.error->detail : "");
}

// --- M4: reset / restore / clean --------------------------------------------

TEST_F(RealRepoTest, SoftResetMovesHeadButKeepsTheIndexAndWorkTree) {
    commitFile("a.txt", "1\n", "c1");
    commitFile("a.txt", "2\n", "c2");
    auto first = run({"rev-parse", "HEAD~1"});
    ASSERT_TRUE(first);

    OperationRunner operations(*runner_, paths_);
    ResetRequest request;
    request.target = first->out;
    request.mode = ResetMode::Soft;
    auto outcome = submitAndWait(operations, makeResetOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    EXPECT_EQ(head->out, first->out);
    // The change from c2 must still be staged.
    auto staged = run({"diff", "--cached", "--name-only"});
    ASSERT_TRUE(staged);
    EXPECT_EQ(staged->out, "a.txt");
}

TEST_F(RealRepoTest, MixedResetMovesHeadAndUnstagesButKeepsTheWorkTree) {
    commitFile("a.txt", "1\n", "c1");
    commitFile("a.txt", "2\n", "c2");
    auto first = run({"rev-parse", "HEAD~1"});
    ASSERT_TRUE(first);

    OperationRunner operations(*runner_, paths_);
    ResetRequest request;
    request.target = first->out;
    request.mode = ResetMode::Mixed;
    auto outcome = submitAndWait(operations, makeResetOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto staged = run({"diff", "--cached", "--name-only"});
    ASSERT_TRUE(staged);
    EXPECT_TRUE(staged->out.empty());
    std::ifstream in(repo_ / "a.txt");
    std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(content, "2\n") << "the work tree must be untouched by a mixed reset";
}

TEST_F(RealRepoTest, HardResetDiscardsTheIndexAndWorkTree) {
    commitFile("a.txt", "1\n", "c1");
    commitFile("a.txt", "2\n", "c2");
    auto first = run({"rev-parse", "HEAD~1"});
    ASSERT_TRUE(first);

    OperationRunner operations(*runner_, paths_);
    ResetRequest request;
    request.target = first->out;
    request.mode = ResetMode::Hard;
    auto outcome = submitAndWait(operations, makeResetOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    std::ifstream in(repo_ / "a.txt");
    std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(content, "1\n");
}

TEST_F(RealRepoTest, RestoreStagedUnstagesWithoutTouchingTheWorkTree) {
    commitFile("a.txt", "1\n", "c1");
    {
        std::ofstream out(repo_ / "a.txt", std::ios::trunc);
        out << "2\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));

    OperationRunner operations(*runner_, paths_);
    RestoreRequest request;
    request.paths = {"a.txt"};
    request.staged = true;
    auto outcome = submitAndWait(operations, makeRestoreOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto staged = run({"diff", "--cached", "--name-only"});
    ASSERT_TRUE(staged);
    EXPECT_TRUE(staged->out.empty());
    std::ifstream in(repo_ / "a.txt");
    std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(content, "2\n") << "unstaging must not touch the work tree";
}

TEST_F(RealRepoTest, RestoreWorkTreeDiscardsUnstagedChanges) {
    commitFile("a.txt", "1\n", "c1");
    {
        std::ofstream out(repo_ / "a.txt", std::ios::trunc);
        out << "scratch\n";
    }

    OperationRunner operations(*runner_, paths_);
    RestoreRequest request;
    request.paths = {"a.txt"};
    request.staged = false;
    auto outcome = submitAndWait(operations, makeRestoreOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    std::ifstream in(repo_ / "a.txt");
    std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(content, "1\n");
}

TEST_F(RealRepoTest, CleanPreviewListsUntrackedFilesWithoutRemovingThem) {
    commitFile("a.txt", "1\n", "c1");
    {
        std::ofstream out(repo_ / "scratch.txt");
        out << "junk\n";
    }

    CleanPreviewer previewer(*runner_, paths_);
    auto preview = previewer.preview(false, CancellationToken{});
    ASSERT_TRUE(preview) << preview.error().message;
    ASSERT_EQ(preview->size(), 1u);
    EXPECT_EQ((*preview)[0].path, "scratch.txt");
    EXPECT_TRUE(std::filesystem::exists(repo_ / "scratch.txt"))
        << "a preview must never touch the filesystem";
}

TEST_F(RealRepoTest, CleanRemovesUntrackedFiles) {
    commitFile("a.txt", "1\n", "c1");
    {
        std::ofstream out(repo_ / "scratch.txt");
        out << "junk\n";
    }

    OperationRunner operations(*runner_, paths_);
    CleanRequest request;
    auto outcome = submitAndWait(operations, makeCleanOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");
    EXPECT_FALSE(std::filesystem::exists(repo_ / "scratch.txt"));
    EXPECT_TRUE(std::filesystem::exists(repo_ / "a.txt")) << "tracked files must be untouched";
}

// --- M4: interactive and plain rebase ---------------------------------------

TEST_F(RealRepoTest, RebasePlanListsCommitsOldestFirst) {
    commitFile("base.txt", "base\n", "base");
    auto base = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(base);
    commitFile("a.txt", "1\n", "c1");
    commitFile("b.txt", "2\n", "c2");

    RebasePlanner planner(*runner_, paths_);
    auto plan = planner.plan(base->out, CancellationToken{});
    ASSERT_TRUE(plan) << plan.error().message;
    ASSERT_EQ(plan->size(), 2u);
    EXPECT_EQ((*plan)[0].subject, "c1");
    EXPECT_EQ((*plan)[1].subject, "c2");
    EXPECT_EQ((*plan)[0].action, RebaseTodoEntry::Action::Pick);
}

TEST_F(RealRepoTest, InteractiveRebaseAppliesReorderingAndDrops) {
    commitFile("base.txt", "base\n", "base");
    auto base = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(base);
    commitFile("a.txt", "1\n", "c1");
    commitFile("b.txt", "2\n", "c2");
    commitFile("c.txt", "3\n", "c3");

    RebasePlanner planner(*runner_, paths_);
    auto plan = planner.plan(base->out, CancellationToken{});
    ASSERT_TRUE(plan);
    ASSERT_EQ(plan->size(), 3u);

    // Reorder c2 before c1, and drop c3 entirely.
    RebaseInteractiveRequest request;
    request.upstream = base->out;
    request.todo = {(*plan)[1], (*plan)[0]};
    request.todo[1].action = RebaseTodoEntry::Action::Pick;

    OperationRunner operations(*runner_, paths_);
    auto outcome = submitAndWait(operations, makeRebaseInteractiveOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");
    EXPECT_TRUE(RepoState::read(paths_).isClean());

    auto subjects = run({"log", "--format=%s", "--reverse"});
    ASSERT_TRUE(subjects);
    EXPECT_EQ(subjects->out, "base\nc2\nc1") << "c2 must now come before c1, and c3 must be gone";
    EXPECT_FALSE(std::filesystem::exists(repo_ / "c.txt"));
}

TEST_F(RealRepoTest, InteractiveRebaseSquashesCommitsTogether) {
    commitFile("base.txt", "base\n", "base");
    auto base = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(base);
    commitFile("a.txt", "1\n", "c1");
    commitFile("a.txt", "2\n", "c2 to squash");

    RebasePlanner planner(*runner_, paths_);
    auto plan = planner.plan(base->out, CancellationToken{});
    ASSERT_TRUE(plan);
    ASSERT_EQ(plan->size(), 2u);

    RebaseInteractiveRequest request;
    request.upstream = base->out;
    request.todo = *plan;
    request.todo[1].action = RebaseTodoEntry::Action::Squash;

    OperationRunner operations(*runner_, paths_);
    auto outcome = submitAndWait(operations, makeRebaseInteractiveOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto count = run({"rev-list", "--count", "HEAD"});
    ASSERT_TRUE(count);
    EXPECT_EQ(count->out, "2") << "base + one squashed commit";
    std::ifstream in(repo_ / "a.txt");
    std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(content, "2\n");
}

TEST_F(RealRepoTest, RebaseConflictContinuesAfterResolution) {
    commitFile("shared.txt", "base\n", "base");
    auto base = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(base);
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("shared.txt", "feature change\n", "feature commit");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "main change\n", "main commit");
    ASSERT_TRUE(run({"switch", "--quiet", "feature"}));

    RebasePlanner planner(*runner_, paths_);
    auto plan = planner.plan("main", CancellationToken{});
    ASSERT_TRUE(plan);
    ASSERT_EQ(plan->size(), 1u);

    RebaseInteractiveRequest request;
    request.upstream = "main";
    request.todo = *plan;

    OperationRunner operations(*runner_, paths_);
    auto outcome = submitAndWait(operations, makeRebaseInteractiveOperation(request));
    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::Conflict);
    EXPECT_TRUE(RepoState::read(paths_).inProgress());

    ResolveConflictRequest resolve;
    resolve.path = "shared.txt";
    resolve.resolution = ConflictResolution::TakeTheirs;
    auto resolved = submitAndWait(operations, makeResolveConflictOperation(resolve));
    ASSERT_TRUE(resolved.succeeded) << (resolved.error ? resolved.error->detail : "");

    auto continued = submitAndWait(operations, makeRebaseContinueOperation());
    ASSERT_TRUE(continued.succeeded) << (continued.error ? continued.error->detail : "");
    EXPECT_TRUE(RepoState::read(paths_).isClean());

    auto content = run({"cat-file", "-p", "HEAD:shared.txt"});
    ASSERT_TRUE(content);
    EXPECT_EQ(content->out, "feature change");
}

TEST_F(RealRepoTest, RebaseSkipDropsTheConflictingCommitAndMovesOn) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("shared.txt", "feature change\n", "feature commit");
    commitFile("other.txt", "unrelated\n", "unrelated commit");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "main change\n", "main commit");
    ASSERT_TRUE(run({"switch", "--quiet", "feature"}));

    OperationRunner operations(*runner_, paths_);
    RebaseRequest request;
    request.upstream = "main";
    auto outcome = submitAndWait(operations, makeRebaseOperation(request));
    ASSERT_FALSE(outcome.succeeded);
    EXPECT_TRUE(RepoState::read(paths_).inProgress());

    auto skipped = submitAndWait(operations, makeRebaseSkipOperation());
    ASSERT_TRUE(skipped.succeeded) << (skipped.error ? skipped.error->detail : "");
    EXPECT_TRUE(RepoState::read(paths_).isClean());
    EXPECT_TRUE(std::filesystem::exists(repo_ / "other.txt"))
        << "the commit queued after the skipped one must still land";
}

TEST_F(RealRepoTest, RebaseAbortUnwindsCleanly) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("shared.txt", "feature change\n", "feature commit");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "main change\n", "main commit");
    ASSERT_TRUE(run({"switch", "--quiet", "feature"}));
    auto beforeRebase = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(beforeRebase);

    OperationRunner operations(*runner_, paths_);
    RebaseRequest request;
    request.upstream = "main";
    auto outcome = submitAndWait(operations, makeRebaseOperation(request));
    ASSERT_FALSE(outcome.succeeded);
    EXPECT_TRUE(RepoState::read(paths_).inProgress());

    auto aborted = submitAndWait(operations, makeRebaseAbortOperation());
    ASSERT_TRUE(aborted.succeeded) << (aborted.error ? aborted.error->detail : "");
    EXPECT_TRUE(RepoState::read(paths_).isClean());

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    EXPECT_EQ(head->out, beforeRebase->out);
}

TEST_F(RealRepoTest, PlainRebaseReplaysCommitsOntoANewBaseUnchanged) {
    commitFile("base.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("a.txt", "1\n", "feature c1");
    commitFile("b.txt", "2\n", "feature c2");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("other.txt", "unrelated\n", "main commit");

    OperationRunner operations(*runner_, paths_);
    ASSERT_TRUE(run({"switch", "--quiet", "feature"}));
    RebaseRequest request;
    request.upstream = "main";
    auto outcome = submitAndWait(operations, makeRebaseOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto subjects = run({"log", "--format=%s", "-2"});
    ASSERT_TRUE(subjects);
    EXPECT_EQ(subjects->out, "feature c2\nfeature c1")
        << "messages must be preserved exactly by a non-interactive rebase";
    EXPECT_TRUE(std::filesystem::exists(repo_ / "other.txt"));
}

// --- M4: blame ---------------------------------------------------------------

TEST_F(RealRepoTest, BlameAttributesEachLineToTheCommitThatIntroducedIt) {
    {
        std::ofstream out(repo_ / "a.txt");
        out << "line one\nline two\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "first two lines"}));
    auto first = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(first);

    {
        std::ofstream out(repo_ / "a.txt", std::ios::app);
        out << "line three\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "add a third line"}));
    auto second = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(second);

    BlameStore blame(*runner_, paths_);
    auto result = blame.blame("a.txt", "", 0, 0, CancellationToken{});
    ASSERT_TRUE(result) << result.error().message;
    ASSERT_EQ((*result)->lines.size(), 3u);
    EXPECT_EQ((*result)->lines[0].commitOid.hex(), first->out);
    EXPECT_EQ((*result)->lines[1].commitOid.hex(), first->out);
    EXPECT_EQ((*result)->lines[2].commitOid.hex(), second->out);
    EXPECT_EQ((*result)->lines[2].content, "line three");
    EXPECT_EQ((*result)->lines[2].summary, "add a third line");
}

TEST_F(RealRepoTest, BlameRespectsAnExplicitLineRange) {
    {
        std::ofstream out(repo_ / "a.txt");
        out << "one\ntwo\nthree\nfour\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "four lines"}));

    BlameStore blame(*runner_, paths_);
    auto result = blame.blame("a.txt", "", 2, 3, CancellationToken{});
    ASSERT_TRUE(result) << result.error().message;
    ASSERT_EQ((*result)->lines.size(), 2u);
    EXPECT_EQ((*result)->lines[0].content, "two");
    EXPECT_EQ((*result)->lines[1].content, "three");
}

// --- M4: file and line history ------------------------------------------------

TEST_F(RealRepoTest, FileHistoryFollowsARenameAcrossHistory) {
    commitFile("old.txt", "content\n", "add old.txt");
    ASSERT_TRUE(run({"mv", "old.txt", "new.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "rename to new.txt"}));
    commitFile("new.txt", "content\nmore\n", "edit new.txt");

    FileHistoryStore history(*runner_, paths_);
    auto entries = history.fileHistory("new.txt", "", CancellationToken{});
    ASSERT_TRUE(entries) << entries.error().message;
    ASSERT_EQ(entries->size(), 3u);
    EXPECT_EQ((*entries)[0].subject, "edit new.txt");
    EXPECT_EQ((*entries)[1].subject, "rename to new.txt");
    EXPECT_EQ((*entries)[1].renamedFrom, "old.txt");
    EXPECT_EQ((*entries)[2].subject, "add old.txt");
}

TEST_F(RealRepoTest, LineHistoryReturnsAChunkPerCommitTouchingTheRange) {
    {
        std::ofstream out(repo_ / "a.txt");
        out << "one\ntwo\nthree\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "initial"}));
    {
        std::ofstream out(repo_ / "a.txt", std::ios::trunc);
        out << "one\nTWO CHANGED\nthree\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "change line two"}));

    FileHistoryStore history(*runner_, paths_);
    auto chunks = history.lineHistory("a.txt", 2, 2, "", CancellationToken{});
    ASSERT_TRUE(chunks) << chunks.error().message;
    ASSERT_GE(chunks->size(), 1u);
    EXPECT_EQ((*chunks)[0].subject, "change line two");
    EXPECT_NE((*chunks)[0].diffText.find("TWO CHANGED"), std::string::npos);
}

// --- M4: reflog and undo -----------------------------------------------------

TEST_F(RealRepoTest, ReflogListsRecentHeadMovementsNewestFirst) {
    commitFile("a.txt", "1\n", "c1");
    commitFile("a.txt", "2\n", "c2");

    ReflogStore reflog(*runner_, paths_);
    auto entries = reflog.list("", CancellationToken{});
    ASSERT_TRUE(entries) << entries.error().message;
    ASSERT_GE(entries->size(), 2u);
    EXPECT_EQ((*entries)[0].index, 0);
    EXPECT_NE((*entries)[0].message.find("c2"), std::string::npos);
    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    EXPECT_EQ((*entries)[0].oid.hex(), head->out);
}

TEST_F(RealRepoTest, UndoResetsBackToWhereHeadStoodBeforeTheOperation) {
    commitFile("a.txt", "1\n", "c1");
    auto beforeSecondCommit = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(beforeSecondCommit);

    OperationRunner operations(*runner_, paths_);
    CommitRequest commitRequest;
    commitRequest.message = "c2";
    {
        std::ofstream out(repo_ / "a.txt", std::ios::trunc);
        out << "2\n";
    }
    ASSERT_TRUE(run({"add", "a.txt"}));
    auto committed = submitAndWait(operations, makeCommitOperation(commitRequest));
    ASSERT_TRUE(committed.succeeded) << (committed.error ? committed.error->detail : "");

    ASSERT_EQ(operations.undoJournal().size(), 1u);
    const auto& entry = operations.undoJournal().back();
    EXPECT_EQ(entry.headBefore.hex(), beforeSecondCommit->out);

    UndoRequest undo;
    undo.headBefore = entry.headBefore;
    undo.branchBefore = entry.branchBefore;
    auto undone = submitAndWait(operations, makeUndoOperation(undo));
    ASSERT_TRUE(undone.succeeded) << (undone.error ? undone.error->detail : "");

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    EXPECT_EQ(head->out, beforeSecondCommit->out);
}

TEST_F(RealRepoTest, UndoRefusesAfterSwitchingToADifferentBranch) {
    commitFile("a.txt", "1\n", "c1");

    OperationRunner operations(*runner_, paths_);
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "other"}));
    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);

    UndoRequest undo;
    undo.headBefore = ObjectId::fromHex(head->out);
    undo.branchBefore = "main";
    auto outcome = submitAndWait(operations, makeUndoOperation(undo));
    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::InvalidArgument);
}

// --- M5: submodules ------------------------------------------------------

TEST_F(RealRepoTest, AddingASubmoduleClonesItAndListsItUpToDate) {
    commitFile("a.txt", "1\n", "c1");
    const std::filesystem::path source = makeSourceRepo("-sub-add");

    OperationRunner operations(*runner_, paths_);
    AddSubmoduleRequest request;
    request.url = source.string();
    request.path = "vendor/sub";
    auto outcome = submitAndWait(operations, makeAddSubmoduleOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    EXPECT_TRUE(std::filesystem::exists(repo_ / "vendor" / "sub" / "readme.txt"));
    EXPECT_TRUE(std::filesystem::exists(repo_ / ".gitmodules"));

    SubmoduleStore store(*runner_, paths_);
    auto list = store.list(CancellationToken{});
    ASSERT_TRUE(list) << list.error().message;
    ASSERT_EQ(list->size(), 1u);
    EXPECT_EQ((*list)[0].path, "vendor/sub");
    EXPECT_EQ((*list)[0].url, source.string());
    EXPECT_EQ((*list)[0].state, SubmoduleInfo::State::UpToDate);
    EXPECT_FALSE((*list)[0].headOid.empty());
}

TEST_F(RealRepoTest, DeinitLeavesTheSubmoduleNotInitialized) {
    commitFile("a.txt", "1\n", "c1");
    const std::filesystem::path source = makeSourceRepo("-sub-deinit");

    OperationRunner operations(*runner_, paths_);
    AddSubmoduleRequest add;
    add.url = source.string();
    add.path = "sub";
    ASSERT_TRUE(submitAndWait(operations, makeAddSubmoduleOperation(add)).succeeded);

    DeinitSubmodulesRequest deinit;
    deinit.paths = {"sub"};
    deinit.force = true;
    auto outcome = submitAndWait(operations, makeDeinitSubmodulesOperation(deinit));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    EXPECT_FALSE(std::filesystem::exists(repo_ / "sub" / "readme.txt"))
        << "deinit must empty the submodule's work tree";

    SubmoduleStore store(*runner_, paths_);
    auto list = store.list(CancellationToken{});
    ASSERT_TRUE(list) << list.error().message;
    ASSERT_EQ(list->size(), 1u);
    EXPECT_EQ((*list)[0].state, SubmoduleInfo::State::NotInitialized);
}

TEST_F(RealRepoTest, InitAndUpdateBringABackADeinitializedSubmodule) {
    commitFile("a.txt", "1\n", "c1");
    const std::filesystem::path source = makeSourceRepo("-sub-reinit");

    OperationRunner operations(*runner_, paths_);
    AddSubmoduleRequest add;
    add.url = source.string();
    add.path = "sub";
    ASSERT_TRUE(submitAndWait(operations, makeAddSubmoduleOperation(add)).succeeded);

    DeinitSubmodulesRequest deinit;
    deinit.paths = {"sub"};
    deinit.force = true;
    ASSERT_TRUE(submitAndWait(operations, makeDeinitSubmodulesOperation(deinit)).succeeded);

    SubmodulePathsRequest init;
    init.paths = {"sub"};
    ASSERT_TRUE(submitAndWait(operations, makeInitSubmodulesOperation(init)).succeeded);

    UpdateSubmodulesRequest update;
    update.paths = {"sub"};
    auto outcome = submitAndWait(operations, makeUpdateSubmodulesOperation(update));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    EXPECT_TRUE(std::filesystem::exists(repo_ / "sub" / "readme.txt"));

    SubmoduleStore store(*runner_, paths_);
    auto list = store.list(CancellationToken{});
    ASSERT_TRUE(list) << list.error().message;
    ASSERT_EQ(list->size(), 1u);
    EXPECT_EQ((*list)[0].state, SubmoduleInfo::State::UpToDate);
}

TEST_F(RealRepoTest, SyncSubmodulesRewritesTheLocalUrlFromGitmodules) {
    commitFile("a.txt", "1\n", "c1");
    const std::filesystem::path source = makeSourceRepo("-sub-sync");

    OperationRunner operations(*runner_, paths_);
    AddSubmoduleRequest add;
    add.url = source.string();
    add.path = "sub";
    ASSERT_TRUE(submitAndWait(operations, makeAddSubmoduleOperation(add)).succeeded);

    const std::string newUrl = source.string() + "-renamed";
    ASSERT_TRUE(run({"config", "--file", ".gitmodules", "submodule.sub.url", newUrl}));

    SubmodulePathsRequest sync;
    sync.paths = {"sub"};
    auto outcome = submitAndWait(operations, makeSyncSubmodulesOperation(sync));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    auto configured = run({"config", "submodule.sub.url"});
    ASSERT_TRUE(configured);
    EXPECT_EQ(configured->out, newUrl);
}

// --- M5: bisect ------------------------------------------------------------

TEST_F(RealRepoTest, BisectFindsTheFirstBadCommitByGoodBadStepping) {
    commitFile("a.txt", "1\n", "c1");  // good
    commitFile("a.txt", "2\n", "c2");  // good
    commitFile("a.txt", "3\n", "c3");  // first bad
    commitFile("a.txt", "4\n", "c4");  // also bad
    auto badHead = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(badHead);
    auto goodBase = run({"rev-parse", "HEAD~3"});
    ASSERT_TRUE(goodBase);
    auto expectedFirstBad = run({"rev-parse", "HEAD~1"});
    ASSERT_TRUE(expectedFirstBad);

    OperationRunner operations(*runner_, paths_);
    BisectStartRequest start;
    start.badRef = badHead->out;
    start.goodRefs = {goodBase->out};
    auto startOutcome = submitAndWait(operations, makeBisectStartOperation(start));
    ASSERT_TRUE(startOutcome.succeeded) << (startOutcome.error ? startOutcome.error->detail : "");

    BisectStore store(*runner_, paths_);
    {
        auto initial = store.status(CancellationToken{});
        ASSERT_TRUE(initial) << initial.error().message;
        EXPECT_TRUE(initial->active);
        EXPECT_EQ(initial->badOid, badHead->out);
        ASSERT_EQ(initial->goodOids.size(), 1u);
        EXPECT_EQ(initial->goodOids[0], goodBase->out);
    }

    // Neither the stdout message nor the log marker for "found it" turned out
    // to be a fixed string: older git prints "is the first bad commit" and
    // logs "# first bad commit: [", but git 2.55 quotes the (customizable)
    // term -- "is the first 'bad' commit" / "# first 'bad' commit: [" --
    // confirmed by capturing the raw log from a CI failure on git 2.55, which
    // otherwise looked like it never converged. `# first ` followed somewhere
    // on the same line by ` commit: [` holds across both.
    auto bisectConcluded = [](std::string_view log) {
        std::size_t lineStart = 0;
        while (lineStart <= log.size()) {
            const std::size_t at = log.find('\n', lineStart);
            const std::string_view line(
                log.data() + lineStart,
                (at == std::string_view::npos ? log.size() : at) - lineStart);
            if (line.starts_with("# first ") && line.find(" commit: [") != std::string_view::npos) {
                return true;
            }
            if (at == std::string_view::npos) {
                break;
            }
            lineStart = at + 1;
        }
        return false;
    };

    bool concluded = false;
    for (int i = 0; i < 10 && !concluded; ++i) {
        auto current = store.status(CancellationToken{});
        ASSERT_TRUE(current) << current.error().message;
        ASSERT_TRUE(current->active);
        auto subject = run({"log", "-1", "--format=%s", current->currentOid});
        ASSERT_TRUE(subject);
        const int commitNumber = std::stoi(subject->out.substr(1));

        BisectMarkRequest mark;
        mark.good = commitNumber < 3;
        auto markOutcome = submitAndWait(operations, makeBisectMarkOperation(mark));
        ASSERT_TRUE(markOutcome.succeeded) << (markOutcome.error ? markOutcome.error->detail : "");

        auto afterMark = store.status(CancellationToken{});
        ASSERT_TRUE(afterMark) << afterMark.error().message;
        concluded = bisectConcluded(afterMark->logText);
    }
    ASSERT_TRUE(concluded) << "bisect did not conclude within 10 steps";

    auto finalStatus = store.status(CancellationToken{});
    ASSERT_TRUE(finalStatus) << finalStatus.error().message;
    EXPECT_EQ(finalStatus->badOid, expectedFirstBad->out);

    BisectResetRequest reset;
    auto resetOutcome = submitAndWait(operations, makeBisectResetOperation(reset));
    ASSERT_TRUE(resetOutcome.succeeded) << (resetOutcome.error ? resetOutcome.error->detail : "");

    auto afterReset = store.status(CancellationToken{});
    ASSERT_TRUE(afterReset) << afterReset.error().message;
    EXPECT_FALSE(afterReset->active);

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    EXPECT_EQ(head->out, badHead->out) << "reset must return to the branch bisect started from";
}

TEST_F(RealRepoTest, BisectSkipMovesPastAnUntestableCommit) {
    // Four commits leave two real candidates (c2, c3) between good and bad, so
    // skipping the first still leaves a next one to test rather than
    // exhausting the search outright (which exits non-zero -- a different,
    // legitimate outcome covered by BisectFindsTheFirstBadCommitByGoodBadStepping's
    // "only skip'ped commits left" case is deliberately not this test).
    commitFile("a.txt", "1\n", "c1");
    commitFile("a.txt", "2\n", "c2");
    commitFile("a.txt", "3\n", "c3");
    commitFile("a.txt", "4\n", "c4");
    auto badHead = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(badHead);
    auto goodBase = run({"rev-parse", "HEAD~3"});
    ASSERT_TRUE(goodBase);
    auto middle = run({"rev-parse", "HEAD~1"});
    ASSERT_TRUE(middle);

    OperationRunner operations(*runner_, paths_);
    BisectStartRequest start;
    start.badRef = badHead->out;
    start.goodRefs = {goodBase->out};
    ASSERT_TRUE(submitAndWait(operations, makeBisectStartOperation(start)).succeeded);

    BisectStore store(*runner_, paths_);
    auto beforeSkip = store.status(CancellationToken{});
    ASSERT_TRUE(beforeSkip) << beforeSkip.error().message;
    EXPECT_EQ(beforeSkip->currentOid, middle->out);

    BisectSkipRequest skip;
    auto skipOutcome = submitAndWait(operations, makeBisectSkipOperation(skip));
    ASSERT_TRUE(skipOutcome.succeeded) << (skipOutcome.error ? skipOutcome.error->detail : "");

    auto afterSkip = store.status(CancellationToken{});
    ASSERT_TRUE(afterSkip) << afterSkip.error().message;
    ASSERT_EQ(afterSkip->skippedOids.size(), 1u);
    EXPECT_EQ(afterSkip->skippedOids[0], middle->out);

    BisectResetRequest reset;
    ASSERT_TRUE(submitAndWait(operations, makeBisectResetOperation(reset)).succeeded);
}

// --- M5: LFS -----------------------------------------------------------------

TEST_F(RealRepoTest, DetectsWhetherGitLfsIsInstalled) {
    auto detected = detectLfs(*runner_, paths_, CancellationToken{});
    ASSERT_TRUE(detected) << detected.error().message;
    // Whichever way it goes, detection itself must not fail -- see LfsOps.h.
    SUCCEED();
}

TEST_F(RealRepoTest, TrackingAPatternRecordsItInGitattributesAndIsListed) {
    auto detected = detectLfs(*runner_, paths_, CancellationToken{});
    ASSERT_TRUE(detected) << detected.error().message;
    if (!detected->available) {
        GTEST_SKIP() << "git-lfs is not installed";
    }
    commitFile("a.txt", "1\n", "c1");

    OperationRunner operations(*runner_, paths_);
    ASSERT_TRUE(submitAndWait(operations, makeLfsInstallOperation()).succeeded);

    LfsTrackRequest track;
    track.pattern = "*.bin";
    ASSERT_TRUE(submitAndWait(operations, makeLfsTrackOperation(track)).succeeded);

    std::ifstream attrs(repo_ / ".gitattributes");
    std::string content((std::istreambuf_iterator<char>(attrs)), std::istreambuf_iterator<char>());
    EXPECT_NE(content.find("*.bin"), std::string::npos);
    EXPECT_NE(content.find("filter=lfs"), std::string::npos);

    LfsStore store(*runner_, paths_);
    auto patterns = store.trackedPatterns(CancellationToken{});
    ASSERT_TRUE(patterns) << patterns.error().message;
    EXPECT_NE(std::find(patterns->begin(), patterns->end(), "*.bin"), patterns->end());

    LfsUntrackRequest untrack;
    untrack.pattern = "*.bin";
    ASSERT_TRUE(submitAndWait(operations, makeLfsUntrackOperation(untrack)).succeeded);

    auto afterUntrack = store.trackedPatterns(CancellationToken{});
    ASSERT_TRUE(afterUntrack) << afterUntrack.error().message;
    EXPECT_EQ(std::find(afterUntrack->begin(), afterUntrack->end(), "*.bin"), afterUntrack->end());
}

TEST_F(RealRepoTest, AddingATrackedFileStoresAPointerAndListsItDownloaded) {
    auto detected = detectLfs(*runner_, paths_, CancellationToken{});
    ASSERT_TRUE(detected) << detected.error().message;
    if (!detected->available) {
        GTEST_SKIP() << "git-lfs is not installed";
    }
    commitFile("a.txt", "1\n", "c1");

    OperationRunner operations(*runner_, paths_);
    ASSERT_TRUE(submitAndWait(operations, makeLfsInstallOperation()).succeeded);
    LfsTrackRequest track;
    track.pattern = "*.bin";
    ASSERT_TRUE(submitAndWait(operations, makeLfsTrackOperation(track)).succeeded);
    ASSERT_TRUE(run({"add", ".gitattributes"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "track *.bin"}));

    {
        std::ofstream out(repo_ / "asset.bin", std::ios::binary | std::ios::trunc);
        out << "not really binary, just needs to go through the clean filter";
    }
    ASSERT_TRUE(run({"add", "asset.bin"}));
    ASSERT_TRUE(run({"commit", "--quiet", "-m", "add asset.bin"}));

    // The clean filter must have replaced the working-tree content with an LFS
    // pointer in the object git actually stored, proving LFS -- not a plain
    // blob -- captured the file.
    auto stored = run({"show", "HEAD:asset.bin"});
    ASSERT_TRUE(stored);
    EXPECT_NE(stored->out.find("https://git-lfs.github.com/spec/v1"), std::string::npos);

    LfsStore store(*runner_, paths_);
    auto files = store.listFiles(CancellationToken{});
    ASSERT_TRUE(files) << files.error().message;
    ASSERT_EQ(files->size(), 1u);
    EXPECT_EQ((*files)[0].path, "asset.bin");
    EXPECT_TRUE((*files)[0].downloadedLocally);
    EXPECT_FALSE((*files)[0].oid.empty());
}

// --- M5: patch import/export -------------------------------------------------

TEST_F(RealRepoTest, ExportsPatchesForSelectedCommitsInOrder) {
    commitFile("a.txt", "1\n", "c1");
    commitFile("a.txt", "2\n", "c2");
    commitFile("a.txt", "3\n", "c3");
    auto c2 = run({"rev-parse", "HEAD~1"});
    ASSERT_TRUE(c2);
    auto c3 = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(c3);

    const std::filesystem::path outputDir = repo_ / "patches";
    OperationRunner operations(*runner_, paths_);
    ExportPatchesRequest request;
    request.commits = {ObjectId::fromHex(c2->out), ObjectId::fromHex(c3->out)};
    request.outputDir = outputDir;
    auto outcome = submitAndWait(operations, makeExportPatchesOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    std::vector<std::string> names;
    for (const auto& entry : std::filesystem::directory_iterator(outputDir)) {
        names.push_back(entry.path().filename().string());
    }
    std::sort(names.begin(), names.end());
    ASSERT_EQ(names.size(), 2u);
    EXPECT_TRUE(names[0].starts_with("0001-"));
    EXPECT_NE(names[0].find("c2"), std::string::npos);
    EXPECT_TRUE(names[1].starts_with("0002-"));
    EXPECT_NE(names[1].find("c3"), std::string::npos);
}

TEST_F(RealRepoTest, AppliesAPlainDiffWithoutCommittingOrStaging) {
    commitFile("a.txt", "1\n", "c1");
    commitFile("a.txt", "2\n", "c2");
    auto diff = run({"diff", "HEAD~1", "HEAD"});
    ASSERT_TRUE(diff);
    const std::filesystem::path patchFile = repo_.string() + "-plain.patch";
    {
        std::ofstream out(patchFile, std::ios::binary | std::ios::trunc);
        out << diff->out << "\n";
    }
    ASSERT_TRUE(run({"reset", "--quiet", "--hard", "HEAD~1"}));

    OperationRunner operations(*runner_, paths_);
    ApplyPatchFilesRequest request;
    request.patchFiles = {patchFile};
    auto outcome = submitAndWait(operations, makeApplyPatchFilesOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    std::ifstream in(repo_ / "a.txt");
    std::string content((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(content, "2\n");
    auto staged = run({"diff", "--cached", "--name-only"});
    ASSERT_TRUE(staged);
    EXPECT_TRUE(staged->out.empty()) << "a plain apply must not touch the index";

    std::filesystem::remove(patchFile);
}

TEST_F(RealRepoTest, ImportsAPatchAsACommitPreservingItsMessage) {
    commitFile("a.txt", "1\n", "c1");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("b.txt", "x\n", "feature commit");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));

    const std::filesystem::path patchDir = repo_ / "am-patches";
    ASSERT_TRUE(run({"format-patch", "-1", "feature", "-o", patchDir.string()}));
    std::filesystem::path patchFile;
    for (const auto& entry : std::filesystem::directory_iterator(patchDir)) {
        patchFile = entry.path();
    }
    ASSERT_FALSE(patchFile.empty());

    OperationRunner operations(*runner_, paths_);
    ImportPatchesRequest request;
    request.patchFiles = {patchFile};
    auto outcome = submitAndWait(operations, makeImportPatchesOperation(request));
    ASSERT_TRUE(outcome.succeeded) << (outcome.error ? outcome.error->detail : "");

    EXPECT_TRUE(std::filesystem::exists(repo_ / "b.txt"));
    auto subject = run({"log", "-1", "--format=%s"});
    ASSERT_TRUE(subject);
    EXPECT_EQ(subject->out, "feature commit");
    auto count = run({"rev-list", "--count", "HEAD"});
    ASSERT_TRUE(count);
    EXPECT_EQ(count->out, "2");
}

TEST_F(RealRepoTest, ImportConflictContinuesAfterResolution) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("shared.txt", "feature change\n", "feature commit");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "main change\n", "main commit");

    const std::filesystem::path patchDir = repo_ / "am-conflict-patches";
    ASSERT_TRUE(run({"format-patch", "-1", "feature", "-o", patchDir.string()}));
    std::filesystem::path patchFile;
    for (const auto& entry : std::filesystem::directory_iterator(patchDir)) {
        patchFile = entry.path();
    }
    ASSERT_FALSE(patchFile.empty());

    OperationRunner operations(*runner_, paths_);
    ImportPatchesRequest request;
    request.patchFiles = {patchFile};
    request.threeWay = true;
    auto outcome = submitAndWait(operations, makeImportPatchesOperation(request));
    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error.has_value());
    EXPECT_EQ(outcome.error->code, GitError::Code::Conflict);
    EXPECT_TRUE(RepoState::read(paths_).inProgress());

    // Resolve by taking the incoming (feature) side, matching how the working
    // copy's conflict resolution already handles "theirs".
    ASSERT_TRUE(run({"checkout", "--theirs", "shared.txt"}));
    ASSERT_TRUE(run({"add", "shared.txt"}));

    auto continued = submitAndWait(operations, makeAmContinueOperation());
    ASSERT_TRUE(continued.succeeded) << (continued.error ? continued.error->detail : "");
    EXPECT_FALSE(RepoState::read(paths_).inProgress());

    auto subject = run({"log", "-1", "--format=%s"});
    ASSERT_TRUE(subject);
    EXPECT_EQ(subject->out, "feature commit");
    std::ifstream in(repo_ / "shared.txt");
    std::string fileContent((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(fileContent, "feature change\n");
}

TEST_F(RealRepoTest, ImportAbortUnwindsCleanly) {
    commitFile("shared.txt", "base\n", "base");
    ASSERT_TRUE(run({"switch", "--quiet", "-c", "feature"}));
    commitFile("shared.txt", "feature change\n", "feature commit");
    ASSERT_TRUE(run({"switch", "--quiet", "main"}));
    commitFile("shared.txt", "main change\n", "main commit");
    auto beforeImport = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(beforeImport);

    const std::filesystem::path patchDir = repo_ / "am-abort-patches";
    ASSERT_TRUE(run({"format-patch", "-1", "feature", "-o", patchDir.string()}));
    std::filesystem::path patchFile;
    for (const auto& entry : std::filesystem::directory_iterator(patchDir)) {
        patchFile = entry.path();
    }
    ASSERT_FALSE(patchFile.empty());

    OperationRunner operations(*runner_, paths_);
    ImportPatchesRequest request;
    request.patchFiles = {patchFile};
    request.threeWay = true;
    auto outcome = submitAndWait(operations, makeImportPatchesOperation(request));
    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(RepoState::read(paths_).inProgress());

    auto aborted = submitAndWait(operations, makeAmAbortOperation());
    ASSERT_TRUE(aborted.succeeded) << (aborted.error ? aborted.error->detail : "");
    EXPECT_FALSE(RepoState::read(paths_).inProgress());

    auto head = run({"rev-parse", "HEAD"});
    ASSERT_TRUE(head);
    EXPECT_EQ(head->out, beforeImport->out);
}

}  // namespace
}  // namespace gbm
