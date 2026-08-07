#pragma once

#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>

namespace gbm {

/// How a history refresh ended, for the timing line's `outcome=` field. See
/// docs/reports/vscode-graph-performance.md, bottleneck #4: the bridge-layer
/// delta between the Qt-free core walk and the real app was invisible because
/// nothing recorded which of these paths a given refresh actually took --
/// FirstChunk and Complete both look identical in the app's operation log
/// without this.
enum class WalkOutcome {
    /// The walk's first (possibly partial) chunk was published.
    FirstChunk,
    /// The walk's final chunk was published.
    Complete,
    /// RepositorySession::walkHistoryWithRefs()'s fingerprint fast path
    /// republished the previous graph without running rev-list at all.
    Skipped,
    /// The walk (or the for-each-ref load ahead of it) returned an error.
    Failed,
    /// A newer refresh superseded this one before it produced a result.
    Cancelled,
};

std::string_view toString(WalkOutcome outcome);

/// Pure decision behind walkTimingEnabled(): true only for the literal "1",
/// matching the truthy convention GBM_ASKPASS_MODE already uses
/// (AskpassHelper.cpp). This is a debug probe with a real per-walk cost
/// (RepositorySession has to build and thread a timing record through every
/// refresh), so it stays strict about what turns it on rather than guessing
/// at variants like "true"/"yes".
bool walkTimingEnabledForValue(const char* value);

/// Whether the GBM_TIMING env var requests the walk-timing probe. Reads the
/// process environment once (function-local static) and caches the result --
/// see walkTimingEnabledForValue() for the pure, testable decision this
/// wraps.
bool walkTimingEnabled();

/// One history refresh's segment boundaries, each as milliseconds elapsed
/// since the request was accepted (RepositorySession's refreshRefs() /
/// refreshHistory() / refreshRefsAndHistory() call -- that instant is
/// timestamp zero and is not itself a field here). -1 means "not reached":
/// distinct from 0, which would misrepresent a mark the fingerprint-skip or
/// error paths never touch (e.g. chunkBuiltMs when no walk ran at all) as
/// free rather than absent.
///
/// firedMs is the first mark reached and the odd one out: every mark after it
/// is a worker- or UI-thread event inside the walk itself, but firedMs is
/// RefreshCoalescer deciding the debounce window has elapsed and the walk may
/// actually start (see docs/reports/vscode-graph-performance.md, bottleneck
/// #6). Without it, the coalescing delay would silently inflate queue_ms
/// (worker queue wait) with a cost that has nothing to do with the worker
/// queue.
struct WalkMarks {
    std::int64_t firedMs = -1;           ///< t0: RefreshCoalescer released the request
    std::int64_t workerStartedMs = -1;   ///< t1: pool task began (queue wait ends)
    std::int64_t refsLoadedMs = -1;      ///< t2: for-each-ref done
    std::int64_t chunkBuiltMs = -1;      ///< t3: chunk built in core (worker thread)
    std::int64_t chunkDeliveredMs = -1;  ///< t4: emitGraphUpdated on the UI thread
    std::int64_t uiAppliedMs = -1;       ///< t5: model + column sizing applied
};

/// Formats one `gbm-timing walk ...` line -- see docs/PERFORMANCE.md,
/// "Bridge-layer timing probe" and docs/reports/vscode-graph-performance.md,
/// bottleneck #4. Pure string formatting: no clock reads, no I/O, so the
/// whole shape is unit-testable without a RepositorySession, which has no
/// test harness (see docs/PERFORMANCE.md).
///
/// Each `*_ms=` field is the gap between two consecutive marks (coalesce_ms
/// is the gap from timestamp zero to firedMs; queue_ms is firedMs to
/// workerStartedMs, i.e. the worker-pool queue wait after RefreshCoalescer
/// released the request). A field prints `-` rather than a number when
/// either endpoint was never reached, so a skipped or failed refresh cannot
/// be misread as an unusually fast one.
std::string formatWalkTiming(std::string_view origin,
                             WalkOutcome outcome,
                             std::size_t rows,
                             const WalkMarks& marks);

}  // namespace gbm
