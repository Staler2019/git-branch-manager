// Walks a real repository, builds the graph, and verifies it against git.
//
// This is the end-to-end check that the streaming walk, the parser and the lane
// algorithm agree with git itself on a repository of realistic size. It also
// prints the timings the performance budget is written against, so the same
// binary doubles as a profiling entry point.
//
//   gbm_graph_check <repo-path> [--print-rows N] [--max-bytes-per-commit F]
//                              [--commit-graph-ab N] [--min-graph-speedup F]
//
#include "core/base/CancellationToken.h"
#include "core/git/GitExecutable.h"
#include "core/git/HistoryProvider.h"
#include "core/git/RefStore.h"
#include "core/graph/GraphAsciiRenderer.h"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

int failures = 0;

void check(bool condition, const std::string& what) {
    if (!condition) {
        std::fprintf(stderr, "FAIL: %s\n", what.c_str());
        ++failures;
    }
}

std::vector<std::string> splitLines(const std::string& text) {
    std::vector<std::string> lines;
    std::size_t start = 0;
    while (start < text.size()) {
        const std::size_t at = text.find('\n', start);
        const std::string line =
            text.substr(start, at == std::string::npos ? std::string::npos : at - start);
        if (!line.empty()) {
            lines.push_back(line);
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return lines;
}

// --- timed walk, and the commit-graph A/B gate ------------------------------

struct WalkTiming {
    long long firstChunkMs = 0;
    long long totalMs = 0;
    std::size_t rows = 0;
    std::size_t chunks = 0;
    gbm::GraphSnapshotPtr snapshot;  ///< Null when the walk failed.
};

/// One timed walk. Extracted so the single-run path below and the
/// commit-graph A/B loop measure through exactly the same code -- if the two
/// ever drifted, the ratio the gate asserts on would be comparing two
/// different things.
WalkTiming timeOneWalk(gbm::HistoryProvider& provider, const gbm::HistoryQuery& query) {
    const auto start = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point firstChunk{};
    std::size_t chunks = 0;

    auto snapshot = provider.walk(
        query,
        [&](gbm::GraphSnapshotPtr chunk) {
            if (chunks == 0) {
                firstChunk = std::chrono::steady_clock::now();
            }
            ++chunks;
            (void)chunk;
        },
        gbm::CancellationToken{});
    const auto done = std::chrono::steady_clock::now();

    WalkTiming timing;
    if (!snapshot) {
        std::fprintf(stderr, "walk failed: %s\n", snapshot.error().message.c_str());
        return timing;
    }
    timing.snapshot = *snapshot;
    timing.rows = (*snapshot)->rowCount();
    timing.chunks = chunks;
    timing.firstChunkMs =
        std::chrono::duration_cast<std::chrono::milliseconds>(firstChunk - start).count();
    timing.totalMs = std::chrono::duration_cast<std::chrono::milliseconds>(done - start).count();
    return timing;
}

void setEnvVar(const char* key, const char* value) {
#if defined(_WIN32)
    ::_putenv_s(key, value);
#else
    ::setenv(key, value, 1);
#endif
}

/// Turns git's use of an existing commit-graph file on or off for every git
/// child this driver spawns from here on.
///
/// It has to arrive out of band, in the environment, rather than as a
/// `git -c core.commitGraph=false` argument on the walk's own command line:
/// HistoryProvider owns the rev-list argv, and the entire point of this
/// measurement is to time the argv the app actually runs. ProcessRunner
/// copies the parent's environment at spawn time, so a setenv here is picked
/// up by the very next child and nothing spawned before it.
///
/// Chosen over writing/deleting the commit-graph file between arms because
/// nothing on disk changes either way: same pack, same inodes, same warm page
/// cache. Physically mutating the repository between arms would move the
/// cache underneath the comparison -- exactly the confound a ratio test
/// cannot absorb.
///
/// Needs GIT_CONFIG_COUNT, i.e. git >= 2.31 -- one minor above this project's
/// 2.30 floor. The caller checks the version first: a silently ignored toggle
/// would make both arms identical and report a false ~1.0x regression.
void setCommitGraphEnabled(bool enabled) {
    setEnvVar("GIT_CONFIG_COUNT", "1");
    setEnvVar("GIT_CONFIG_KEY_0", "core.commitGraph");
    setEnvVar("GIT_CONFIG_VALUE_0", enabled ? "true" : "false");
}

long long medianOf(std::vector<long long> values) {
    // Median, not mean and not best-of-N. A mean is dragged by the one sample
    // that got descheduled; best-of-N systematically flatters whichever arm
    // happened to catch the quietest moment on the machine. With an odd
    // sample count the median is a real observation, not an average of luck.
    std::sort(values.begin(), values.end());
    return values.empty() ? 0 : values[values.size() / 2];
}

std::string joinSamples(const std::vector<long long>& values) {
    std::string text;
    for (const long long value : values) {
        if (!text.empty()) {
            text += ' ';
        }
        text += std::to_string(value);
    }
    return text;
}

/// Times the same walk with and without git's commit-graph and fails if the
/// graph has stopped buying what docs/PERFORMANCE.md claims it buys.
///
/// A *ratio*, deliberately, and never an absolute millisecond ceiling. On a
/// real 162,368-commit clone, removing the commit-graph moved
/// time-to-first-chunk 62ms -> 898ms and the full walk 195ms -> 1027ms -- but
/// on that same warm repository the identical operation swung 83ms -> 1069ms
/// across five runs of an unchanged binary (see
/// docs/reports/vscode-graph-performance.md). An absolute gate wide enough to
/// survive that spread would catch nothing; one tight enough to catch a
/// regression would go red most nights. The ratio between two arms measured
/// seconds apart on one machine is stable in a way neither arm's absolute
/// value is: whatever is making the machine slow that moment is making both
/// arms slow.
void runCommitGraphAb(gbm::HistoryProvider& provider,
                      const gbm::HistoryQuery& query,
                      const gbm::GitInstallation& installation,
                      int pairs,
                      double minSpeedup) {
    // GIT_CONFIG_COUNT is git 2.31; this project's floor is 2.30. Refusing
    // here is the whole reason this check exists: on 2.30 the toggle is
    // silently ignored, both arms use the commit-graph, and the run would
    // report a false ~1.0x regression instead of naming the real problem.
    if (installation.version < gbm::GitVersion{2, 31, 0}) {
        check(false,
              "commit-graph A/B needs git 2.31 for GIT_CONFIG_COUNT; found " +
                  installation.version.toString());
        return;
    }

    // A warm-up walk whose timing is discarded. The first walk pays for
    // faulting the pack and the commit-graph file into the page cache;
    // charging that cost to whichever arm happens to run first would bias
    // exactly the comparison this gate exists to make fairly.
    setCommitGraphEnabled(true);
    const WalkTiming warmup = timeOneWalk(provider, query);
    if (!warmup.snapshot) {
        check(false, "commit-graph A/B warm-up walk failed");
        return;
    }

    std::vector<long long> offTotal;
    std::vector<long long> offFirst;
    std::vector<long long> onTotal;
    std::vector<long long> onFirst;
    bool rowsAgree = true;

    for (int i = 0; i < pairs; ++i) {
        // The no-graph arm runs first in every pair on purpose. It touches a
        // superset of the pages the graph arm needs, so any residual
        // cold-cache cost lands on the arm already called slow: the bias runs
        // toward *understating* the speedup, so a pass can never be an
        // artefact of the ordering.
        setCommitGraphEnabled(false);
        const WalkTiming off = timeOneWalk(provider, query);
        setCommitGraphEnabled(true);
        const WalkTiming on = timeOneWalk(provider, query);
        if (!off.snapshot || !on.snapshot) {
            check(false, "a walk failed during the commit-graph A/B loop");
            return;
        }
        rowsAgree = rowsAgree && off.rows == warmup.rows && on.rows == warmup.rows;
        offTotal.push_back(off.totalMs);
        offFirst.push_back(off.firstChunkMs);
        onTotal.push_back(on.totalMs);
        onFirst.push_back(on.firstChunkMs);
    }
    setCommitGraphEnabled(true);  // Leave the process in the state main() otherwise expects.

    // If the two arms disagree on row count they did not walk the same
    // history, and whatever ratio came out of them means nothing.
    check(rowsAgree, "the commit-graph A/B arms walked different row counts");

    const long long offMs = medianOf(offTotal);
    const long long onMs = medianOf(onTotal);
    const long long offFirstMs = medianOf(offFirst);
    const long long onFirstMs = medianOf(onFirst);

    std::fprintf(stderr,
                 "commit-graph A/B (%d pairs, %zu rows):\n"
                 "  graph off: total median=%lldms [%s] first-chunk median=%lldms\n"
                 "  graph on : total median=%lldms [%s] first-chunk median=%lldms\n",
                 pairs,
                 warmup.rows,
                 offMs,
                 joinSamples(offTotal).c_str(),
                 offFirstMs,
                 onMs,
                 joinSamples(onTotal).c_str(),
                 onFirstMs);

    // Below this floor, 1ms clock resolution and process-spawn cost are a
    // large fraction of the measurement and the ratio stops meaning anything.
    // This is the guard against the one realistic way the gate degenerates
    // into passing on noise: someone shrinking the fixture to make CI faster.
    constexpr long long kMinMeasurableMs = 50;
    check(onMs >= kMinMeasurableMs,
          "fixture too small to time: the commit-graph walk took " + std::to_string(onMs) +
              "ms, under the " + std::to_string(kMinMeasurableMs) +
              "ms floor -- raise the fixture's commit count");

    const double totalSpeedup =
        static_cast<double>(offMs) / static_cast<double>(std::max<long long>(onMs, 1));
    const double firstSpeedup =
        static_cast<double>(offFirstMs) / static_cast<double>(std::max<long long>(onFirstMs, 1));

    // One machine-readable line for the nightly job's Step Summary to grep.
    std::fprintf(stderr,
                 "commit-graph-ab: rows=%zu pairs=%d off_total_ms=%lld on_total_ms=%lld "
                 "total_speedup=%.2f off_first_ms=%lld on_first_ms=%lld first_speedup=%.2f\n",
                 warmup.rows,
                 pairs,
                 offMs,
                 onMs,
                 totalSpeedup,
                 offFirstMs,
                 onFirstMs,
                 firstSpeedup);

    // Gated on total, reported on first-chunk. Time-to-first-chunk is the more
    // dramatic number (14x vs 5.3x on a real 162k-commit clone) because
    // streaming topo-order is exactly what the commit-graph enables -- but it
    // is a single instant, one descheduling away from a wrong answer, whereas
    // total aggregates the whole walk and averages that away. One gate, on
    // the steadier metric; the other number is here for the nightly trend.
    check(totalSpeedup >= minSpeedup,
          "commit-graph speedup fell to " + std::to_string(totalSpeedup) + "x, under the " +
              std::to_string(minSpeedup) + "x gate");
}

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fputs("usage: gbm_graph_check <repo-path> [--print-rows N]\n", stderr);
        return 2;
    }

    const std::filesystem::path repoPath = argv[1];
    int printRows = 0;
    double maxBytesPerCommit = 140.0;
    int commitGraphAbPairs = 0;
    double minGraphSpeedup = 2.0;

    for (int i = 2; i < argc; ++i) {
        if (std::strcmp(argv[i], "--print-rows") == 0 && i + 1 < argc) {
            printRows = std::atoi(argv[++i]);
        } else if (std::strcmp(argv[i], "--max-bytes-per-commit") == 0 && i + 1 < argc) {
            maxBytesPerCommit = std::atof(argv[++i]);
        } else if (std::strcmp(argv[i], "--commit-graph-ab") == 0 && i + 1 < argc) {
            commitGraphAbPairs = std::atoi(argv[++i]);
            // Forced odd so medianOf() returns a real observation rather than
            // averaging the two middle samples.
            if (commitGraphAbPairs > 0 && commitGraphAbPairs % 2 == 0) {
                ++commitGraphAbPairs;
            }
        } else if (std::strcmp(argv[i], "--min-graph-speedup") == 0 && i + 1 < argc) {
            minGraphSpeedup = std::atof(argv[++i]);
        }
    }

    auto installation = gbm::GitExecutable::detect();
    if (!installation) {
        std::fprintf(stderr, "no usable git: %s\n", installation.error().message.c_str());
        return 1;
    }
    std::fprintf(stderr,
                 "using git %s at %s\n",
                 installation->version.toString().c_str(),
                 installation->executable.string().c_str());

    auto runner = gbm::makeProcessRunner(installation->executable);
    const gbm::RepoPaths paths(repoPath, repoPath / ".git", repoPath / ".git");

    // --- refs ---------------------------------------------------------------
    // Timed, and run twice, to make the single-call cost and the
    // "if something ran for-each-ref twice" cost both visible on whatever
    // repository this is pointed at -- not just the rev-list walk
    // docs/PERFORMANCE.md already measures. This is what motivated
    // RepositorySession::refreshRefsAndHistory(), which shares one load
    // between refreshRefs() and refreshHistory() instead of each
    // independently re-running it (every call site that needs both now uses
    // it); the second timing below is what that fix avoids paying for. See
    // docs/PERFORMANCE.md's "UI refresh path" section for the numbers this
    // produced on a repository with a few thousand refs.
    gbm::RefStore refStore(*runner, paths);
    const auto refsStart = std::chrono::steady_clock::now();
    auto refs = refStore.load(gbm::CancellationToken{});
    const auto refsFirstMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                                 std::chrono::steady_clock::now() - refsStart)
                                 .count();
    if (!refs) {
        std::fprintf(stderr, "could not read refs: %s\n", refs.error().message.c_str());
        return 1;
    }

    const auto refsSecondStart = std::chrono::steady_clock::now();
    auto refsAgain = refStore.load(gbm::CancellationToken{});
    const auto refsSecondMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                                  std::chrono::steady_clock::now() - refsSecondStart)
                                  .count();
    check(static_cast<bool>(refsAgain), "second for-each-ref call failed");

    std::fprintf(stderr,
                 "refs: %zu (for-each-ref: %lldms once, %lldms twice back-to-back)\n",
                 (*refs)->totalRefCount,
                 static_cast<long long>(refsFirstMs),
                 static_cast<long long>(refsFirstMs + refsSecondMs));

    // --- walk ---------------------------------------------------------------
    gbm::HistoryQuery query;
    query.seedRefs = gbm::RefStore::historySeedRefs(**refs);

    const auto start = std::chrono::steady_clock::now();
    std::chrono::steady_clock::time_point firstChunk{};
    std::size_t chunks = 0;

    gbm::HistoryProvider provider(*runner, paths);
    auto snapshot = provider.walk(
        query,
        [&](gbm::GraphSnapshotPtr chunk) {
            if (chunks == 0) {
                firstChunk = std::chrono::steady_clock::now();
            }
            ++chunks;
            (void)chunk;
        },
        gbm::CancellationToken{});
    if (!snapshot) {
        std::fprintf(stderr, "walk failed: %s\n", snapshot.error().message.c_str());
        return 1;
    }
    const auto done = std::chrono::steady_clock::now();

    const auto toFirstMs =
        std::chrono::duration_cast<std::chrono::milliseconds>(firstChunk - start).count();
    const auto totalMs =
        std::chrono::duration_cast<std::chrono::milliseconds>(done - start).count();
    const auto rows = (*snapshot)->rowCount();

    std::fprintf(stderr,
                 "rows=%zu edges=%zu lanes=%u chunks=%zu\n"
                 "time-to-first-chunk=%lldms total=%lldms\n",
                 rows,
                 (*snapshot)->edges.size(),
                 (*snapshot)->laneCount,
                 chunks,
                 static_cast<long long>(toFirstMs),
                 static_cast<long long>(totalMs));

    if (rows > 0) {
        const double bytesPerCommit =
            static_cast<double>((*snapshot)->approximateBytes()) / static_cast<double>(rows);
        std::fprintf(stderr,
                     "memory=%.1f bytes/commit (%.1f MB projected at 500k)\n",
                     bytesPerCommit,
                     bytesPerCommit * 500000.0 / (1024.0 * 1024.0));
        check(bytesPerCommit < maxBytesPerCommit,
              "memory per commit exceeds the budget: " + std::to_string(bytesPerCommit));
    }

    // --- cross-check the row order against git itself -----------------------
    // The single most valuable assertion here: a plausible-looking graph built
    // from a misparsed walk is far worse than an obvious failure.
    std::vector<std::string> expectedArgs{"rev-list", "--topo-order"};
    for (const std::string& ref : query.seedRefs) {
        expectedArgs.push_back(ref);
    }
    expectedArgs.emplace_back("--all");

    gbm::GitCommand command(paths.commandDir(), expectedArgs);
    auto expected = runner->run(command, gbm::CancellationToken{});
    if (!expected) {
        std::fprintf(
            stderr, "could not read git's own order: %s\n", expected.error().message.c_str());
        return 1;
    }

    const auto expectedOids = splitLines(expected->out);
    check(expectedOids.size() == rows,
          "row count " + std::to_string(rows) + " != git's " + std::to_string(expectedOids.size()));

    const std::size_t compare = std::min(expectedOids.size(), rows);
    std::size_t mismatches = 0;
    for (std::size_t row = 0; row < compare; ++row) {
        if ((*snapshot)->oids[row].hex() != expectedOids[row]) {
            if (mismatches < 5) {
                std::fprintf(stderr,
                             "row %zu: got %s, git says %s\n",
                             row,
                             (*snapshot)->oids[row].hex().c_str(),
                             expectedOids[row].c_str());
            }
            ++mismatches;
        }
    }
    check(mismatches == 0, std::to_string(mismatches) + " rows diverge from git's topo order");

    // --- invariants on real history ----------------------------------------
    std::size_t straight = 0;
    std::size_t movedRight = 0;
    for (const gbm::Edge& edge : (*snapshot)->edges) {
        if (edge.parentRow != gbm::kRowBoundary) {
            check(edge.parentRow > edge.childRow, "an edge points upwards");
        }
        if (edge.kind != gbm::EdgeKind::FirstParent || edge.parentRow == gbm::kRowBoundary) {
            continue;
        }
        const gbm::LaneId parentLane = (*snapshot)->rows[edge.parentRow].lane;
        if (parentLane == edge.childLane) {
            ++straight;
        } else if (parentLane > edge.childLane) {
            ++movedRight;
        }
    }
    check(movedRight == 0,
          std::to_string(movedRight) + " first-parent chains moved right (should be 0)");
    std::fprintf(
        stderr, "first-parent edges: %zu straight, %zu moved right\n", straight, movedRight);

    // Runs after correctness is established above: a broken walk should
    // report as a walk bug, not a perf regression. Off by default (0 pairs);
    // the commit_graph_speedup_ratio ctest is the only caller that turns it
    // on, via RunCommitGraphRatioCheck.cmake.
    if (commitGraphAbPairs > 0) {
        runCommitGraphAb(provider, query, *installation, commitGraphAbPairs, minGraphSpeedup);
    }

    if (printRows > 0) {
        gbm::AsciiRenderOptions options;
        options.showLaneNumbers = true;
        options.maxRows = static_cast<std::size_t>(printRows);
        std::fputs(renderGraphAscii(**snapshot, options).c_str(), stdout);
    }

    if (failures == 0) {
        std::fputs("graph_check: OK\n", stderr);
        return 0;
    }
    std::fprintf(stderr, "graph_check: %d failure(s)\n", failures);
    return 1;
}
