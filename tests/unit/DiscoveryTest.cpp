// Discovery and cache tests.
//
// The awkward cases here are the ones that matter in practice: a `.git` file
// pointing at a linked worktree, a repository inside `node_modules`, a symlink
// cycle, and — most importantly — that a *cancelled* scan never marks
// repositories as missing.
#include "core/base/CancellationToken.h"
#include "core/cache/RepoIndexDb.h"
#include "core/discovery/RepoClassifier.h"
#include "core/discovery/Scanner.h"
#include "core/discovery/SkipRules.h"

#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

/// Builds a throwaway directory tree and removes it afterwards.
class TempTree : public ::testing::Test {
protected:
    void SetUp() override {
        // Suite + test name keeps parallel ctest jobs from colliding without
        // needing a platform-specific process id.
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        root_ =
            std::filesystem::temp_directory_path() /
            ("gbm-test-" + std::string(info->test_suite_name()) + "-" + std::string(info->name()));
        std::filesystem::remove_all(root_);
        std::filesystem::create_directories(root_);
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(root_, ec);
    }

    std::filesystem::path makeDir(const std::string& relative) {
        const auto path = root_ / relative;
        std::filesystem::create_directories(path);
        return path;
    }

    void writeFile(const std::filesystem::path& path, const std::string& contents) {
        std::filesystem::create_directories(path.parent_path());
        std::ofstream out(path, std::ios::binary | std::ios::trunc);
        out << contents;
    }

    /// A minimally valid non-bare repository: `.git/` containing HEAD.
    std::filesystem::path makeNormalRepo(const std::string& relative) {
        const auto work = makeDir(relative);
        writeFile(work / ".git" / "HEAD", "ref: refs/heads/main\n");
        makeDir(relative + "/.git/refs");
        makeDir(relative + "/.git/objects");
        return work;
    }

    std::filesystem::path root_;
};

// --- classification --------------------------------------------------------

using ClassifierTest = TempTree;

TEST_F(ClassifierTest, RecognisesANormalCheckout) {
    const auto work = makeNormalRepo("project");

    const ClassifiedRepo result = RepoClassifier::classify(work);
    ASSERT_TRUE(result.isRepo());
    EXPECT_EQ(result.kind, RepoKind::Normal);
    EXPECT_EQ(result.paths.workDir(), work);
    EXPECT_EQ(result.paths.gitDir(), work / ".git");
    EXPECT_FALSE(result.paths.isLinkedWorktree());
}

TEST_F(ClassifierTest, RecognisesABareRepository) {
    const auto bare = makeDir("mirror.git");
    writeFile(bare / "HEAD", "ref: refs/heads/main\n");
    writeFile(bare / "config", "[core]\n\tbare = true\n");
    makeDir("mirror.git/objects");
    makeDir("mirror.git/refs");

    const ClassifiedRepo result = RepoClassifier::classify(bare);
    ASSERT_TRUE(result.isRepo());
    EXPECT_EQ(result.kind, RepoKind::Bare);
    EXPECT_TRUE(result.paths.isBare());
    EXPECT_TRUE(result.paths.workDir().empty());
}

TEST_F(ClassifierTest, DoesNotTreatANonBareRepoDirAsBare) {
    // `core.bare = false` must win over the directory shape, otherwise a normal
    // repository's own .git directory would be reported as a separate bare repo.
    const auto dir = makeDir("notbare");
    writeFile(dir / "HEAD", "ref: refs/heads/main\n");
    writeFile(dir / "config", "[core]\n\tbare = false\n");
    makeDir("notbare/objects");
    makeDir("notbare/refs");

    EXPECT_FALSE(RepoClassifier::looksBare(dir));
}

TEST_F(ClassifierTest, RecognisesALinkedWorktreeFromItsGitFile) {
    const auto main = makeNormalRepo("main");
    const auto worktreeGitDir = main / ".git" / "worktrees" / "feature";
    std::filesystem::create_directories(worktreeGitDir);
    writeFile(worktreeGitDir / "HEAD", "ref: refs/heads/feature\n");
    writeFile(worktreeGitDir / "commondir", "../..\n");

    const auto worktree = makeDir("feature-wt");
    writeFile(worktree / ".git", "gitdir: " + worktreeGitDir.string() + "\n");

    const ClassifiedRepo result = RepoClassifier::classify(worktree);
    ASSERT_TRUE(result.isRepo());
    EXPECT_EQ(result.kind, RepoKind::LinkedWorktree);
    EXPECT_TRUE(result.paths.isLinkedWorktree());
    // The common dir must resolve to the main repository, or shared refs and
    // objects would be looked for in the wrong place.
    EXPECT_EQ(result.paths.commonDir(), (main / ".git").lexically_normal());
}

TEST_F(ClassifierTest, RecognisesASubmodule) {
    const auto parent = makeNormalRepo("parent");
    const auto moduleGitDir = parent / ".git" / "modules" / "sub";
    std::filesystem::create_directories(moduleGitDir);
    writeFile(moduleGitDir / "HEAD", "ref: refs/heads/main\n");

    const auto sub = makeDir("parent/sub");
    writeFile(sub / ".git", "gitdir: " + moduleGitDir.string() + "\n");

    const ClassifiedRepo result = RepoClassifier::classify(sub);
    ASSERT_TRUE(result.isRepo());
    EXPECT_EQ(result.kind, RepoKind::Submodule);
}

TEST_F(ClassifierTest, ResolvesARelativeGitDirPointer) {
    const auto main = makeNormalRepo("rel");
    const auto worktreeGitDir = main / ".git" / "worktrees" / "wt";
    std::filesystem::create_directories(worktreeGitDir);

    const auto worktree = makeDir("rel-wt");
    // Relative pointers are what git actually writes for worktrees created inside
    // the same tree.
    writeFile(worktree / ".git", "gitdir: ../rel/.git/worktrees/wt\n");

    const ClassifiedRepo result = RepoClassifier::classify(worktree);
    ASSERT_TRUE(result.isRepo());
    EXPECT_EQ(result.kind, RepoKind::LinkedWorktree);
}

TEST_F(ClassifierTest, ReportsADanglingGitPointerAsUnreadable) {
    // A worktree whose parent repository was deleted. Reporting it as a working
    // repository would produce a broken entry the user cannot open.
    const auto worktree = makeDir("orphan");
    writeFile(worktree / ".git", "gitdir: /nonexistent/path/.git/worktrees/x\n");

    const ClassifiedRepo result = RepoClassifier::classify(worktree);
    EXPECT_FALSE(result.isRepo());
    EXPECT_TRUE(result.unreadable);
}

TEST_F(ClassifierTest, PlainDirectoriesAreNotRepositories) {
    EXPECT_FALSE(RepoClassifier::classify(makeDir("just-a-folder")).isRepo());
}

// --- skip rules ------------------------------------------------------------

TEST(SkipRules, SkipsDependencyAndBuildTrees) {
    const SkipRules rules;
    EXPECT_TRUE(rules.shouldSkipName("node_modules"));
    EXPECT_TRUE(rules.shouldSkipName("__pycache__"));
    EXPECT_TRUE(rules.shouldSkipName(".git"));
    EXPECT_TRUE(rules.shouldSkipName("target"));
    EXPECT_FALSE(rules.shouldSkipName("src"));
    EXPECT_FALSE(rules.shouldSkipName("my-project"));
}

TEST(SkipRules, SupportsATrailingWildcard) {
    const SkipRules rules;
    EXPECT_TRUE(rules.shouldSkipName("build"));
    EXPECT_TRUE(rules.shouldSkipName("build-debug"));
    EXPECT_TRUE(rules.shouldSkipName("cmake-build-release"));
    EXPECT_FALSE(rules.shouldSkipName("buildings"))
        << "'build*' should not be so greedy it eats unrelated names"
        << " (this is 'build-*' plus exact 'build')";
}

TEST(SkipRules, AcceptsUserPatterns) {
    SkipRules rules;
    EXPECT_FALSE(rules.shouldSkipName("Archive"));
    rules.addPattern("Archive");
    EXPECT_TRUE(rules.shouldSkipName("Archive"));
    rules.clearUserPatterns();
    EXPECT_FALSE(rules.shouldSkipName("Archive"));
}

// --- cache -----------------------------------------------------------------

TEST(RepoIndexDb, RoundTripsBaseFoldersAndRepos) {
    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());

    auto folderId = db.addBaseFolder("/work", 6, false);
    ASSERT_TRUE(folderId);

    auto folders = db.baseFolders();
    ASSERT_TRUE(folders);
    ASSERT_EQ(folders->size(), 1u);
    EXPECT_EQ((*folders)[0].path, "/work");

    RepoRecord record;
    record.baseFolderId = *folderId;
    record.workDir = "/work/project";
    record.gitDir = "/work/project/.git";
    record.commonDir = "/work/project/.git";
    record.kind = RepoKind::Normal;
    record.name = "project";
    record.lastSeenGeneration = 1;
    ASSERT_TRUE(db.upsertRepo(record));

    auto repos = db.repos();
    ASSERT_TRUE(repos);
    ASSERT_EQ(repos->size(), 1u);
    EXPECT_EQ((*repos)[0].name, "project");
    EXPECT_EQ((*repos)[0].toPaths().gitDir(), std::filesystem::path("/work/project/.git"));
}

TEST(RepoIndexDb, UpsertIsIdempotentOnGitDir) {
    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    auto folderId = db.addBaseFolder("/work");
    ASSERT_TRUE(folderId);

    RepoRecord record;
    record.baseFolderId = *folderId;
    record.workDir = "/work/p";
    record.gitDir = "/work/p/.git";
    record.commonDir = "/work/p/.git";
    record.name = "p";
    record.lastSeenGeneration = 1;

    auto first = db.upsertRepo(record);
    record.lastSeenGeneration = 2;
    auto second = db.upsertRepo(record);
    ASSERT_TRUE(first);
    ASSERT_TRUE(second);
    EXPECT_EQ(*first, *second) << "rescanning must update, not duplicate";

    auto repos = db.repos();
    ASSERT_TRUE(repos);
    EXPECT_EQ(repos->size(), 1u);
}

TEST(RepoIndexDb, MarkMissingIsASoftDeleteThatReverses) {
    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    auto folderId = db.addBaseFolder("/work");
    ASSERT_TRUE(folderId);

    RepoRecord record;
    record.baseFolderId = *folderId;
    record.workDir = "/work/p";
    record.gitDir = "/work/p/.git";
    record.commonDir = "/work/p/.git";
    record.name = "p";
    record.lastSeenGeneration = 1;
    ASSERT_TRUE(db.upsertRepo(record));

    // A later scan generation did not see it.
    auto marked = db.markMissing(*folderId, 2);
    ASSERT_TRUE(marked);
    EXPECT_EQ(*marked, 1);
    EXPECT_EQ(db.repos()->size(), 0u);
    EXPECT_EQ(db.repos(true)->size(), 1u) << "the row must survive for its user metadata";

    // Reappearing (an unmounted drive came back) must clear the mark.
    record.lastSeenGeneration = 3;
    ASSERT_TRUE(db.upsertRepo(record));
    EXPECT_EQ(db.repos()->size(), 1u);
}

TEST(RepoIndexDb, StoresAndReadsBackAProbe) {
    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    auto folderId = db.addBaseFolder("/work");
    RepoRecord record;
    record.baseFolderId = *folderId;
    record.workDir = "/work/p";
    record.gitDir = "/work/p/.git";
    record.commonDir = "/work/p/.git";
    record.name = "p";
    auto repoId = db.upsertRepo(record);
    ASSERT_TRUE(repoId);

    RepoProbe probe;
    probe.repoId = *repoId;
    probe.headKind = 0;
    probe.headRef = "refs/heads/main";
    probe.headOid = ObjectId::fromHex(std::string(40, 'c'));
    probe.ahead = 3;
    probe.behind = 1;
    probe.dirtyFiles = 5;
    probe.gitDirMtimeNs = 123456789;
    ASSERT_TRUE(db.saveProbe(probe));

    auto loaded = db.probe(*repoId);
    ASSERT_TRUE(loaded);
    ASSERT_TRUE(*loaded);
    EXPECT_EQ((*loaded)->headRef, "refs/heads/main");
    EXPECT_EQ((*loaded)->headOid, probe.headOid);
    EXPECT_EQ((*loaded)->ahead, 3);
    EXPECT_EQ((*loaded)->dirtyFiles, 5);
    EXPECT_EQ((*loaded)->gitDirMtimeNs, 123456789);
}

TEST(RepoIndexDb, SearchEscapesLikeMetacharacters) {
    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    auto folderId = db.addBaseFolder("/work");

    for (const char* name : {"alpha", "beta", "100%real"}) {
        RepoRecord record;
        record.baseFolderId = *folderId;
        record.workDir = std::string("/work/") + name;
        record.gitDir = std::string("/work/") + name + "/.git";
        record.commonDir = record.gitDir;
        record.name = name;
        ASSERT_TRUE(db.upsertRepo(record));
    }

    EXPECT_EQ(db.search("alpha")->size(), 1u);
    // A bare '%' would otherwise match every row.
    auto percent = db.search("%");
    ASSERT_TRUE(percent);
    EXPECT_EQ(percent->size(), 1u) << "'%' must be treated as a literal character";
    EXPECT_EQ((*percent)[0].name, "100%real");
}

TEST(RepoIndexDb, RefusesACacheFromANewerSchema) {
    // The cache is rebuildable, so refusing is strictly better than silently
    // misreading a future layout.
    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    ASSERT_TRUE(db.database().execute("UPDATE schema_info SET version = 9999;"));

    auto migrated = db.migrate();
    ASSERT_FALSE(migrated);
    EXPECT_EQ(migrated.error().code, GitError::Code::Unsupported);
}

// --- scanner ---------------------------------------------------------------

using ScannerTest = TempTree;

TEST_F(ScannerTest, FindsRepositoriesAndSkipsNoise) {
    makeNormalRepo("one");
    makeNormalRepo("nested/two");
    // A repository inside node_modules must not be reported: the skip rules are
    // what keep a scan of a developer's home directory tractable.
    makeNormalRepo("one/node_modules/pkg");
    makeDir("empty/deeper");

    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    auto folderId = db.addBaseFolder(root_.string(), 8, false);
    ASSERT_TRUE(folderId);
    auto folders = db.baseFolders();
    ASSERT_TRUE(folders);

    Scanner scanner(db);
    CancellationSource source;
    auto result = scanner.scan((*folders)[0], ScanMode::Full, source.token());
    ASSERT_TRUE(result) << result.error().message;
    EXPECT_FALSE(result->cancelled);

    auto repos = db.repos();
    ASSERT_TRUE(repos);
    EXPECT_EQ(repos->size(), 2u);
    for (const RepoRecord& repo : *repos) {
        EXPECT_EQ(repo.name.find("pkg"), std::string::npos)
            << "found a repository that should have been skipped: " << repo.workDir;
    }
}

TEST_F(ScannerTest, DoesNotDescendIntoRepositories) {
    // Descending would surface every submodule working copy as a top-level entry
    // and multiply the work for no benefit.
    makeNormalRepo("outer");
    makeNormalRepo("outer/inner");

    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    auto folderId = db.addBaseFolder(root_.string(), 8, false);
    auto folders = db.baseFolders();
    ASSERT_TRUE(folders);

    Scanner scanner(db);
    CancellationSource source;
    ASSERT_TRUE(scanner.scan((*folders)[0], ScanMode::Full, source.token()));

    auto repos = db.repos();
    ASSERT_TRUE(repos);
    EXPECT_EQ(repos->size(), 1u);
    EXPECT_EQ((*repos)[0].name, "outer");
}

TEST_F(ScannerTest, RespectsTheDepthLimit) {
    makeNormalRepo("a/b/c/d/e/deep");

    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    ASSERT_TRUE(db.addBaseFolder(root_.string(), 2, false));
    auto folders = db.baseFolders();
    ASSERT_TRUE(folders);

    Scanner scanner(db);
    CancellationSource source;
    ASSERT_TRUE(scanner.scan((*folders)[0], ScanMode::Full, source.token()));
    EXPECT_EQ(db.repos()->size(), 0u) << "the repository lies past maxDepth";
}

TEST_F(ScannerTest, CancellationNeverMarksRepositoriesAsMissing) {
    // The single most important safety property of the scanner. Most of the tree
    // is unvisited when a scan is cancelled, so running the mark-missing sweep
    // would make every repository vanish from the user's list.
    makeNormalRepo("one");
    makeNormalRepo("two");

    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    ASSERT_TRUE(db.addBaseFolder(root_.string(), 8, false));
    auto folders = db.baseFolders();
    ASSERT_TRUE(folders);

    Scanner scanner(db);
    {
        CancellationSource source;
        ASSERT_TRUE(scanner.scan((*folders)[0], ScanMode::Full, source.token()));
    }
    ASSERT_EQ(db.repos()->size(), 2u);

    // Now scan with a token that is already cancelled.
    CancellationSource cancelledSource;
    cancelledSource.cancel();
    auto result = scanner.scan((*folders)[0], ScanMode::Full, cancelledSource.token());
    ASSERT_TRUE(result);
    EXPECT_TRUE(result->cancelled);
    EXPECT_EQ(result->reposMarkedMissing, 0);
    EXPECT_EQ(db.repos()->size(), 2u) << "a cancelled scan must not delete anything";
}

TEST_F(ScannerTest, IncrementalScanPrunesUnchangedSubtrees) {
    for (int i = 0; i < 20; ++i) {
        makeDir("plain/dir" + std::to_string(i) + "/child");
    }
    makeNormalRepo("repo");

    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    ASSERT_TRUE(db.addBaseFolder(root_.string(), 8, false));
    auto folders = db.baseFolders();
    ASSERT_TRUE(folders);

    Scanner scanner(db);
    CancellationSource source;

    auto first = scanner.scan((*folders)[0], ScanMode::Full, source.token());
    ASSERT_TRUE(first);
    EXPECT_GT(first->directoriesScanned, 20);

    // The stored signatures let the second pass skip the untouched subtrees.
    folders = db.baseFolders();
    auto second = scanner.scan((*folders)[0], ScanMode::Incremental, source.token());
    ASSERT_TRUE(second);
    EXPECT_GT(second->directoriesSkipped, 0)
        << "an incremental rescan of an unchanged tree should skip work";
    EXPECT_LT(second->directoriesScanned, first->directoriesScanned);
    EXPECT_EQ(db.repos()->size(), 1u) << "pruning must not lose known repositories";
}

TEST_F(ScannerTest, ReportsRepositoriesInBatchesAsTheyAreFound) {
    for (int i = 0; i < 45; ++i) {
        makeNormalRepo("repo" + std::to_string(i));
    }

    RepoIndexDb db;
    ASSERT_TRUE(db.openInMemory());
    ASSERT_TRUE(db.addBaseFolder(root_.string(), 4, false));
    auto folders = db.baseFolders();
    ASSERT_TRUE(folders);

    std::size_t batches = 0;
    std::size_t reported = 0;
    Scanner scanner(db);
    CancellationSource source;
    auto result = scanner.scan((*folders)[0],
                               ScanMode::Full,
                               source.token(),
                               nullptr,
                               [&](const std::vector<RepoRecord>& batch) {
                                   ++batches;
                                   reported += batch.size();
                               });

    ASSERT_TRUE(result);
    EXPECT_EQ(reported, 45u);
    EXPECT_GE(batches, 2u) << "rows should appear progressively, not all at the end";
}

}  // namespace
}  // namespace gbm
