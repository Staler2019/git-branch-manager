#include "core/git/HistoryProvider.h"

#include "core/base/Logging.h"
#include "core/base/ThreadCheck.h"
#include "core/graph/GraphBuilder.h"

#include <algorithm>
#include <charconv>
#include <utility>

namespace gbm {

std::vector<std::string> HistoryQuery::toRevListArgs() const {
    std::vector<std::string> args;
    args.emplace_back("rev-list");

    // --topo-order, never --date-order: date order interleaves branches, which
    // destroys the first-parent continuity the graph layout depends on. git's
    // topo walk is already streaming when a commit-graph is present, so we get
    // ordering for free rather than sorting half a million rows ourselves.
    args.emplace_back(dateOrder ? "--date-order" : "--topo-order");
    args.emplace_back("--parents");
    args.emplace_back("--timestamp");

    if (firstParentOnly) {
        args.emplace_back("--first-parent");
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

    // Explicit tips first, then --all. rev-list de-duplicates, and the graph
    // builder assigns lane 0 to the first tip it encounters, so this ordering is
    // what pins the trunk to the leftmost column.
    for (const std::string& ref : includeRefs) {
        args.push_back(ref);
    }
    args.emplace_back("--all");

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

    GraphBuilder builder;
    std::size_t malformedLines = 0;

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
        builder.add(record.oid, record.parents, record.commitTime);

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
