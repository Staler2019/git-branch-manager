#pragma once

#include "core/base/WalkTiming.h"
#include "core/git/HistoryProvider.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <memory>

namespace gbm {

/// Shared, per-refresh carrier for the marks core/base/WalkTiming.h turns
/// into a `gbm-timing walk ...` line -- see
/// docs/reports/vscode-graph-performance.md, bottleneck #4. Built once per
/// RepositorySession::refreshHistory()/refreshRefsAndHistory() call, right
/// after setBusy(true) (that instant is timestamp zero), and threaded
/// through the posted worker lambda, walkHistoryWithRefs(), and the chunk
/// callback. Null whenever walkTimingEnabled() is false -- every
/// RepositorySession call site checks for null before touching a mark,
/// which is what keeps this free when the probe is off.
///
/// The five timing marks are std::atomic<std::int64_t>, not plain fields:
/// the worker thread marks workerStartedMs/refsLoadedMs/chunkBuiltMs while
/// the UI thread may still be formatting the previous chunk's line (a walk
/// can publish several chunks before it completes), and this object carries
/// no other synchronization of its own. skipped_ and firstChunkLogged_ are
/// ordinary bool members deliberately -- both are only ever touched from
/// inside RepositorySession's Qt::QueuedConnection lambdas, i.e. the UI
/// thread, same as SnapshotHolder's documented split between "worker
/// publishes, UI thread reads".
class WalkTimingProbe {
public:
    explicit WalkTimingProbe(GraphUpdateOrigin origin)
        : origin_(origin), requestedAt_(std::chrono::steady_clock::now()) {}

    GraphUpdateOrigin origin() const { return origin_; }

    void markWorkerStarted() { mark(workerStartedMs_); }

    void markRefsLoaded() { mark(refsLoadedMs_); }

    void markChunkBuilt() { mark(chunkBuiltMs_); }

    void markChunkDelivered() { mark(chunkDeliveredMs_); }

    void markUiApplied() { mark(uiAppliedMs_); }

    /// Set by the fingerprint fast path (RepositorySession::
    /// walkHistoryWithRefs()) before it calls emitGraphUpdated() -- that call
    /// republishes the prior graph without running rev-list at all, so the
    /// resulting line must say outcome=skipped rather than the
    /// first-chunk/complete inference RepositorySession::noteGraphApplied()
    /// otherwise makes from `complete`.
    void markSkipped() { skipped_ = true; }

    bool consumeSkipped() {
        const bool was = skipped_;
        skipped_ = false;
        return was;
    }

    /// True once a first-chunk, complete, or skipped line has been logged
    /// for this probe -- lets noteGraphApplied() skip the intermediate
    /// chunks HistoryProvider's geometric publish schedule produces between
    /// the first and the last, so a walk logs at most two lines rather than
    /// one per chunk.
    bool firstChunkLogged() const { return firstChunkLogged_; }

    void setFirstChunkLogged() { firstChunkLogged_ = true; }

    WalkMarks snapshot() const {
        WalkMarks marks;
        marks.workerStartedMs = workerStartedMs_.load();
        marks.refsLoadedMs = refsLoadedMs_.load();
        marks.chunkBuiltMs = chunkBuiltMs_.load();
        marks.chunkDeliveredMs = chunkDeliveredMs_.load();
        marks.uiAppliedMs = uiAppliedMs_.load();
        return marks;
    }

private:
    void mark(std::atomic<std::int64_t>& slot) {
        const auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - requestedAt_);
        slot.store(elapsed.count());
    }

    GraphUpdateOrigin origin_;
    std::chrono::steady_clock::time_point requestedAt_;
    std::atomic<std::int64_t> workerStartedMs_{-1};
    std::atomic<std::int64_t> refsLoadedMs_{-1};
    std::atomic<std::int64_t> chunkBuiltMs_{-1};
    std::atomic<std::int64_t> chunkDeliveredMs_{-1};
    std::atomic<std::int64_t> uiAppliedMs_{-1};
    bool skipped_ = false;
    bool firstChunkLogged_ = false;
};

using WalkTimingProbePtr = std::shared_ptr<WalkTimingProbe>;

}  // namespace gbm
