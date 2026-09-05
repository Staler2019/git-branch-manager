#include "core/git/HistoryProvider.h"

#include "core/base/Logging.h"
#include "core/base/ThreadCheck.h"
#include "core/graph/GraphBuilder.h"

#include <algorithm>
#include <charconv>
#include <span>
#include <utility>

namespace gbm {

std::vector<std::string> HistoryQuery::toRevListArgs() const {
    std::vector<std::string> args;
    args.emplace_back("rev-list");

    // --date-order, unconditionally. The History list draws this walk's
    // `--timestamp` in its Date column, so the row order has to agree with that
    // column: reading down the list, time must never go up. `--topo-order` does
    // not promise that -- it walks one branch to its end before starting the
    // next -- and on this project's own repository it produced **15 inversions
    // over 835 rows, 7 of them on merge rows**, which is what was reported.
    // `--date-order` measures 0 on the same repository.
    //
    // This overrules an earlier round, which kept `--topo-order` on the grounds
    // that it "groups a merged branch's commits at the point they landed rather
    // than interleaving them by timestamp". That is a true description and it
    // was the wrong trade: the grouping is exactly what puts a row above an
    // older one.
    //
    // Two claims the old comment made here are also withdrawn, both measured:
    //
    //  * "date order destroys the first-parent continuity the graph layout
    //    depends on" -- it does not. Lane occupancy is GraphBuilder's
    //    `laneRefCount_`, a count of pending edges, so a column stays held
    //    while its parent is unemitted no matter how many unrelated rows are
    //    interleaved. Interleaving lengthens a line; it never breaks one.
    //  * "topo streams for free when a commit-graph is present" -- so does
    //    date order, and by the same mechanism. Measured time-to-first-row on
    //    a 60,000-commit repository: 0.010s both, with a commit-graph; 0.160s
    //    vs 0.157s without. On 31,500 commits across 1,501 refs with 1,500
    //    merges: 0.163s vs 0.160s.
    //
    // What survives untouched is the property isLinearWalk() leans on: like
    // topo order, date order never prints a parent before its children.
    args.emplace_back("--date-order");
    args.emplace_back("--parents");
    args.emplace_back("--timestamp");

    if (firstParentOnly) {
        args.emplace_back("--first-parent");
    }
    if (noMerges) {
        args.emplace_back("--no-merges");
    }
    if (includeReflog) {
        args.emplace_back("--reflog");
    }
    if (maxCount > 0) {
        args.emplace_back("--max-count=" + std::to_string(maxCount));
    }
    if (author) {
        args.emplace_back("--author=" + *author);
    }
    if (grep) {
        args.emplace_back("--grep=" + *grep);
        args.emplace_back("--regexp-ignore-case");
    }
    if (since) {
        args.emplace_back("--since=" + std::to_string(*since));
    }
    if (until) {
        args.emplace_back("--until=" + std::to_string(*until));
    }

    // includeRefs narrows the walk (the branch filter): no --all, only what's
    // reachable from these tips. Otherwise seedRefs (usually HEAD's branch
    // plus its upstream and the trunk) go first and --all supplies everything
    // else. rev-list de-duplicates, so the seeds cost nothing -- but they do
    // *not* pin the trunk to the leftmost column, which is what this comment
    // used to claim; see seedRefs' own doc and GraphOptions::trunkTip.
    if (!includeRefs.empty()) {
        for (const std::string& ref : includeRefs) {
            args.push_back(ref);
        }
    } else {
        for (const std::string& ref : seedRefs) {
            args.push_back(ref);
        }
        args.emplace_back("--all");
    }

    for (const std::string& ref : excludeRefs) {
        args.emplace_back("--not");
        args.push_back(ref);
    }

    if (pathFilter) {
        args.emplace_back("--");
        args.push_back(*pathFilter);
    }
    return args;
}

std::string_view toString(GraphUpdateOrigin origin) {
    switch (origin) {
        case GraphUpdateOrigin::Explicit:
            return "explicit";
        case GraphUpdateOrigin::AutoFetchResync:
            return "auto-fetch resync";
    }
    return "unknown";
}

HistoryProvider::HistoryProvider(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

HistoryProvider::Record HistoryProvider::parseRevListLine(std::string_view line) {
    // With --timestamp --parents the record is:
    //     <unix-time> SP <oid> [SP <parent-oid>]...
    Record record;
    if (line.empty()) {
        return record;
    }

    std::size_t cursor = 0;
    auto nextToken = [&line, &cursor]() -> std::string_view {
        while (cursor < line.size() && line[cursor] == ' ') {
            ++cursor;
        }
        const std::size_t start = cursor;
        while (cursor < line.size() && line[cursor] != ' ') {
            ++cursor;
        }
        return line.substr(start, cursor - start);
    };

    const std::string_view timestamp = nextToken();
    if (timestamp.empty()) {
        return record;
    }

    std::uint64_t seconds = 0;
    const auto parsed =
        std::from_chars(timestamp.data(), timestamp.data() + timestamp.size(), seconds);
    if (parsed.ec != std::errc{}) {
        return record;
    }
    // Clamp rather than reject: a repository with a bogus far-future commit date
    // (they exist) should still render.
    record.commitTime =
        static_cast<std::uint32_t>(seconds > 0xFFFFFFFFull ? 0xFFFFFFFFull : seconds);

    const std::string_view oidText = nextToken();
    if (!record.oid.parseHex(oidText)) {
        return record;
    }

    for (;;) {
        const std::string_view parentText = nextToken();
        if (parentText.empty()) {
            break;
        }
        ObjectId parent;
        if (parent.parseHex(parentText)) {
            record.parents.push_back(parent);
        }
    }

    record.valid = true;
    return record;
}

GitResult<GraphSnapshotPtr> HistoryProvider::walk(const HistoryQuery& query,
                                                  const ChunkSink& onChunk,
                                                  CancellationToken token) {
    GBM_ASSERT_NOT_UI_THREAD();

    GitCommand command(paths_.commandDir(), query.toRevListArgs());
    // No timeout: on a cold 500k-commit repository this legitimately takes
    // seconds. Cancellation is the control the user actually needs.
    command.timeout = std::chrono::milliseconds(0);
    command.idleTimeout = GitCommand::kHangCeiling;

    GraphBuilder builder(GraphOptions{.trunkTip = query.trunkTip});
    std::size_t malformedLines = 0;

    // Linear mode holds each record back by one row so its parents can be
    // rewritten to whatever actually comes next -- see the lambda below and
    // HistoryQuery::isLinearWalk().
    const bool bridgeFilteredParents = query.isLinearWalk();
    Record held;

    // Geometric schedule: publish at 256 rows, then 512, 1024, ... Because each
    // publish costs O(rows), doubling keeps the total work linear overall.
    std::size_t nextPublishAt = kFirstChunkRows;
    bool publishedOnce = false;
    const auto started = std::chrono::steady_clock::now();

    const LineSink sink = [&](std::string_view line) {
        if (token.isCancelled()) {
            return false;
        }
        const Record record = parseRevListLine(line);
        if (!record.valid) {
            ++malformedLines;
            return true;  // Skip the row; do not abandon the whole walk.
        }
        if (bridgeFilteredParents) {
            // `--no-merges` removes rows from the middle of the history, so a
            // row's recorded parent is often a commit git never emits.
            // GraphBuilder would leave that edge pending and finish() would
            // turn it into a boundary stub -- a line that arrives from above
            // and stops halfway -- so a branch with three merges in it would be
            // drawn broken in three places, which is the opposite of the single
            // unbroken line this mode exists to show. The side branches the
            // merges brought in would also still be drawn as parallel lanes.
            //
            // Rewriting the parent to the next row emitted **is** a deliberate
            // simplification, not a reconstruction of the real edge: this mode
            // draws a list, and the segment means "the next row". See
            // isLinearWalk() for what that does and does not claim.
            //
            // The last record is emitted unbridged on purpose. A complete walk
            // ends at a root (no parents, correctly drawn as a root); a walk
            // cut short by --max-count keeps its real parent and so becomes a
            // boundary stub, which there is the true statement.
            if (held.valid) {
                const std::span<const ObjectId> bridged(&record.oid, 1);
                builder.add(held.oid, bridged, held.commitTime);
            }
            held = record;
        } else {
            builder.add(record.oid, record.parents, record.commitTime);
        }

        if (builder.truncated()) {
            return false;  // Row cap reached.
        }

        const std::size_t rows = builder.rowCount();
        bool publish = rows >= nextPublishAt;

        // The very first chunk may also go early on a timer, so a repository whose
        // walk is slow to start still paints promptly. Only the first: after that
        // the row thresholds take over, and a timer would reintroduce the
        // quadratic behaviour described in the header.
        if (!publish && !publishedOnce &&
            (std::chrono::steady_clock::now() - started) >= kFirstChunkInterval && rows > 0) {
            publish = true;
        }

        if (publish) {
            if (onChunk) {
                onChunk(builder.snapshot());
            }
            publishedOnce = true;
            // Wait another `rows` rows before the next publish -- i.e. double --
            // with the increment capped so very large histories still refresh.
            const std::size_t increment = std::min(std::max(rows, kFirstChunkRows), kMaxChunkRows);
            nextPublishAt = rows + increment;
        }
        return true;
    };

    auto result =
        runner_.streamSeparated(command, IProcessRunner::Separator::Newline, sink, nullptr, token);

    if (!result) {
        // A cancelled walk is not an error the UI should show; the caller simply
        // discards the partial result.
        return fail(std::move(result).error());
    }

    if (bridgeFilteredParents && held.valid) {
        builder.add(held.oid, held.parents, held.commitTime);
    }

    // `--max-count` stops rev-list itself rather than the builder's own row
    // cap, so builder.truncated() would otherwise stay false even though the
    // history shown is partial -- mark it explicitly so the existing
    // "history truncated" UI (which already reads GraphSnapshot::truncated)
    // reports it correctly.
    if (query.maxCount > 0 && builder.rowCount() >= query.maxCount) {
        builder.markTruncated();
    }

    builder.finish();
    auto finalSnapshot = builder.snapshot();

    if (malformedLines > 0) {
        logMessage(LogLevel::Warn,
                   "Skipped " + std::to_string(malformedLines) + " unparseable rev-list records");
    }
    if (onChunk) {
        onChunk(finalSnapshot);
    }
    return finalSnapshot;
}

}  // namespace gbm
