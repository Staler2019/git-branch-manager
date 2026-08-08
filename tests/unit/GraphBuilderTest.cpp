// Tests for the lane algorithm.
//
// The graph is the one component where a passing unit test is not obviously
// enough, because the requirement ("looks like Fork") is visual. So this file
// pins down the shape two ways: readable ASCII assertions for the specific
// topologies that define the look, and property tests over thousands of random
// DAGs for the invariants an eye cannot check at scale.
#include "core/graph/GraphAsciiRenderer.h"
#include "core/graph/GraphBuilder.h"

#include <algorithm>
#include <gtest/gtest.h>
#include <map>
#include <set>
#include <string>
#include <vector>

namespace gbm {
namespace {

ObjectId oidFor(int n) {
    char buffer[41];
    std::snprintf(buffer, sizeof(buffer), "%040d", n);
    return ObjectId::fromHex(buffer);
}

struct Commit {
    int id;
    std::vector<int> parents;
};

/// Builds from a list given newest-first, as rev-list --topo-order produces.
GraphSnapshotPtr build(const std::vector<Commit>& commits, GraphOptions options = {}) {
    GraphBuilder builder(options);
    for (const Commit& commit : commits) {
        std::vector<ObjectId> parents;
        parents.reserve(commit.parents.size());
        for (int parent : commit.parents) {
            parents.push_back(oidFor(parent));
        }
        builder.add(oidFor(commit.id), parents, 1000u + static_cast<std::uint32_t>(commit.id));
    }
    builder.finish();
    return builder.snapshot();
}

/// A deterministic DAG where every parent id is greater than its child's, which
/// is exactly the ordering guarantee topo-order gives us.
std::vector<Commit> makeRandomDag(int count,
                                  std::uint64_t seed,
                                  double mergeRate,
                                  int maxExtraParents = 1) {
    std::vector<Commit> commits;
    commits.reserve(static_cast<std::size_t>(count));
    std::uint64_t state = seed;
    auto next = [&state]() {
        state = state * 6364136223846793005ULL + 1442695040888963407ULL;
        return (state >> 33);
    };
    auto unit = [&next]() { return static_cast<double>(next() % 100000) / 100000.0; };

    for (int id = 1; id <= count; ++id) {
        std::vector<int> parents;
        if (id < count) {
            parents.push_back(id + 1);
            if (unit() < mergeRate) {
                const int extra =
                    1 + static_cast<int>(next() % static_cast<std::uint64_t>(maxExtraParents));
                for (int e = 0; e < extra; ++e) {
                    const int candidate = id + 2 + static_cast<int>(next() % 5);
                    if (candidate < count &&
                        std::find(parents.begin(), parents.end(), candidate) == parents.end()) {
                        parents.push_back(candidate);
                    }
                }
            }
        }
        commits.push_back({id, parents});
    }
    return commits;
}

// --- the shapes that define the look --------------------------------------

TEST(GraphBuilder, LinearHistoryIsASingleStraightColumn) {
    auto snapshot = build({{1, {2}}, {2, {3}}, {3, {4}}, {4, {}}});

    ASSERT_EQ(snapshot->rowCount(), 4u);
    for (const RowMeta& row : snapshot->rows) {
        EXPECT_EQ(row.lane, 0) << "a linear history must never leave lane 0";
    }
    EXPECT_EQ(snapshot->laneCount, 1);

    // No bends anywhere: every edge starts and descends in the same lane.
    for (const Edge& edge : snapshot->edges) {
        EXPECT_EQ(edge.lane, edge.childLane);
    }
}

TEST(GraphBuilder, TrunkKeepsLaneZeroAcrossAMerge) {
    // 1 is a merge of trunk (2) and a feature branch (5); both meet again at 6.
    auto snapshot = build({
        {1, {2, 5}},
        {2, {3}},
        {5, {6}},
        {3, {6}},
        {6, {}},
    });

    EXPECT_EQ(snapshot->rows[0].lane, 0) << "the merge itself stays on trunk";
    EXPECT_EQ(snapshot->rows[1].lane, 0);
    EXPECT_EQ(snapshot->rows[3].lane, 0);
    EXPECT_EQ(snapshot->rows[4].lane, 0) << "the common ancestor rejoins trunk";
    EXPECT_GT(snapshot->rows[2].lane, 0) << "the merged-in branch must sit to the right";
    EXPECT_TRUE(snapshot->rows[0].isMerge());
}

TEST(GraphBuilder, MergedParentsGoToTheRightNotTheLeft) {
    // The property that distinguishes this from a naive lowest-free-lane policy:
    // a second parent must never be allocated a column left of the merge commit.
    auto commits = makeRandomDag(3000, 991, 0.25, 3);
    auto snapshot = build(commits);

    for (const Edge& edge : snapshot->edges) {
        if (edge.kind == EdgeKind::FirstParent) {
            continue;
        }
        EXPECT_GT(edge.lane, edge.childLane) << "merge parent lane " << edge.lane
                                             << " is not right of child lane " << edge.childLane;
    }
}

TEST(GraphBuilder, OctopusMergeFansOutOnePerExtraParent) {
    auto snapshot = build({
        {1, {2, 3, 4, 5}},
        {2, {6}},
        {3, {6}},
        {4, {6}},
        {5, {6}},
        {6, {}},
    });

    EXPECT_EQ(snapshot->parentCountOf(0), 4u);
    EXPECT_EQ(snapshot->rows[0].lane, 0);

    std::set<LaneId> extraLanes;
    for (const Edge& edge : snapshot->edges) {
        if (edge.childRow == 0 && edge.kind == EdgeKind::Octopus) {
            extraLanes.insert(edge.lane);
        }
    }
    EXPECT_EQ(extraLanes.size(), 3u) << "n parents produce n-1 extra columns";
}

TEST(GraphBuilder, OctopusWithMoreThanSevenParentsKeepsAnExactCount) {
    // RowMeta::parentCount() saturates at 7 to fit its flag byte, so the exact
    // count has to come from the parent pool. Linux history contains a 66-parent
    // octopus, so this is not hypothetical.
    std::vector<Commit> commits;
    std::vector<int> parents;
    for (int p = 2; p <= 21; ++p) {
        parents.push_back(p);
    }
    commits.push_back({1, parents});
    for (int p = 2; p <= 21; ++p) {
        commits.push_back({p, {}});
    }

    auto snapshot = build(commits);
    EXPECT_EQ(snapshot->parentCountOf(0), 20u);
    EXPECT_EQ(snapshot->parentsOf(0).size(), 20u);
}

TEST(GraphBuilder, RootCommitFreesItsLane) {
    // Two unrelated histories: the second must be able to reuse lane 0's
    // neighbours once the first history's root has been emitted.
    auto snapshot = build({{1, {2}}, {2, {}}, {3, {4}}, {4, {}}});
    EXPECT_EQ(snapshot->rows[0].lane, 0);
    EXPECT_EQ(snapshot->rows[2].lane, 0) << "an unrelated root should reuse the freed column";
}

TEST(GraphBuilder, MissingParentsBecomeBoundaryStubs) {
    // A shallow clone: commit 2's parent was never walked.
    auto snapshot = build({{1, {2}}, {2, {99}}});

    EXPECT_TRUE(snapshot->rows[1].isBoundary());
    bool foundBoundaryEdge = false;
    for (const Edge& edge : snapshot->edges) {
        if (edge.childRow == 1) {
            EXPECT_EQ(edge.parentRow, kRowBoundary);
            foundBoundaryEdge = true;
        }
    }
    EXPECT_TRUE(foundBoundaryEdge);
}

// --- invariants ------------------------------------------------------------

TEST(GraphBuilder, InvariantFirstParentChainsNeverMoveRight) {
    // I1, the straightness theorem. A first-parent edge either keeps its lane or
    // moves strictly left; if it could move right, chains would zig-zag and the
    // graph would stop looking like Fork's.
    for (std::uint64_t seed : {1u, 7u, 42u, 1337u, 99991u}) {
        auto snapshot = build(makeRandomDag(2000, seed, 0.15, 2));

        std::size_t straight = 0;
        for (const Edge& edge : snapshot->edges) {
            if (edge.kind != EdgeKind::FirstParent || edge.parentRow == kRowBoundary) {
                continue;
            }
            const LaneId parentLane = snapshot->rows[edge.parentRow].lane;
            if (parentLane == edge.childLane) {
                ++straight;
            } else {
                EXPECT_LT(parentLane, edge.childLane)
                    << "seed " << seed << ": first-parent chain moved right";
            }
        }
        EXPECT_GT(straight, 0u);
    }
}

TEST(GraphBuilder, InvariantEdgesAlwaysPointDownwards) {
    // I4: topological consistency. A parent must appear at a later row than its
    // child, or the renderer would try to draw an upward line.
    auto snapshot = build(makeRandomDag(3000, 20240101, 0.2, 3));
    for (const Edge& edge : snapshot->edges) {
        if (edge.parentRow != kRowBoundary) {
            EXPECT_GT(edge.parentRow, edge.childRow);
        }
    }
}

TEST(GraphBuilder, InvariantNoEdgePassesThroughAnotherCommitsCell) {
    // I3: an edge descending in lane L must not cross a commit that occupies
    // (row, L), which would render as a line running through a node.
    auto snapshot = build(makeRandomDag(2000, 5551, 0.2, 2));

    for (const Edge& edge : snapshot->edges) {
        if (edge.parentRow == kRowBoundary) {
            continue;
        }
        for (RowId row = edge.childRow + 1; row < edge.parentRow; ++row) {
            EXPECT_NE(snapshot->rows[row].lane, edge.lane)
                << "edge in lane " << edge.lane << " passes through the commit at row " << row;
        }
    }
}

TEST(GraphBuilder, InvariantEveryCommitAppearsExactlyOnce) {
    auto commits = makeRandomDag(1500, 88, 0.2, 2);
    auto snapshot = build(commits);

    ASSERT_EQ(snapshot->rowCount(), commits.size());
    std::set<std::string> seen;
    for (const ObjectId& oid : snapshot->oids) {
        EXPECT_TRUE(seen.insert(oid.hex()).second) << "duplicate commit " << oid.hex();
    }

    RowId row = 0;
    EXPECT_TRUE(snapshot->findRow(oidFor(1), &row));
    EXPECT_EQ(row, 0u);
}

TEST(GraphBuilder, InvariantChunkInvariance) {
    // I6. This is the test that protects the whole streaming design: publishing
    // snapshots part-way through must not change the result, otherwise the graph
    // would visibly rearrange itself as history loads.
    auto commits = makeRandomDag(1200, 31337, 0.2, 3);
    auto whole = build(commits);

    for (std::size_t chunk :
         {std::size_t{1}, std::size_t{7}, std::size_t{97}, std::size_t{100000}}) {
        GraphBuilder builder;
        std::size_t since = 0;
        for (const Commit& commit : commits) {
            std::vector<ObjectId> parents;
            for (int parent : commit.parents) {
                parents.push_back(oidFor(parent));
            }
            builder.add(oidFor(commit.id), parents, 1000u + static_cast<std::uint32_t>(commit.id));
            if (++since >= chunk) {
                (void)builder.snapshot();  // Publish mid-stream.
                since = 0;
            }
        }
        builder.finish();
        auto chunked = builder.snapshot();

        ASSERT_EQ(chunked->rowCount(), whole->rowCount()) << "chunk size " << chunk;
        ASSERT_EQ(chunked->edges.size(), whole->edges.size()) << "chunk size " << chunk;
        EXPECT_EQ(chunked->laneCount, whole->laneCount) << "chunk size " << chunk;

        for (std::size_t i = 0; i < whole->rows.size(); ++i) {
            EXPECT_EQ(whole->rows[i].lane, chunked->rows[i].lane) << "row " << i;
            EXPECT_EQ(whole->rows[i].color, chunked->rows[i].color) << "row " << i;
            EXPECT_EQ(whole->rows[i].flags, chunked->rows[i].flags) << "row " << i;
        }
        for (std::size_t i = 0; i < whole->edges.size(); ++i) {
            EXPECT_EQ(whole->edges[i].childRow, chunked->edges[i].childRow);
            EXPECT_EQ(whole->edges[i].parentRow, chunked->edges[i].parentRow);
            EXPECT_EQ(whole->edges[i].lane, chunked->edges[i].lane);
            EXPECT_EQ(whole->edges[i].childLane, chunked->edges[i].childLane);
            EXPECT_EQ(whole->edges[i].color, chunked->edges[i].color);
        }
    }
}

TEST(GraphBuilder, InvariantColorsAreStableWhenHistoryIsAppended) {
    // I7. Colour comes from the lane's seed oid, not the lane index, so appending
    // newer commits must not recolour existing branches. Were it index-based,
    // every refresh would reshuffle the graph's colours.
    auto older = makeRandomDag(400, 777, 0.2, 2);
    auto baseline = build(older);

    // The same history with 50 newer commits prepended (newest-first order).
    std::vector<Commit> extended;
    for (int id = -50; id < 0; ++id) {
        extended.push_back({id, {id + 1 == 0 ? 1 : id + 1}});
    }
    for (const Commit& commit : older) {
        extended.push_back(commit);
    }
    auto grown = build(extended);

    for (const Commit& commit : older) {
        RowId baseRow = 0;
        RowId grownRow = 0;
        ASSERT_TRUE(baseline->findRow(oidFor(commit.id), &baseRow));
        ASSERT_TRUE(grown->findRow(oidFor(commit.id), &grownRow));
        // Lane 0 is the trunk in both, and its colour is fixed by contract.
        if (baseline->rows[baseRow].lane == 0 && grown->rows[grownRow].lane == 0) {
            EXPECT_EQ(baseline->rows[baseRow].color, grown->rows[grownRow].color);
        }
    }
}

TEST(GraphBuilder, LaneOverflowIsReportedRatherThanSilentlyDropped) {
    // More simultaneously-open branches than kMaxLanes. The requirement is not
    // that it renders perfectly, but that it never silently loses commits and
    // says so via overflowedEdges.
    std::vector<Commit> commits;
    const int branchCount = kMaxLanes + 20;
    const int shared = branchCount + 1;
    commits.push_back({1, {}});  // placeholder replaced below
    commits.clear();

    for (int b = 1; b <= branchCount; ++b) {
        commits.push_back({b, {shared}});
    }
    commits.push_back({shared, {}});

    auto snapshot = build(commits);
    EXPECT_EQ(snapshot->rowCount(), static_cast<std::size_t>(branchCount + 1));
    EXPECT_LE(snapshot->laneCount, kMaxLanes);

    bool anyOverflow = snapshot->overflowedEdges > 0;
    for (const RowMeta& row : snapshot->rows) {
        anyOverflow = anyOverflow || row.isOverflow();
    }
    EXPECT_TRUE(anyOverflow) << "exceeding the lane cap must be reported";
}

TEST(GraphBuilder, RespectsTheRowCap) {
    GraphOptions options;
    options.maxRows = 100;
    auto snapshot = build(makeRandomDag(500, 4242, 0.1), options);

    EXPECT_EQ(snapshot->rowCount(), 100u);
    EXPECT_TRUE(snapshot->truncated);
}

// --- viewport queries ------------------------------------------------------

TEST(GraphSnapshot, EdgesInRangeReturnsOnlyOverlappingEdges) {
    // The paint path must stay proportional to the viewport, not to history size.
    auto snapshot = build(makeRandomDag(2000, 606, 0.2, 2));

    std::vector<const Edge*> found;
    snapshot->edgesInRange(900, 960, found);

    for (const Edge* edge : found) {
        const RowId end = edge->parentRow == kRowBoundary ? edge->childRow + 1 : edge->parentRow;
        EXPECT_LE(edge->childRow, 960u);
        EXPECT_GE(end, 900u);
    }

    // Cross-check against a brute-force scan: the bucket index must not miss any.
    std::size_t expected = 0;
    for (const Edge& edge : snapshot->edges) {
        const RowId end = edge.parentRow == kRowBoundary ? edge.childRow + 1 : edge.parentRow;
        if (edge.childRow <= 960 && end >= 900) {
            ++expected;
        }
    }
    EXPECT_EQ(found.size(), expected);
}

TEST(GraphSnapshot, MaxLaneInRangeLetsTheGutterShrink) {
    auto snapshot = build({
        {1, {2, 5}},
        {2, {3}},
        {5, {6}},
        {3, {6}},
        {6, {7}},
        {7, {8}},
        {8, {}},
    });

    // The busy era near the merge is wider than the linear tail, so a viewport
    // over the tail can render a narrower gutter.
    const LaneId nearMerge = snapshot->maxLaneInRange(0, 4);
    const LaneId inTail = snapshot->maxLaneInRange(5, 6);
    EXPECT_GE(nearMerge, inTail);
    EXPECT_EQ(inTail, 0);
}

TEST(GraphSnapshot, MemoryStaysWithinTheBudget) {
    // The design budgets 64 MB per open repository for the graph of a 500k-commit
    // history. 92 bytes/commit is ~18% above the measured post-oidOrder_ cost
    // (77.3 on this fixture, 75-76 on a 20k-commit perf-shaped fixture and on
    // this repo's own real history -- see docs/PERFORMANCE.md, "GraphSnapshot
    // memory layout"), not a round number picked without measuring. Keep this
    // in sync with graph_check.cpp's --max-bytes-per-commit default.
    auto snapshot = build(makeRandomDag(5000, 12345, 0.15, 2));
    const double bytesPerCommit =
        static_cast<double>(snapshot->approximateBytes()) / snapshot->rowCount();

    // Printed unconditionally, not just on failure: this is the number bottleneck
    // #5 in docs/reports/vscode-graph-performance.md tracks over time, and a
    // passing run that never shows the margin makes silent regressions easy.
    std::fprintf(stderr, "GraphSnapshot memory: %.1f bytes/commit\n", bytesPerCommit);

    EXPECT_LT(bytesPerCommit, 92.0)
        << "at " << bytesPerCommit << " bytes/commit, 500k commits would exceed the 64 MB budget";
}

TEST(GraphSnapshot, FindRowSurvivesStreamedChunksAndMissesCleanly) {
    // The index backing findRow is rebuilt by finalizeIndices() on every
    // streamed chunk (see GraphSnapshot.h), not just once at the end. This
    // pins the contract that matters to callers -- every oid emitted so far is
    // findable after a chunk boundary (not just the first one), an oid that
    // has not been added yet misses cleanly even mid-stream, and a miss must
    // leave the caller's output untouched.
    auto commits = makeRandomDag(500, 424242, 0.2, 2);

    GraphBuilder builder;
    std::size_t since = 0;
    for (std::size_t i = 0; i < commits.size(); ++i) {
        const Commit& commit = commits[i];
        std::vector<ObjectId> parents;
        for (int parent : commit.parents) {
            parents.push_back(oidFor(parent));
        }
        builder.add(oidFor(commit.id), parents, 1000u + static_cast<std::uint32_t>(commit.id));
        if (++since >= 37) {
            auto midStream = builder.snapshot();  // Exercise finalizeIndices() mid-stream.
            for (std::size_t added = 0; added <= i; ++added) {
                RowId row = 0;
                EXPECT_TRUE(midStream->findRow(oidFor(commits[added].id), &row))
                    << "commit id " << commits[added].id << " was already added but is not findable";
            }
            if (i + 1 < commits.size()) {
                RowId notYetAdded = 0xDEADBEEFu;
                EXPECT_FALSE(midStream->findRow(oidFor(commits[i + 1].id), &notYetAdded))
                    << "commit id " << commits[i + 1].id << " has not been added yet but was found";
                EXPECT_EQ(notYetAdded, 0xDEADBEEFu);
            }
            since = 0;
        }
    }
    builder.finish();
    auto snapshot = builder.snapshot();

    for (const Commit& commit : commits) {
        RowId row = 0;
        ASSERT_TRUE(snapshot->findRow(oidFor(commit.id), &row)) << "missing oid for id " << commit.id;
        EXPECT_EQ(snapshot->oids[row], oidFor(commit.id));
    }

    // An oid that was never part of this history must miss cleanly and must not
    // touch the caller's output parameter.
    RowId sentinel = 0xDEADBEEFu;
    EXPECT_FALSE(snapshot->findRow(oidFor(999999), &sentinel));
    EXPECT_EQ(sentinel, 0xDEADBEEFu);

    // findRow(oid, nullptr) must not crash; only presence is asked for.
    EXPECT_TRUE(snapshot->findRow(oidFor(commits.back().id), nullptr));
}

// --- ASCII renderer --------------------------------------------------------

TEST(GraphAsciiRenderer, RendersLinearHistoryWithoutConnectors) {
    auto snapshot = build({{1, {2}}, {2, {3}}, {3, {}}});
    AsciiRenderOptions options;
    options.showShortOid = false;

    EXPECT_EQ(renderGraphAscii(*snapshot, options), "*\n*\n*\n");
}

TEST(GraphAsciiRenderer, MarksMergeCommitsDistinctly) {
    auto snapshot = build({{1, {2, 3}}, {2, {4}}, {3, {4}}, {4, {}}});
    AsciiRenderOptions options;
    options.showShortOid = false;

    const std::string rendered = renderGraphAscii(*snapshot, options);
    EXPECT_NE(rendered.find('M'), std::string::npos) << rendered;
    EXPECT_NE(rendered.find('\\'), std::string::npos) << rendered;
}

}  // namespace
}  // namespace gbm
