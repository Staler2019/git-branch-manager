#pragma once

#include "core/git/HistoryProvider.h"
#include "core/workers/Debouncer.h"

#include <chrono>
#include <cstdint>

namespace gbm {

/// Collapses a burst of RepositorySession refresh requests
/// (refreshRefs()/refreshHistory()/refreshRefsAndHistory()/
/// setHistoryFilter()) into exactly one `for-each-ref` load, wrapping
/// Debouncer with the request-merging RepositorySession itself needs on top
/// of "when to fire".
///
/// See docs/reports/vscode-graph-performance.md, bottleneck #6: on a
/// repository with thousands of refs, a single `for-each-ref` call costs more
/// than the entire commit-graph-accelerated rev-list walk that follows it, so
/// a burst of refresh calls (checkout, then a rename, then a push, all within
/// a second) must not spawn one `for-each-ref` per call.
///
/// Two orthogonal jobs, split the same way Debouncer already splits "when":
///  - Debouncer decides *when* to fire and folds a request arriving mid-run
///    into exactly one follow-up (see its own doc comment for that half).
///  - RefreshCoalescer decides *what* the fired refresh should do: which of
///    refs/history were asked for across the whole window, merged as a union
///    rather than the last-write-wins a bare Debouncer would give, plus which
///    GraphUpdateOrigin the merged batch should log as.
///
/// Intended driver: RepositorySession owns one single-shot QTimer, restarted
/// (`QTimer::start(kDelay)`, which Qt restarts if already running) on every
/// request() call that returns Arm. A Fold means a refresh is already running
/// and the timer must be left alone; onFinished() returning true means the
/// caller must instead re-drive it immediately (`start(0)`), matching
/// Debouncer::finish()'s "fire immediately, no second wait".
///
/// Every dispatch (onTimeout() or fireNow()) returns a Generation -- a
/// monotonically increasing, never-reused id for that specific run. The
/// caller threads it through to whichever terminal path the resulting walk
/// takes and passes it back to onFinished(). A generation that no longer
/// matches the current one is stale -- superseded by a newer dispatch before
/// it reported back -- and onFinished() ignores it rather than touching
/// state the newer, still-in-flight run now owns.
///
/// This replaced an earlier design that tried to infer staleness from the
/// walk's own CancellationToken instead. That doesn't generalize: refs-only
/// walks and history walks are tracked by two different, independently
/// managed cancellation sources in RepositorySession (readCancel_ vs.
/// historyCancel_), and a token-based guard added for one path silently
/// missed the other. The generation counter is owned entirely by this class,
/// so a single check covers every terminal path uniformly regardless of
/// which cancellation source (if any) that path uses.
///
/// request() calls Debouncer::shouldFire() once immediately after
/// notifyEvent(), not just from the timer. While idle this is a harmless
/// no-op (a request just set lastEvent_ to `now`, so the quiet period cannot
/// have elapsed yet) -- but it is required while running_, because that is
/// the only thing that sets Debouncer's internal dirty bit. Without it,
/// finish() would never see a follow-up was owed: see Debouncer's own
/// CoalescesEventsArrivingMidRun test for why shouldFire() has to be called
/// again after notifyEvent() rather than deferred to the next timer tick.
///
/// Deliberately not thread-safe: every call is made from the UI thread, same
/// as StartupReadGate and every other RepositorySession call site.
class RefreshCoalescer {
public:
    /// Matches MainWindow's existing probeDebounce_/repoOpenDebounce_
    /// interval -- the established debounce window in this codebase.
    static constexpr std::chrono::milliseconds kDelay{150};

    using Clock = Debouncer::Clock;

    /// Identifies one dispatched run. 0 is reserved and never returned by
    /// onTimeout()/fireNow() -- it means "did not fire" for onTimeout(), and
    /// is otherwise not a value callers need to construct themselves.
    using Generation = std::uint64_t;

    /// Whether the caller must (re)arm the delay timer (Arm) or leave it
    /// alone because a refresh is already running and onFinished() will
    /// drive the follow-up instead (Fold).
    enum class RefreshAction { Arm, Fold };

    /// What the fired refresh should actually do, merged from every
    /// request() call in the window it covers.
    struct PendingRefresh {
        bool wantsRefs = false;
        bool wantsHistory = false;
        GraphUpdateOrigin origin = GraphUpdateOrigin::Explicit;
    };

    RefreshCoalescer() : debouncer_(kDelay) {}

    /// Records one refresh request, merging its flags and origin into the
    /// pending batch. Explicit always wins the merge -- a real user action
    /// folded into a window that also contained a silent auto-fetch resync
    /// must still log (and behave) as Explicit, not the other way round.
    RefreshAction request(bool wantsRefs,
                          bool wantsHistory,
                          GraphUpdateOrigin origin,
                          Clock::time_point now = Clock::now()) {
        mergeIntoPending(wantsRefs, wantsHistory, origin);

        const bool wasRunning = debouncer_.isRunning();
        debouncer_.notifyEvent(now);
        // See the class doc comment: required while running_ to set
        // Debouncer's dirty bit, a safe no-op while idle.
        debouncer_.shouldFire(now);

        return wasRunning ? RefreshAction::Fold : RefreshAction::Arm;
    }

    /// Wraps Debouncer::shouldFire(): once the delay timer's quiet period has
    /// genuinely elapsed, dispatches a new generation and returns it (never
    /// 0). Returns 0 when the quiet period has not yet elapsed.
    Generation onTimeout(Clock::time_point now = Clock::now()) {
        if (!debouncer_.shouldFire(now)) {
            return 0;
        }
        return ++generation_;
    }

    /// Bypasses the delay window and dispatches a new generation immediately
    /// -- for a caller that must fire right now rather than wait out the
    /// coalescing delay (RepositorySession::setHistoryFilter(), the one
    /// deliberate exception documented on the class above).
    ///
    /// Merges (wantsRefs, wantsHistory, origin) into the pending batch before
    /// resetting the debouncer's mechanics, so any request already armed but
    /// unfired, or already folded into an in-flight run that this call
    /// supersedes, is absorbed into the immediate fire's own batch rather
    /// than silently discarded -- the caller's very next takePending() call
    /// delivers it. The debouncer's running_/dirty_ state is always fully
    /// reset here regardless of whether a run was already in flight: the
    /// returned generation is what protects the superseded run's own
    /// eventual onFinished() from being misread as belonging to this one.
    Generation fireNow(bool wantsRefs,
                       bool wantsHistory,
                       GraphUpdateOrigin origin,
                       Clock::time_point now = Clock::now()) {
        mergeIntoPending(wantsRefs, wantsHistory, origin);

        debouncer_ = Debouncer(kDelay);
        // Reuses the same mechanism Debouncer::finish() already relies on
        // for a folded follow-up: notifyEvent() at the clock epoch
        // guarantees the very next shouldFire() check sees an elapsed delay
        // no matter how small `now` is.
        debouncer_.notifyEvent(Clock::time_point{});
        debouncer_.shouldFire(now);

        return ++generation_;
    }

    /// Wraps Debouncer::finish(): true when a request folded in while the
    /// run that just completed was running, so the caller must immediately
    /// re-drive the timer (start(0)) for the follow-up run. `generation`
    /// must be the value onTimeout()/fireNow() returned for the run that is
    /// finishing; a generation that no longer matches the current one is
    /// stale -- a newer dispatch has already superseded it -- and this is a
    /// no-op that returns false without touching any state.
    bool onFinished(Generation generation) {
        if (generation == 0 || generation != generation_) {
            return false;
        }
        return debouncer_.finish();
    }

    /// The generation currently dispatched (0 if none has fired yet). Lets a
    /// terminal path re-check, on the UI thread right before it publishes,
    /// whether a newer dispatch has already superseded the one it was
    /// carrying out -- see RepositorySession::startRefsOnly() for why that
    /// check has to happen here rather than via a worker-thread read of this
    /// (deliberately not thread-safe) class's state.
    Generation currentGeneration() const { return generation_; }

    /// Consumes and clears the merged batch this fire covers. Must be called
    /// exactly once per onTimeout()/fireNow() that dispatched, right before
    /// dispatching -- a later request() (folded, or the next window
    /// entirely) starts a fresh batch.
    PendingRefresh takePending() {
        PendingRefresh pending{
            pendingWantsRefs_,
            pendingWantsHistory_,
            pendingHasExplicit_ ? GraphUpdateOrigin::Explicit : GraphUpdateOrigin::AutoFetchResync};
        pendingWantsRefs_ = false;
        pendingWantsHistory_ = false;
        pendingHasExplicit_ = false;
        return pending;
    }

    /// Drops any pending or in-flight request state -- used by
    /// RepositorySession::cancelPendingReads() so a session teardown cannot
    /// leave a stale Fold wedged forever. Deliberately does not touch
    /// generation_: it must keep increasing so that a very late report from
    /// before this reset() can never coincidentally match a future
    /// dispatch's generation.
    void reset() {
        debouncer_ = Debouncer(kDelay);
        pendingWantsRefs_ = false;
        pendingWantsHistory_ = false;
        pendingHasExplicit_ = false;
    }

private:
    void mergeIntoPending(bool wantsRefs, bool wantsHistory, GraphUpdateOrigin origin) {
        pendingWantsRefs_ = pendingWantsRefs_ || wantsRefs;
        pendingWantsHistory_ = pendingWantsHistory_ || wantsHistory;
        pendingHasExplicit_ = pendingHasExplicit_ || origin == GraphUpdateOrigin::Explicit;
    }

    Debouncer debouncer_;
    Generation generation_ = 0;
    bool pendingWantsRefs_ = false;
    bool pendingWantsHistory_ = false;
    bool pendingHasExplicit_ = false;
};

}  // namespace gbm
