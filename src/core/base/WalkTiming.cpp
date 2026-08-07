#include "core/base/WalkTiming.h"

#include <cstdlib>
#include <cstring>

namespace gbm {

std::string_view toString(WalkOutcome outcome) {
    switch (outcome) {
        case WalkOutcome::FirstChunk:
            return "first-chunk";
        case WalkOutcome::Complete:
            return "complete";
        case WalkOutcome::Skipped:
            return "skipped";
        case WalkOutcome::Failed:
            return "failed";
        case WalkOutcome::Cancelled:
            return "cancelled";
    }
    return "unknown";
}

bool walkTimingEnabledForValue(const char* value) {
    return value != nullptr && std::strcmp(value, "1") == 0;
}

bool walkTimingEnabled() {
    static const bool enabled = walkTimingEnabledForValue(std::getenv("GBM_TIMING"));
    return enabled;
}

namespace {

/// Appends "<name>=<value>" or "<name>=-" depending on whether both marks
/// were reached, and returns the later mark for the caller's next segment.
/// `from` is the previous segment's end mark (or 0 for the very first
/// segment, whose start is the request itself); `to` is -1 when unreached.
void appendSegment(std::string& out, std::string_view name, std::int64_t from, std::int64_t to) {
    out += name;
    out.push_back('=');
    if (from < 0 || to < 0) {
        out.push_back('-');
        return;
    }
    out += std::to_string(to - from);
}

}  // namespace

std::string formatWalkTiming(std::string_view origin,
                             WalkOutcome outcome,
                             std::size_t rows,
                             const WalkMarks& marks) {
    std::string out = "gbm-timing walk origin=";
    out += origin;
    out += " outcome=";
    out += toString(outcome);
    out += " rows=";
    out += std::to_string(rows);
    out.push_back(' ');

    appendSegment(out, "coalesce_ms", 0, marks.firedMs);
    out.push_back(' ');
    appendSegment(out, "queue_ms", marks.firedMs, marks.workerStartedMs);
    out.push_back(' ');
    appendSegment(out, "refs_ms", marks.workerStartedMs, marks.refsLoadedMs);
    out.push_back(' ');
    appendSegment(out, "walk_ms", marks.refsLoadedMs, marks.chunkBuiltMs);
    out.push_back(' ');
    appendSegment(out, "hop_ms", marks.chunkBuiltMs, marks.chunkDeliveredMs);
    out.push_back(' ');
    appendSegment(out, "apply_ms", marks.chunkDeliveredMs, marks.uiAppliedMs);
    out.push_back(' ');

    // total_ms is the last mark actually reached, not always uiAppliedMs --
    // skipped/failed/cancelled refreshes never reach MainWindow, so there is
    // no UI-apply leg to report.
    std::int64_t total = -1;
    if (marks.uiAppliedMs >= 0) {
        total = marks.uiAppliedMs;
    } else if (marks.chunkDeliveredMs >= 0) {
        total = marks.chunkDeliveredMs;
    } else if (marks.chunkBuiltMs >= 0) {
        total = marks.chunkBuiltMs;
    } else if (marks.refsLoadedMs >= 0) {
        total = marks.refsLoadedMs;
    } else if (marks.workerStartedMs >= 0) {
        total = marks.workerStartedMs;
    } else if (marks.firedMs >= 0) {
        total = marks.firedMs;
    }
    out += "total_ms=";
    if (total < 0) {
        out.push_back('-');
    } else {
        out += std::to_string(total);
    }

    return out;
}

}  // namespace gbm
