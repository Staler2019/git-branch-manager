#pragma once

#include "core/git/HistoryProvider.h"
#include "core/workers/Debouncer.h"

#include <chrono>

namespace gbm {

/// Collapses a burst of RepositorySession refresh requests
/// (refreshRefs()/refreshHistory()/refreshRefsAndHistory()) into exactly one
/// `for-each-ref` load, wrapping Debouncer with the request-merging
/// RepositorySession itself needs on top of "when to fire".
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
        pendingWantsRefs_ = pendingWantsRefs_ || wantsRefs;
        pendingWantsHistory_ = pendingWantsHistory_ || wantsHistory;
        pendingHasExplicit_ = pendingHasExplicit_ || origin == GraphUpdateOrigin::Explicit;

        const bool wasRunning = debouncer_.isRunning();
        debouncer_.notifyEvent(now);
        // See the class doc comment: required while running_ to set
        // Debouncer's dirty bit, a safe no-op while idle.
        debouncer_.shouldFire(now);

        return wasRunning ? RefreshAction::Fold : RefreshAction::Arm;
    }

    /// Wraps Debouncer::shouldFire(): true once the delay timer's quiet
    /// period has genuinely elapsed and a refresh must start now.
    bool onTimeout(Clock::time_point now = Clock::now()) { return debouncer_.shouldFire(now); }

    /// Bypasses the delay window and marks a refresh running immediately --
    /// for a caller that must fire right now rather than wait out the
    /// coalescing delay (RepositorySession::setHistoryFilter(), the one
    /// deliberate exception documented on the class above). Discards
    /// whatever was pending, the same as reset(): an immediate fire supplies
    /// its own query directly rather than going through takePending().
    ///
    /// Marking running_ here (rather than leaving the caller to bypass this
    /// class entirely) is what makes a request arriving during the immediate
    /// fire correctly Fold instead of arming its own independent refresh --
    /// which would otherwise race ahead and cancel the fire that was
    /// supposed to be immediate. Reuses the same mechanism
    /// Debouncer::finish() already relies on for a folded follow-up:
    /// notifyEvent() at the clock epoch guarantees the very next
    /// shouldFire() check sees an elapsed delay no matter how small `now`
    /// is.
    void fireNow(Clock::time_point now = Clock::now()) {
        pendingWantsRefs_ = false;
        pendingWantsHistory_ = false;
        pendingHasExplicit_ = false;
        debouncer_.notifyEvent(Clock::time_point{});
        debouncer_.shouldFire(now);
    }

    /// Wraps Debouncer::finish(): true when a request folded in while the
    /// refresh that just completed was running, so the caller must
    /// immediately re-drive the timer (start(0)) for the follow-up run.
    bool onFinished() { return debouncer_.finish(); }

    /// Consumes and clears the merged batch this fire covers. Must be called
    /// exactly once per onTimeout() that returned true, right before
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
    /// leave a stale Fold wedged forever.
    void reset() {
        debouncer_ = Debouncer(kDelay);
        pendingWantsRefs_ = false;
        pendingWantsHistory_ = false;
        pendingHasExplicit_ = false;
    }

private:
    Debouncer debouncer_;
    bool pendingWantsRefs_ = false;
    bool pendingWantsHistory_ = false;
    bool pendingHasExplicit_ = false;
};

}  // namespace gbm
