#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/ObjectId.h"
#include "core/git/AskpassHelper.h"
#include "core/git/CommitMeta.h"
#include "core/git/GitExecutable.h"
#include "core/git/HistoryProvider.h"
#include "core/git/RefStore.h"
#include "core/git/RepoPaths.h"
#include "core/workers/Debouncer.h"
#include "core/workers/ThreadPool.h"

#include <atomic>
#include <fstream>
#include <gtest/gtest.h>
#include <string>
#include <thread>
#include <vector>

namespace gbm {
namespace {

// --- ObjectId --------------------------------------------------------------

TEST(ObjectId, ParsesSha1AndSha256) {
    const std::string sha1 = "0123456789abcdef0123456789abcdef01234567";
    ObjectId id;
    ASSERT_TRUE(id.parseHex(sha1));
    EXPECT_EQ(id.byteLength(), 20u);
    EXPECT_EQ(id.hex(), sha1);
    EXPECT_EQ(id.shortHex(7), "0123456");

    const std::string sha256(64, 'a');
    ObjectId wide;
    ASSERT_TRUE(wide.parseHex(sha256));
    EXPECT_EQ(wide.byteLength(), 32u);
    EXPECT_EQ(wide.hex(), sha256);
}

TEST(ObjectId, RejectsMalformedInput) {
    ObjectId id;
    EXPECT_FALSE(id.parseHex(""));
    EXPECT_FALSE(id.parseHex("abc"));                 // too short
    EXPECT_FALSE(id.parseHex(std::string(39, 'a')));  // one short of SHA-1
    EXPECT_FALSE(id.parseHex(std::string(40, 'z')));  // not hex
    EXPECT_TRUE(id.isNull());
}

TEST(ObjectId, HashIsStableAcrossRuns) {
    // Lane colours derive from this hash, so a change would reshuffle every
    // branch colour and invalidate the graph golden tests. Pinning the value
    // makes that breakage impossible to introduce accidentally.
    const ObjectId id = ObjectId::fromHex("0123456789abcdef0123456789abcdef01234567");

    // FNV-1a over the 20 significant bytes. The literal is the contract: if this
    // ever changes, every branch colour changes with it.
    EXPECT_EQ(id.hash(), 0xd2798904d255dbbdULL);

    const ObjectId same = ObjectId::fromHex("0123456789abcdef0123456789abcdef01234567");
    EXPECT_EQ(id.hash(), same.hash());
    EXPECT_EQ(id, same);

    const ObjectId other = ObjectId::fromHex("0123456789abcdef0123456789abcdef01234568");
    EXPECT_NE(id.hash(), other.hash());
}

// --- error classification --------------------------------------------------

TEST(GitError, ClassifiesTheFailuresUsersActuallyHit) {
    struct Case {
        const char* stderrText;
        GitError::Code expected;
    };

    const Case cases[] = {
        {"error: Your local changes to the following files would be overwritten by checkout:",
         GitError::Code::DirtyWorkTree},
        {"fatal: Unable to create '/repo/.git/index.lock': File exists.", GitError::Code::LockHeld},
        {"CONFLICT (content): Merge conflict in src/main.cpp", GitError::Code::Conflict},
        {"! [rejected]        main -> main (non-fast-forward)", GitError::Code::NonFastForward},
        {"fatal: Authentication failed for 'https://example.invalid/repo.git/'",
         GitError::Code::Auth},
        {"Host key verification failed.", GitError::Code::HostKey},
        {"error: failed to push some refs: pre-receive hook declined",
         GitError::Code::HookRejected},
        {"fatal: not a git repository (or any of the parent directories): .git",
         GitError::Code::NotFound},
        {"error: unknown option `no-such-flag'", GitError::Code::Unsupported},
    };

    for (const Case& testCase : cases) {
        const GitError error = classifyGitStderr(testCase.stderrText, 128);
        EXPECT_EQ(error.code, testCase.expected) << testCase.stderrText;
        // The raw text is always preserved: the operation log shows it verbatim,
        // and a summary alone would make bug reports unactionable.
        EXPECT_EQ(error.detail, testCase.stderrText);
        EXPECT_FALSE(error.message.empty());
        EXPECT_EQ(error.exitCode, 128);
    }
}

TEST(GitError, FallsBackWithoutLosingStderr) {
    const GitError error = classifyGitStderr("something entirely unexpected", 1);
    EXPECT_EQ(error.code, GitError::Code::ProcessFailed);
    EXPECT_EQ(error.detail, "something entirely unexpected");
}

// --- Result ----------------------------------------------------------------

TEST(Result, CarriesValuesAndErrors) {
    GitResult<int> ok = 42;
    ASSERT_TRUE(ok);
    EXPECT_EQ(*ok, 42);

    GitResult<int> bad = fail(GitError::Code::NotFound, "missing");
    ASSERT_FALSE(bad);
    EXPECT_EQ(bad.error().code, GitError::Code::NotFound);
    EXPECT_EQ(bad.valueOr(7), 7);

    GitResult<void> voidOk;
    EXPECT_TRUE(voidOk);
    GitResult<void> voidBad = fail(GitError::Code::Cancelled, "stopped");
    ASSERT_FALSE(voidBad);
    EXPECT_EQ(voidBad.error().code, GitError::Code::Cancelled);
}

// --- cancellation ----------------------------------------------------------

TEST(CancellationToken, FiresCallbacksExactlyOnce) {
    CancellationSource source;
    CancellationToken token = source.token();
    EXPECT_FALSE(token.isCancelled());

    std::atomic_int calls{0};
    token.onCancel([&calls] { ++calls; });

    source.cancel();
    source.cancel();  // Idempotent.

    EXPECT_TRUE(token.isCancelled());
    EXPECT_EQ(calls.load(), 1);
}

TEST(CancellationToken, RunsCallbackImmediatelyIfAlreadyCancelled) {
    // Without this, a callback registered just after cancellation would never
    // run, leaving a child process alive after the user pressed Cancel.
    CancellationSource source;
    source.cancel();

    std::atomic_bool ran{false};
    source.token().onCancel([&ran] { ran = true; });
    EXPECT_TRUE(ran.load());
}

// --- thread pool -----------------------------------------------------------

TEST(ThreadPool, RunsAllQueuedWork) {
    ThreadPool pool("test", 4);
    std::atomic_int total{0};
    for (int i = 0; i < 500; ++i) {
        pool.post([&total] { ++total; });
    }
    pool.drain();
    EXPECT_EQ(total.load(), 500);
}

TEST(ThreadPool, SurvivesAThrowingTask) {
    // A worker that lets an exception escape would otherwise terminate the whole
    // application while the user is only browsing history.
    ThreadPool pool("test", 2);
    std::atomic_int completed{0};

    pool.post([] { throw std::runtime_error("boom"); });
    pool.post([&completed] { ++completed; });
    pool.drain();

    EXPECT_EQ(completed.load(), 1);
}

TEST(ThreadPool, DefaultSizeLeavesRoomForTheUiThread) {
    const std::size_t size = ThreadPool::defaultThreadCount();
    EXPECT_GE(size, 2u);
    EXPECT_LE(size, 6u);
}

// --- debouncer -------------------------------------------------------------

TEST(Debouncer, WaitsForTheQuietPeriod) {
    Debouncer debouncer(std::chrono::milliseconds(100));
    const auto start = Debouncer::Clock::now();

    debouncer.notifyEvent(start);
    EXPECT_FALSE(debouncer.shouldFire(start));
    EXPECT_FALSE(debouncer.shouldFire(start + std::chrono::milliseconds(50)));
    EXPECT_TRUE(debouncer.shouldFire(start + std::chrono::milliseconds(150)));
}

TEST(Debouncer, ABurstOfEventsProducesOneRun) {
    // A single checkout on a large tree emits thousands of events; each one must
    // not become a separate `git status`.
    Debouncer debouncer(std::chrono::milliseconds(100));
    const auto start = Debouncer::Clock::now();

    for (int i = 0; i < 1000; ++i) {
        debouncer.notifyEvent(start + std::chrono::milliseconds(i / 20));
    }
    EXPECT_TRUE(debouncer.shouldFire(start + std::chrono::milliseconds(500)));
    EXPECT_FALSE(debouncer.shouldFire(start + std::chrono::milliseconds(600)))
        << "only one run should start per burst";
}

TEST(Debouncer, CoalescesEventsArrivingMidRun) {
    Debouncer debouncer(std::chrono::milliseconds(10));
    const auto start = Debouncer::Clock::now();

    debouncer.notifyEvent(start);
    ASSERT_TRUE(debouncer.shouldFire(start + std::chrono::milliseconds(20)));
    EXPECT_TRUE(debouncer.isRunning());

    // Events during the run set a dirty bit rather than queueing more runs.
    debouncer.notifyEvent(start + std::chrono::milliseconds(25));
    EXPECT_FALSE(debouncer.shouldFire(start + std::chrono::milliseconds(30)));

    EXPECT_TRUE(debouncer.finish()) << "exactly one more run should follow";
    EXPECT_TRUE(debouncer.shouldFire(start + std::chrono::milliseconds(40)));
    EXPECT_FALSE(debouncer.finish()) << "and then no more";
}

// --- git version detection -------------------------------------------------

TEST(GitVersion, ParsesVendorSuffixedVersions) {
    EXPECT_EQ(GitVersion::parse("git version 2.43.0").minor, 43);
    EXPECT_EQ(GitVersion::parse("git version 2.39.3 (Apple Git-146)").patch, 3);
    EXPECT_EQ(GitVersion::parse("git version 2.45.1.windows.1").minor, 45);

    const GitVersion version = GitVersion::parse("git version 2.30.2");
    EXPECT_TRUE(version >= GitInstallation::minimumSupported());
    EXPECT_FALSE(GitVersion::parse("git version 2.29.0") >= GitInstallation::minimumSupported());
}

TEST(GitInstallation, WarnsAboutMissingCapabilities) {
    // Because the backend is CLI-only, the user's git version is a hard feature
    // boundary. Surfacing it beats letting commands fail mysteriously later.
    GitInstallation old;
    old.executable = "/usr/bin/git";
    old.version = {2, 31, 0};
    EXPECT_TRUE(old.isUsable());
    EXPECT_FALSE(old.warnings().empty());

    GitInstallation modern;
    modern.executable = "/usr/bin/git";
    modern.version = {2, 45, 0};
    modern.capabilities.fsMonitor = true;
    modern.capabilities.mergeTreeWriteTree = true;
    modern.capabilities.changedPathBloom = true;
    EXPECT_TRUE(modern.warnings().empty());
}

// --- rev-list parsing ------------------------------------------------------

TEST(HistoryProvider, ParsesTimestampParentsAndOid) {
    const auto record = HistoryProvider::parseRevListLine(
        "1699999999 0123456789abcdef0123456789abcdef01234567 "
        "1111111111111111111111111111111111111111 "
        "2222222222222222222222222222222222222222");

    ASSERT_TRUE(record.valid);
    EXPECT_EQ(record.commitTime, 1699999999u);
    EXPECT_EQ(record.oid.hex(), "0123456789abcdef0123456789abcdef01234567");
    ASSERT_EQ(record.parents.size(), 2u);
    EXPECT_EQ(record.parents[0].hex(), std::string(40, '1'));
}

TEST(HistoryProvider, ParsesARootCommitWithNoParents) {
    const auto record = HistoryProvider::parseRevListLine("1000000000 " + std::string(40, 'a'));
    ASSERT_TRUE(record.valid);
    EXPECT_TRUE(record.parents.empty());
}

TEST(HistoryProvider, RejectsMalformedRecordsWithoutThrowing) {
    // Malformed rows are skipped, not fatal: one unparseable record must not
    // abandon the entire history walk.
    EXPECT_FALSE(HistoryProvider::parseRevListLine("").valid);
    EXPECT_FALSE(HistoryProvider::parseRevListLine("not-a-number abc").valid);
    EXPECT_FALSE(HistoryProvider::parseRevListLine("1699999999 tooshort").valid);
    EXPECT_FALSE(HistoryProvider::parseRevListLine("1699999999").valid);
}

TEST(HistoryQuery, UsesTopoOrderAndSeedsTipsBeforeAll) {
    HistoryQuery query;
    query.includeRefs = {"refs/heads/main"};
    const auto args = query.toRevListArgs();

    ASSERT_FALSE(args.empty());
    EXPECT_EQ(args[0], "rev-list");
    EXPECT_NE(std::find(args.begin(), args.end(), "--topo-order"), args.end())
        << "date order would interleave branches and break lane continuity";
    EXPECT_NE(std::find(args.begin(), args.end(), "--parents"), args.end());
    EXPECT_NE(std::find(args.begin(), args.end(), "--timestamp"), args.end());

    // The explicit tip must precede --all: the graph builder gives lane 0 to the
    // first tip it sees, which is how the trunk stays leftmost.
    const auto tipAt = std::find(args.begin(), args.end(), "refs/heads/main");
    const auto allAt = std::find(args.begin(), args.end(), "--all");
    ASSERT_NE(tipAt, args.end());
    ASSERT_NE(allAt, args.end());
    EXPECT_LT(tipAt - args.begin(), allAt - args.begin());
}

TEST(HistoryQuery, PushesFilteringDownIntoGit) {
    HistoryQuery query;
    query.author = "someone";
    query.grep = "fix";
    query.pathFilter = "src/main.cpp";
    query.maxCount = 500;

    const auto args = query.toRevListArgs();
    EXPECT_NE(std::find(args.begin(), args.end(), "--author=someone"), args.end());
    EXPECT_NE(std::find(args.begin(), args.end(), "--grep=fix"), args.end());
    EXPECT_NE(std::find(args.begin(), args.end(), "--max-count=500"), args.end());
    // Path filtering must come after a "--" separator or a path that looks like a
    // ref would be misread.
    const auto separator = std::find(args.begin(), args.end(), "--");
    const auto path = std::find(args.begin(), args.end(), "src/main.cpp");
    ASSERT_NE(separator, args.end());
    ASSERT_NE(path, args.end());
    EXPECT_LT(separator - args.begin(), path - args.begin());
}

// --- commit object parsing -------------------------------------------------

TEST(CommitMeta, ParsesARawCommitObject) {
    const std::string raw =
        "tree 1111111111111111111111111111111111111111\n"
        "parent 2222222222222222222222222222222222222222\n"
        "parent 3333333333333333333333333333333333333333\n"
        "author Ada Lovelace <ada@example.invalid> 1699999999 +0200\n"
        "committer Ada Lovelace <ada@example.invalid> 1700000000 -0700\n"
        "\n"
        "Fix the thing\n"
        "\n"
        "A longer explanation.\n";

    const ObjectId oid = ObjectId::fromHex(std::string(40, 'f'));
    const CommitMeta meta = CommitMeta::parseRawCommit(oid, raw);

    EXPECT_EQ(meta.tree.hex(), std::string(40, '1'));
    ASSERT_EQ(meta.parents.size(), 2u);
    EXPECT_EQ(meta.author.name, "Ada Lovelace");
    EXPECT_EQ(meta.author.email, "ada@example.invalid");
    EXPECT_EQ(meta.author.when, 1699999999);
    EXPECT_EQ(meta.author.tzOffsetMinutes, 120);
    EXPECT_EQ(meta.committer.tzOffsetMinutes, -7 * 60);
    EXPECT_EQ(meta.subject, "Fix the thing");
    EXPECT_EQ(meta.body, "A longer explanation.");
}

TEST(CommitMeta, SkipsUnknownAndMultiLineHeaders) {
    // gpgsig spans many continuation lines. Treating an unfamiliar header as an
    // error would break history browsing on plenty of real repositories.
    const std::string raw =
        "tree 1111111111111111111111111111111111111111\n"
        "author A <a@example.invalid> 1 +0000\n"
        "committer A <a@example.invalid> 1 +0000\n"
        "gpgsig -----BEGIN PGP SIGNATURE-----\n"
        " \n"
        " iQEcBAABCgAGBQJ...\n"
        " -----END PGP SIGNATURE-----\n"
        "encoding ISO-8859-1\n"
        "mergetag object 4444444444444444444444444444444444444444\n"
        " type commit\n"
        "\n"
        "Signed commit\n";

    const CommitMeta meta =
        CommitMeta::parseRawCommit(ObjectId::fromHex(std::string(40, 'a')), raw);
    EXPECT_TRUE(meta.signedCommit);
    EXPECT_EQ(meta.subject, "Signed commit");
    EXPECT_EQ(meta.author.name, "A");
}

TEST(Signature, HandlesNamesContainingAngleBrackets) {
    // Scanning for the email from the left would truncate this name.
    const Signature signature = parseSignature("Weird <Name> <real@example.invalid> 100 +0000");
    EXPECT_EQ(signature.email, "real@example.invalid");
    EXPECT_EQ(signature.name, "Weird <Name>");
    EXPECT_EQ(signature.when, 100);
}

// --- ref name validation ---------------------------------------------------

TEST(RefStore, ValidatesBranchNamesBeforeSpawningGit) {
    EXPECT_TRUE(RefStore::isValidBranchName("feature/thing"));
    EXPECT_TRUE(RefStore::isValidBranchName("release-1.2"));

    EXPECT_FALSE(RefStore::isValidBranchName(""));
    EXPECT_FALSE(RefStore::isValidBranchName(".hidden"));
    EXPECT_FALSE(RefStore::isValidBranchName("trailing/"));
    EXPECT_FALSE(RefStore::isValidBranchName("with space"));
    EXPECT_FALSE(RefStore::isValidBranchName("a..b"));
    EXPECT_FALSE(RefStore::isValidBranchName("caret^"));
    EXPECT_FALSE(RefStore::isValidBranchName("colon:name"));
    EXPECT_FALSE(RefStore::isValidBranchName("star*"));
    EXPECT_FALSE(RefStore::isValidBranchName("thing.lock"));
    EXPECT_FALSE(RefStore::isValidBranchName("at@{brace"));
}

// --- repository paths ------------------------------------------------------

TEST(RepoPaths, DistinguishesLinkedWorktreesFromNormalCheckouts) {
    // Getting this wrong means reading another worktree's HEAD, so the split
    // between per-worktree and shared state is asserted directly.
    const RepoPaths normal("/repo", "/repo/.git", "/repo/.git");
    EXPECT_FALSE(normal.isLinkedWorktree());
    EXPECT_FALSE(normal.isBare());
    EXPECT_EQ(normal.commandDir(), std::filesystem::path("/repo"));
    EXPECT_EQ(normal.displayName(), "repo");

    const RepoPaths worktree("/wt", "/repo/.git/worktrees/wt", "/repo/.git");
    EXPECT_TRUE(worktree.isLinkedWorktree());
    // HEAD and index are private to the worktree...
    EXPECT_EQ(worktree.headFile(), std::filesystem::path("/repo/.git/worktrees/wt/HEAD"));
    EXPECT_EQ(worktree.indexFile(), std::filesystem::path("/repo/.git/worktrees/wt/index"));
    // ...while objects and packed-refs are shared.
    EXPECT_EQ(worktree.objectsDir(), std::filesystem::path("/repo/.git/objects"));
    EXPECT_EQ(worktree.packedRefsFile(), std::filesystem::path("/repo/.git/packed-refs"));

    const RepoPaths bare({}, "/mirror.git", "/mirror.git");
    EXPECT_TRUE(bare.isBare());
    EXPECT_EQ(bare.commandDir(), std::filesystem::path("/mirror.git"));
}

TEST(RepoPaths, DerivesADisplayNameFromTheParentOfDotGit) {
    const RepoPaths paths("", "/some/project/.git", "/some/project/.git");
    EXPECT_EQ(paths.displayName(), "project");
}

// --- M3: askpass handshake --------------------------------------------------

TEST(Askpass, WireAddsTheAskpassEnvironmentOverrides) {
    GitCommand command;
    askpass::wire(command, "/tmp/gbm-askpass-test-dir");

    auto find = [&command](const std::string& key) -> std::optional<std::string> {
        for (const auto& [k, v] : command.envOverrides) {
            if (k == key) {
                return v;
            }
        }
        return std::nullopt;
    };

    EXPECT_TRUE(find("GIT_ASKPASS").has_value());
    EXPECT_TRUE(find("SSH_ASKPASS").has_value());
    EXPECT_EQ(find("GBM_ASKPASS_MODE"), "1");
    EXPECT_EQ(find("GBM_ASKPASS_DIR"), "/tmp/gbm-askpass-test-dir");
}

TEST(Askpass, WireIsANoOpWithAnEmptyDirectory) {
    GitCommand command;
    askpass::wire(command, {});
    EXPECT_TRUE(command.envOverrides.empty())
        << "a command with no askpass directory must behave exactly as it did before M3";
}

TEST(Askpass, ClientWritesTheRequestAndFailsPromptlyOnCancel) {
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());

    std::thread responder([&dir] {
        // Give the client time to write its request before reacting to it.
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        std::ofstream cancel(dir / "cancel");
        cancel << "x";
    });

    const int exitCode = askpass::runClientForDir(dir, "Password for 'https://example.invalid': ");
    responder.join();

    EXPECT_EQ(exitCode, 1);

    std::ifstream request(dir / "request");
    std::string contents((std::istreambuf_iterator<char>(request)),
                         std::istreambuf_iterator<char>());
    EXPECT_EQ(contents, "Password for 'https://example.invalid': ");

    std::filesystem::remove_all(dir);
}

TEST(Askpass, ClientPrintsTheAnswerOnceAResponseArrives) {
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());

    std::thread responder([&dir] {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        std::ofstream response(dir / "response", std::ios::binary);
        response << "s3cret";
    });

    const int exitCode = askpass::runClientForDir(dir, "Password: ");
    responder.join();

    EXPECT_EQ(exitCode, 0);
    // The response file is consumed, matching a real one-shot credential prompt.
    EXPECT_FALSE(std::filesystem::exists(dir / "response"));

    std::filesystem::remove_all(dir);
}

}  // namespace
}  // namespace gbm
