// Walks a real repository, builds the graph, and verifies it against git.
//
// This is the end-to-end check that the streaming walk, the parser and the lane
// algorithm agree with git itself on a repository of realistic size. It also
// prints the timings the performance budget is written against, so the same
// binary doubles as a profiling entry point.
//
//   gbm_graph_check <repo-path> [--print-rows N] [--max-bytes-per-commit F]
//
#include "core/base/CancellationToken.h"
#include "core/git/GitExecutable.h"
#include "core/git/HistoryProvider.h"
#include "core/git/RefStore.h"
#include "core/graph/GraphAsciiRenderer.h"

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

}  // namespace

int main(int argc, char** argv) {
    if (argc < 2) {
        std::fputs("usage: gbm_graph_check <repo-path> [--print-rows N]\n", stderr);
        return 2;
    }

    const std::filesystem::path repoPath = argv[1];
    int printRows = 0;
    double maxBytesPerCommit = 140.0;

    for (int i = 2; i < argc; ++i) {
        if (std::strcmp(argv[i], "--print-rows") == 0 && i + 1 < argc) {
            printRows = std::atoi(argv[++i]);
        } else if (std::strcmp(argv[i], "--max-bytes-per-commit") == 0 && i + 1 < argc) {
            maxBytesPerCommit = std::atof(argv[++i]);
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
    gbm::RefStore refStore(*runner, paths);
    auto refs = refStore.load(gbm::CancellationToken{});
    if (!refs) {
        std::fprintf(stderr, "could not read refs: %s\n", refs.error().message.c_str());
        return 1;
    }
    std::fprintf(stderr, "refs: %zu\n", (*refs)->totalRefCount);

    // --- walk ---------------------------------------------------------------
    gbm::HistoryQuery query;
    query.includeRefs = gbm::RefStore::historySeedRefs(**refs);

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
    for (const std::string& ref : query.includeRefs) {
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
