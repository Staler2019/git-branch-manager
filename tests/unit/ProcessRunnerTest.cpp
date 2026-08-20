// Tests for the process seam.
//
// The fake runner exists so the failure modes a live repository will not produce
// on demand become ordinary test cases. These are the ones that actually bite:
// output truncated mid-record, a child killed while streaming, non-UTF-8 bytes in
// a path, and a non-zero exit with empty stderr.
#include "core/git/HistoryProvider.h"
#include "core/git/RefStore.h"
#include "core/git/UnifiedDiffParser.h"
#include "support/FakeProcessRunner.h"

#include <gtest/gtest.h>
#include <string>
#include <vector>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

RepoPaths testPaths() {
    return RepoPaths("/repo", "/repo/.git", "/repo/.git");
}

TEST(FakeProcessRunner, MatchesRulesOnArgvAndRecordsInvocations) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.out = "hello";
    runner.whenArgsContain({"rev-parse"}, response);

    GitCommand command(std::filesystem::path("/repo"), {"rev-parse", "HEAD"});
    auto result = runner.run(command, CancellationToken{});

    ASSERT_TRUE(result);
    EXPECT_EQ(result->out, "hello");
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0)[0], "rev-parse");
}

TEST(FakeProcessRunner, PropagatesClassifiedFailures) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.exitCode = 128;
    response.err = "error: Your local changes would be overwritten by checkout";
    runner.whenArgsContain({"switch"}, response);

    GitCommand command(std::filesystem::path("/repo"), {"switch", "other"});
    auto result = runner.run(command, CancellationToken{});

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::DirtyWorkTree);
    EXPECT_EQ(result.error().exitCode, 128);
    EXPECT_FALSE(result.error().argv.empty());
}

TEST(FakeProcessRunner, HonoursAnAlreadyCancelledToken) {
    FakeProcessRunner runner;
    CancellationSource source;
    source.cancel();

    GitCommand command(std::filesystem::path("/repo"), {"status"});
    auto result = runner.run(command, source.token());

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::Cancelled);
}

TEST(FakeProcessRunner, SplitsNulSeparatedOutput) {
    // `-z` output is the only correct way to read paths, so NUL splitting has to
    // be right: a path containing a newline would otherwise split into two.
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.out = std::string("first\nwith newline\0second\0", 26);
    runner.setDefaultResponse(response);

    std::vector<std::string> records;
    GitCommand command(std::filesystem::path("/repo"), {"status", "-z"});
    auto result = runner.streamSeparated(
        command,
        IProcessRunner::Separator::Nul,
        [&records](std::string_view record) {
            records.emplace_back(record);
            return true;
        },
        nullptr,
        CancellationToken{});

    ASSERT_TRUE(result);
    ASSERT_EQ(records.size(), 2u);
    EXPECT_EQ(records[0], "first\nwith newline");
    EXPECT_EQ(records[1], "second");
}

TEST(FakeProcessRunner, StopsStreamingWhenTheSinkAsksTo) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    for (int i = 0; i < 100; ++i) {
        response.out += "line" + std::to_string(i) + "\n";
    }
    runner.setDefaultResponse(response);

    int seen = 0;
    GitCommand command(std::filesystem::path("/repo"), {"log"});
    auto result = runner.stream(
        command,
        [&seen](std::string_view) {
            ++seen;
            return seen < 5;  // Ask to stop after five records.
        },
        nullptr,
        CancellationToken{});

    ASSERT_TRUE(result);
    EXPECT_EQ(seen, 5);
}

TEST(HistoryProvider, StreamsChunksAndBuildsAGraph) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    // A short linear history, newest first, as rev-list emits it.
    response.out = "1000 " + std::string(40, '1') + " " + std::string(40, '2') + "\n" + "999 " +
                   std::string(40, '2') + " " + std::string(40, '3') + "\n" + "998 " +
                   std::string(40, '3') + "\n";
    runner.whenArgsContain({"rev-list"}, response);

    HistoryProvider provider(runner, testPaths());
    HistoryQuery query;

    std::vector<GraphSnapshotPtr> chunks;
    auto final = provider.walk(
        query,
        [&chunks](GraphSnapshotPtr chunk) { chunks.push_back(std::move(chunk)); },
        CancellationToken{});

    ASSERT_TRUE(final) << final.error().message;
    EXPECT_EQ((*final)->rowCount(), 3u);
    EXPECT_TRUE((*final)->complete);
    ASSERT_FALSE(chunks.empty());
    EXPECT_TRUE(chunks.back()->complete);

    // A linear history must be one straight column even through the streaming path.
    for (const RowMeta& row : (*final)->rows) {
        EXPECT_EQ(row.lane, 0);
    }
}

TEST(HistoryProvider, PublishesChunksOnAGeometricSchedule) {
    // Regression guard for a quadratic walk.
    //
    // Publishing a snapshot copies every row built so far, so a fixed-interval
    // timer is self-defeating: once one copy takes longer than the interval, every
    // row triggers another publish. Measured on a 200k-commit repository, that was
    // 13,608 chunks and 470 seconds versus 12 chunks and 0.6 seconds. The schedule
    // must stay logarithmic in the number of rows.
    constexpr std::size_t kRows = 20000;

    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.out.reserve(kRows * 100);
    for (std::size_t i = 1; i <= kRows; ++i) {
        char oid[41];
        std::snprintf(oid, sizeof(oid), "%040zu", i);
        char parent[41];
        std::snprintf(parent, sizeof(parent), "%040zu", i + 1);
        response.out += std::to_string(1000000 - i);
        response.out += " ";
        response.out += oid;
        if (i < kRows) {
            response.out += " ";
            response.out += parent;
        }
        response.out += "\n";
    }
    runner.whenArgsContain({"rev-list"}, response);

    std::size_t chunks = 0;
    HistoryProvider provider(runner, testPaths());
    auto result = provider.walk(
        HistoryQuery{}, [&chunks](GraphSnapshotPtr) { ++chunks; }, CancellationToken{});

    ASSERT_TRUE(result);
    EXPECT_EQ((*result)->rowCount(), kRows);

    // log2(20000 / 256) is about 6, plus the final publish. A generous ceiling
    // still catches any return to per-row or per-interval publishing.
    EXPECT_LE(chunks, 20u) << "chunk schedule is not geometric: " << chunks << " publishes for "
                           << kRows << " rows";
    EXPECT_GE(chunks, 2u) << "progressive painting requires more than a single final chunk";
}

TEST(HistoryProvider, SkipsMalformedRecordsRatherThanAbandoningTheWalk) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    response.out = "1000 " + std::string(40, '1') +
                   "\n"
                   "this line is garbage\n"
                   "999 " +
                   std::string(40, '2') + "\n";
    runner.whenArgsContain({"rev-list"}, response);

    HistoryProvider provider(runner, testPaths());
    auto result = provider.walk(HistoryQuery{}, nullptr, CancellationToken{});

    ASSERT_TRUE(result);
    EXPECT_EQ((*result)->rowCount(), 2u) << "good records must still be kept";
}

TEST(HistoryProvider, SurvivesAChildKilledMidStream) {
    // Simulates the process dying part-way: rows already delivered stay valid, and
    // the caller gets a partial-but-coherent snapshot instead of a crash.
    FakeProcessRunner runner;
    FakeProcessRunner::Response response;
    for (int i = 1; i <= 50; ++i) {
        char oid[41];
        std::snprintf(oid, sizeof(oid), "%040d", i);
        char parent[41];
        std::snprintf(parent, sizeof(parent), "%040d", i + 1);
        response.out += std::to_string(2000 - i) + " " + oid + " " + parent + "\n";
    }
    response.truncateAfterRecords = 10;
    runner.whenArgsContain({"rev-list"}, response);

    HistoryProvider provider(runner, testPaths());
    auto result = provider.walk(HistoryQuery{}, nullptr, CancellationToken{});

    ASSERT_TRUE(result);
    EXPECT_EQ((*result)->rowCount(), 10u);
    // The last row's parent was never walked, so it must be a boundary stub
    // rather than pointing at nothing.
    EXPECT_TRUE((*result)->rows[9].isBoundary());
}

TEST(RefStore, ParsesForEachRefOutputIncludingTrackingInfo) {
    FakeProcessRunner runner;

    // readHead() resolves HEAD's oid and its symbolic name in one rev-parse,
    // so the scripted reply is both lines: "<oid>\n<symbolic full name>".
    FakeProcessRunner::Response revParse;
    revParse.out = std::string(40, 'a') + "\nrefs/heads/main";
    runner.whenArgsContain({"rev-parse"}, revParse);

    // Fields are separated by the ASCII unit separator, which cannot appear in a
    // ref name, so no escaping is needed.
    const char sep = '\x1f';
    FakeProcessRunner::Response refs;
    refs.out = std::string("refs/heads/main") + sep + "commit" + sep + std::string(40, 'a') + sep +
               "" + sep + "refs/remotes/origin/main" + sep + "[ahead 2, behind 3]" + sep + "*" +
               sep + "" + "\n" + std::string("refs/tags/v1.0") + sep + "tag" + sep +
               std::string(40, 'b') + sep + std::string(40, 'c') + sep + "" + sep + "" + sep + " " +
               sep + "" + "\n";
    runner.whenArgsContain({"for-each-ref"}, refs);

    RefStore store(runner, testPaths());
    auto snapshot = store.load(CancellationToken{});
    ASSERT_TRUE(snapshot) << snapshot.error().message;

    EXPECT_EQ((*snapshot)->head.kind, HeadInfo::Kind::Branch);
    EXPECT_EQ((*snapshot)->head.branchName, "main");
    ASSERT_EQ((*snapshot)->refs.size(), 2u);

    const auto branches = (*snapshot)->ofKind(RefKind::LocalBranch);
    ASSERT_EQ(branches.size(), 1u);
    EXPECT_EQ(branches[0]->shortName, "main");
    EXPECT_EQ(branches[0]->ahead, 2);
    EXPECT_EQ(branches[0]->behind, 3);
    EXPECT_TRUE(branches[0]->isHead);

    // An annotated tag must resolve to its peeled commit, or the graph would try
    // to decorate a row that does not exist.
    const auto tags = (*snapshot)->ofKind(RefKind::Tag);
    ASSERT_EQ(tags.size(), 1u);
    EXPECT_EQ(tags[0]->target.hex(), std::string(40, 'c'));
    EXPECT_EQ(tags[0]->tagObject.hex(), std::string(40, 'b'));
}

TEST(RefStore, TreatsAnUnbornHeadAsANormalState) {
    // A freshly initialised repository has no commits. It must still open.
    FakeProcessRunner runner;
    FakeProcessRunner::Response symbolic;
    symbolic.out = "refs/heads/main";
    runner.whenArgsContain({"symbolic-ref"}, symbolic);

    FakeProcessRunner::Response revParse;
    revParse.exitCode = 1;  // HEAD does not resolve: no commits yet
    runner.whenArgsContain({"rev-parse"}, revParse);
    runner.whenArgsContain({"for-each-ref"}, FakeProcessRunner::Response{});

    RefStore store(runner, testPaths());
    auto snapshot = store.load(CancellationToken{});

    ASSERT_TRUE(snapshot);
    EXPECT_EQ((*snapshot)->head.kind, HeadInfo::Kind::Unborn);
    EXPECT_TRUE((*snapshot)->refs.empty());
}

TEST(RefStore, TripsTheRefCountGuardOnAHugeRefSet) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response revParse;
    revParse.out = std::string(40, 'a');  // an oid with no symbolic name: detached
    runner.whenArgsContain({"rev-parse"}, revParse);

    const char sep = '\x1f';
    FakeProcessRunner::Response refs;
    for (std::size_t i = 0; i <= RefStore::kRefCountGuard + 10; ++i) {
        refs.out += "refs/heads/b" + std::to_string(i) + sep + "commit" + sep +
                    std::string(40, 'a') + sep + "" + sep + "" + sep + "" + sep + " " + sep + "" +
                    "\n";
    }
    runner.whenArgsContain({"for-each-ref"}, refs);

    RefStore store(runner, testPaths());
    auto snapshot = store.load(CancellationToken{});
    ASSERT_TRUE(snapshot);

    // The guard exists so a decade-old repository with thousands of stale
    // branches does not make the graph unusable; it must be reported, not silent.
    EXPECT_TRUE((*snapshot)->refCountGuardTripped);
    EXPECT_GT((*snapshot)->totalRefCount, RefStore::kRefCountGuard);
}

TEST(RefStore, SeedsHistoryWithHeadBeforeTrunk) {
    RefSnapshot snapshot;
    snapshot.head.kind = HeadInfo::Kind::Branch;
    snapshot.head.fullRef = "refs/heads/feature";

    RefInfo feature;
    feature.fullName = "refs/heads/feature";
    feature.kind = RefKind::LocalBranch;
    feature.isHead = true;
    feature.upstream = "refs/remotes/origin/feature";

    RefInfo main;
    main.fullName = "refs/heads/main";
    main.kind = RefKind::LocalBranch;

    // The upstream ref itself must be present for historySeedRefs to trust
    // it -- see RefStore::refExists.
    RefInfo upstream;
    upstream.fullName = "refs/remotes/origin/feature";
    upstream.kind = RefKind::RemoteBranch;

    snapshot.refs = {feature, main, upstream};

    const auto seeds = RefStore::historySeedRefs(snapshot);
    ASSERT_GE(seeds.size(), 3u);
    EXPECT_EQ(seeds[0], "refs/heads/feature") << "HEAD must be seeded first";
    EXPECT_NE(std::find(seeds.begin(), seeds.end(), "refs/remotes/origin/feature"), seeds.end());
    EXPECT_NE(std::find(seeds.begin(), seeds.end(), "refs/heads/main"), seeds.end());
}

TEST(RefStore, ExcludesAGoneUpstreamFromHistorySeeds) {
    // `branch.<name>.remote`/`.merge` config still names an upstream after
    // its remote-tracking ref is pruned (e.g. `git remote remove origin`, or
    // the branch was deleted upstream and pruned locally) -- git reports
    // that as `[gone]` in %(upstream:track), but still hands back the dead
    // name in %(upstream). Seeding rev-list with it aborts the entire walk
    // with "unknown revision", so it must never reach historySeedRefs'
    // output even though `upstream` is non-empty.
    RefSnapshot snapshot;
    snapshot.head.kind = HeadInfo::Kind::Branch;
    snapshot.head.fullRef = "refs/heads/feature";

    RefInfo feature;
    feature.fullName = "refs/heads/feature";
    feature.kind = RefKind::LocalBranch;
    feature.isHead = true;
    feature.upstream = "refs/remotes/origin/feature";
    feature.hasTrackingInfo = true;
    feature.isGone = true;
    // Deliberately no "refs/remotes/origin/feature" entry in snapshot.refs --
    // that is exactly the pruned state being tested.

    snapshot.refs = {feature};

    const auto seeds = RefStore::historySeedRefs(snapshot);
    EXPECT_EQ(std::find(seeds.begin(), seeds.end(), "refs/remotes/origin/feature"), seeds.end());
    EXPECT_NE(std::find(seeds.begin(), seeds.end(), "refs/heads/feature"), seeds.end());
}

TEST(RefStore, ParsesGoneTrackFieldWithoutCountingAsAheadOrBehind) {
    FakeProcessRunner runner;
    // readHead() resolves HEAD's oid and its symbolic name in one rev-parse,
    // so the scripted reply is both lines: "<oid>\n<symbolic full name>".
    FakeProcessRunner::Response revParse;
    revParse.out = std::string(40, 'a') + "\nrefs/heads/feature";
    runner.whenArgsContain({"rev-parse"}, revParse);

    const char sep = '\x1f';
    FakeProcessRunner::Response refs;
    refs.out = std::string("refs/heads/feature") + sep + "commit" + sep + std::string(40, 'a') +
               sep + "" + sep + "refs/remotes/origin/feature" + sep + "[gone]" + sep + "*" + sep +
               "" + "\n";
    runner.whenArgsContain({"for-each-ref"}, refs);

    RefStore store(runner, testPaths());
    auto snapshot = store.load(CancellationToken{});
    ASSERT_TRUE(snapshot) << snapshot.error().message;

    ASSERT_EQ((*snapshot)->refs.size(), 1u);
    EXPECT_TRUE((*snapshot)->refs[0].isGone);
    EXPECT_TRUE((*snapshot)->refs[0].hasTrackingInfo);
    EXPECT_EQ((*snapshot)->refs[0].ahead, 0);
    EXPECT_EQ((*snapshot)->refs[0].behind, 0);
}

TEST(RefStore, LoadsEveryRefWithASingleForEachRefInvocation) {
    // A counted invariant, not a wall-clock one -- same reasoning as
    // HistoryProvider.PublishesChunksOnAGeometricSchedule above.
    //
    // Ahead/behind comes from %(upstream:track) inside the one for-each-ref
    // above on purpose (see RefStore::load). The obvious-looking alternative --
    // a `rev-list --count` per branch -- is one process per ref, which turns a
    // sub-second load on docs/PERFORMANCE.md's 3,798-ref repository into
    // minutes. Every parsed field would still be correct if someone did that,
    // so the process count is the only thing that can catch it.
    FakeProcessRunner runner;
    // readHead() resolves HEAD's oid and its symbolic name in one rev-parse,
    // so the scripted reply is both lines: "<oid>\n<symbolic full name>".
    FakeProcessRunner::Response revParse;
    revParse.out = std::string(40, 'a') + "\nrefs/heads/main";
    runner.whenArgsContain({"rev-parse"}, revParse);

    // Enough refs, each with tracking info, that a per-ref process would be
    // unmistakable in the invocation list rather than a rounding error.
    const char sep = '\x1f';
    FakeProcessRunner::Response refs;
    for (int i = 0; i < 200; ++i) {
        char oid[41];
        std::snprintf(oid, sizeof(oid), "%040d", i);
        const std::string name = "branch-" + std::to_string(i);
        refs.out += "refs/heads/" + name + sep + "commit" + sep + oid + sep + "" + sep +
                    "refs/remotes/origin/" + name + sep + "[ahead 1, behind 2]" + sep + "" + sep +
                    "" + "\n";
    }
    runner.whenArgsContain({"for-each-ref"}, refs);

    RefStore store(runner, testPaths());
    auto snapshot = store.load(CancellationToken{});
    ASSERT_TRUE(snapshot) << snapshot.error().message;
    ASSERT_EQ((*snapshot)->refs.size(), 200u);
    EXPECT_EQ((*snapshot)->ofKind(RefKind::LocalBranch).front()->ahead, 1);

    std::size_t forEachRefCalls = 0;
    for (std::size_t i = 0; i < runner.invocationCount(); ++i) {
        const std::vector<std::string> args = runner.invokedArgs(i);
        if (!args.empty() && args.front() == "for-each-ref") {
            ++forEachRefCalls;
        }
    }
    EXPECT_EQ(forEachRefCalls, 1u)
        << "one load() must cost exactly one for-each-ref, not one per ref";

    // Two processes in total: one rev-parse resolving HEAD's oid and symbolic
    // name together (readHead), then the single for-each-ref. This was three
    // until readHead() stopped issuing a separate symbolic-ref -- see
    // RefStoreHeadTest.cpp. Pinned so that adding "just one more quick git
    // call" to load() has to be a deliberate edit to this number.
    EXPECT_EQ(runner.invocationCount(), 2u);
}

}  // namespace
}  // namespace gbm
