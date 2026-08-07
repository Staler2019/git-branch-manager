#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/ObjectId.h"
#include "core/base/WalkTiming.h"
#include "core/git/AskpassHelper.h"
#include "core/git/CommitMeta.h"
#include "core/git/GitExecutable.h"
#include "core/git/HistoryProvider.h"
#include "core/git/RefStore.h"
#include "core/git/RepoPaths.h"
#include "core/workers/Debouncer.h"
#include "core/workers/RefreshCoalescer.h"
#include "core/workers/StartupReadGate.h"
#include "core/workers/ThreadPool.h"

#include <atomic>
#include <fstream>
#include <gtest/gtest.h>
#include <string>
#include <thread>
#include <vector>

namespace gbm {
namespace {

// --- ObjectId --------------------------------------------------------------

TEST(ObjectId, ParsesSha1AndSha256) {
    const std::string sha1 = "0123456789abcdef0123456789abcdef01234567";
    ObjectId id;
    ASSERT_TRUE(id.parseHex(sha1));
    EXPECT_EQ(id.byteLength(), 20u);
    EXPECT_EQ(id.hex(), sha1);
    EXPECT_EQ(id.shortHex(7), "0123456");

    const std::string sha256(64, 'a');
    ObjectId wide;
    ASSERT_TRUE(wide.parseHex(sha256));
    EXPECT_EQ(wide.byteLength(), 32u);
    EXPECT_EQ(wide.hex(), sha256);
}

TEST(ObjectId, RejectsMalformedInput) {
    ObjectId id;
    EXPECT_FALSE(id.parseHex(""));
    EXPECT_FALSE(id.parseHex("abc"));                 // too short
    EXPECT_FALSE(id.parseHex(std::string(39, 'a')));  // one short of SHA-1
    EXPECT_FALSE(id.parseHex(std::string(40, 'z')));  // not hex
    EXPECT_TRUE(id.isNull());
}

TEST(ObjectId, HashIsStableAcrossRuns) {
    // Lane colours derive from this hash, so a change would reshuffle every
    // branch colour and invalidate the graph golden tests. Pinning the value
    // makes that breakage impossible to introduce accidentally.
    const ObjectId id = ObjectId::fromHex("0123456789abcdef0123456789abcdef01234567");

    // FNV-1a over the 20 significant bytes. The literal is the contract: if this
    // ever changes, every branch colour changes with it.
    EXPECT_EQ(id.hash(), 0xd2798904d255dbbdULL);

    const ObjectId same = ObjectId::fromHex("0123456789abcdef0123456789abcdef01234567");
    EXPECT_EQ(id.hash(), same.hash());
    EXPECT_EQ(id, same);

    const ObjectId other = ObjectId::fromHex("0123456789abcdef0123456789abcdef01234568");
    EXPECT_NE(id.hash(), other.hash());
}

// --- error classification --------------------------------------------------

TEST(GitError, ClassifiesTheFailuresUsersActuallyHit) {
    struct Case {
        const char* stderrText;
        GitError::Code expected;
    };

    const Case cases[] = {
        {"error: Your local changes to the following files would be overwritten by checkout:",
         GitError::Code::DirtyWorkTree},
        {"fatal: Unable to create '/repo/.git/index.lock': File exists.", GitError::Code::LockHeld},
        {"CONFLICT (content): Merge conflict in src/main.cpp", GitError::Code::Conflict},
        {"! [rejected]        main -> main (non-fast-forward)", GitError::Code::NonFastForward},
        {"fatal: Authentication failed for 'https://example.invalid/repo.git/'",
         GitError::Code::Auth},
        {"Host key verification failed.", GitError::Code::HostKey},
        {"error: failed to push some refs: pre-receive hook declined",
         GitError::Code::HookRejected},
        {"fatal: not a git repository (or any of the parent directories): .git",
         GitError::Code::NotFound},
        {"error: unknown option `no-such-flag'", GitError::Code::Unsupported},
    };

    for (const Case& testCase : cases) {
        const GitError error = classifyGitStderr(testCase.stderrText, 128);
        EXPECT_EQ(error.code, testCase.expected) << testCase.stderrText;
        // The raw text is always preserved: the operation log shows it verbatim,
        // and a summary alone would make bug reports unactionable.
        EXPECT_EQ(error.detail, testCase.stderrText);
        EXPECT_FALSE(error.message.empty());
        EXPECT_EQ(error.exitCode, 128);
    }
}

TEST(GitError, FallsBackWithoutLosingStderr) {
    const GitError error = classifyGitStderr("something entirely unexpected", 1);
    EXPECT_EQ(error.code, GitError::Code::ProcessFailed);
    EXPECT_EQ(error.detail, "something entirely unexpected");
}

// --- Result ----------------------------------------------------------------

TEST(Result, CarriesValuesAndErrors) {
    GitResult<int> ok = 42;
    ASSERT_TRUE(ok);
    EXPECT_EQ(*ok, 42);

    GitResult<int> bad = fail(GitError::Code::NotFound, "missing");
    ASSERT_FALSE(bad);
    EXPECT_EQ(bad.error().code, GitError::Code::NotFound);
    EXPECT_EQ(bad.valueOr(7), 7);

    GitResult<void> voidOk;
    EXPECT_TRUE(voidOk);
    GitResult<void> voidBad = fail(GitError::Code::Cancelled, "stopped");
    ASSERT_FALSE(voidBad);
    EXPECT_EQ(voidBad.error().code, GitError::Code::Cancelled);
}

// --- cancellation ----------------------------------------------------------

TEST(CancellationToken, FiresCallbacksExactlyOnce) {
    CancellationSource source;
    CancellationToken token = source.token();
    EXPECT_FALSE(token.isCancelled());

    std::atomic_int calls{0};
    auto reg = token.onCancel([&calls] { ++calls; });

    source.cancel();
    source.cancel();  // Idempotent.

    EXPECT_TRUE(token.isCancelled());
    EXPECT_EQ(calls.load(), 1);
}

TEST(CancellationToken, RunsCallbackImmediatelyIfAlreadyCancelled) {
    // Without this, a callback registered just after cancellation would never
    // run, leaving a child process alive after the user pressed Cancel.
    CancellationSource source;
    source.cancel();

    std::atomic_bool ran{false};
    auto reg = source.token().onCancel([&ran] { ran = true; });
    EXPECT_TRUE(ran.load());
}

TEST(CancellationToken, UnregisteringABeforeCancelPreventsItFromFiring) {
    // This is what ProcessRunner::execute() relies on: a callback capturing
    // stack state that has already gone out of scope must never fire, even
    // if cancel() is called afterward on the same CancellationSource (e.g.
    // RepositorySession::cancelPendingReads() firing once for a whole
    // session's worth of already-finished reads).
    CancellationSource source;
    CancellationToken token = source.token();

    std::atomic_int calls{0};
    {
        auto reg = token.onCancel([&calls] { ++calls; });
        reg.reset();  // Explicit unregister -- the case a destructor also covers.
    }

    source.cancel();
    EXPECT_EQ(calls.load(), 0);
}

TEST(CancellationToken, RegistrationDestructorUnregisters) {
    CancellationSource source;
    CancellationToken token = source.token();

    std::atomic_int calls{0};
    {
        auto reg = token.onCancel([&calls] { ++calls; });
        // reg destructs here, at the end of this block, before cancel() runs.
    }

    source.cancel();
    EXPECT_EQ(calls.load(), 0);
}

TEST(CancellationToken, MovedRegistrationStillUnregisters) {
    CancellationSource source;
    CancellationToken token = source.token();

    std::atomic_int calls{0};
    auto reg = token.onCancel([&calls] { ++calls; });
    auto moved = std::move(reg);

    moved.reset();
    source.cancel();
    EXPECT_EQ(calls.load(), 0);
}

TEST(CancellationToken, SeveralRegistrationsAreIndependent) {
    // Unregistering one callback must not disturb another registered on the
    // same token -- the id-based removal has to target exactly one entry.
    CancellationSource source;
    CancellationToken token = source.token();

    std::atomic_int firstCalls{0};
    std::atomic_int secondCalls{0};
    auto first = token.onCancel([&firstCalls] { ++firstCalls; });
    auto second = token.onCancel([&secondCalls] { ++secondCalls; });

    first.reset();
    source.cancel();

    EXPECT_EQ(firstCalls.load(), 0);
    EXPECT_EQ(secondCalls.load(), 1);
}

// --- thread pool -----------------------------------------------------------

TEST(ThreadPool, RunsAllQueuedWork) {
    ThreadPool pool("test", 4);
    std::atomic_int total{0};
    for (int i = 0; i < 500; ++i) {
        pool.post([&total] { ++total; });
    }
    pool.drain();
    EXPECT_EQ(total.load(), 500);
}

TEST(ThreadPool, SurvivesAThrowingTask) {
    // A worker that lets an exception escape would otherwise terminate the whole
    // application while the user is only browsing history.
    ThreadPool pool("test", 2);
    std::atomic_int completed{0};

    pool.post([] { throw std::runtime_error("boom"); });
    pool.post([&completed] { ++completed; });
    pool.drain();

    EXPECT_EQ(completed.load(), 1);
}

TEST(ThreadPool, DefaultSizeLeavesRoomForTheUiThread) {
    const std::size_t size = ThreadPool::defaultThreadCount();
    EXPECT_GE(size, 2u);
    EXPECT_LE(size, 6u);
}

TEST(ThreadPool, CancelQueuedAndDrainDiscardsQueuedWorkButWaitsForTheActiveTask) {
    // This is exactly the shape MainWindow::closeRepository() relies on: cancel
    // the token(s) a running task carries, then call this so no queued lambda
    // capturing the about-to-be-destroyed RepositorySession ever runs, and
    // nothing is still touching it when the call returns.
    ThreadPool pool("test", 1);  // One worker: makes queue-vs-active deterministic.
    std::atomic_bool activeTaskStarted{false};
    std::atomic_bool activeTaskMayFinish{false};
    std::atomic_bool activeTaskFinished{false};
    std::atomic_int queuedTasksRun{0};

    pool.post([&] {
        activeTaskStarted.store(true);
        while (!activeTaskMayFinish.load()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
        activeTaskFinished.store(true);
    });

    // Wait until the pool has actually picked up the first task, so the
    // remaining posts land in the queue behind it (single worker) instead of
    // racing to start first.
    while (!activeTaskStarted.load()) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }

    for (int i = 0; i < 10; ++i) {
        pool.post([&queuedTasksRun] { ++queuedTasksRun; });
    }
    EXPECT_GT(pool.queueDepth(), 0u);

    // Let the active task finish shortly after cancelQueuedAndDrain() starts
    // waiting, from a second thread, so this actually exercises the "blocks
    // until currently-executing work finishes" half of the contract rather
    // than returning instantly because nothing was active.
    std::thread releaser([&] {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        activeTaskMayFinish.store(true);
    });

    pool.cancelQueuedAndDrain();
    releaser.join();

    EXPECT_TRUE(activeTaskFinished.load())
        << "must wait for the active task, not just clear the queue";
    EXPECT_EQ(queuedTasksRun.load(), 0) << "queued-but-not-started work must be discarded, not run";
    EXPECT_EQ(pool.queueDepth(), 0u);

    // The pool itself is still usable afterward -- cancelQueuedAndDrain() is
    // not a shutdown.
    std::atomic_int total{0};
    pool.post([&total] { ++total; });
    pool.drain();
    EXPECT_EQ(total.load(), 1);
}

// --- debouncer -------------------------------------------------------------

TEST(Debouncer, WaitsForTheQuietPeriod) {
    Debouncer debouncer(std::chrono::milliseconds(100));
    const auto start = Debouncer::Clock::now();

    debouncer.notifyEvent(start);
    EXPECT_FALSE(debouncer.shouldFire(start));
    EXPECT_FALSE(debouncer.shouldFire(start + std::chrono::milliseconds(50)));
    EXPECT_TRUE(debouncer.shouldFire(start + std::chrono::milliseconds(150)));
}

TEST(Debouncer, ABurstOfEventsProducesOneRun) {
    // A single checkout on a large tree emits thousands of events; each one must
    // not become a separate `git status`.
    Debouncer debouncer(std::chrono::milliseconds(100));
    const auto start = Debouncer::Clock::now();

    for (int i = 0; i < 1000; ++i) {
        debouncer.notifyEvent(start + std::chrono::milliseconds(i / 20));
    }
    EXPECT_TRUE(debouncer.shouldFire(start + std::chrono::milliseconds(500)));
    EXPECT_FALSE(debouncer.shouldFire(start + std::chrono::milliseconds(600)))
        << "only one run should start per burst";
}

TEST(Debouncer, CoalescesEventsArrivingMidRun) {
    Debouncer debouncer(std::chrono::milliseconds(10));
    const auto start = Debouncer::Clock::now();

    debouncer.notifyEvent(start);
    ASSERT_TRUE(debouncer.shouldFire(start + std::chrono::milliseconds(20)));
    EXPECT_TRUE(debouncer.isRunning());

    // Events during the run set a dirty bit rather than queueing more runs.
    debouncer.notifyEvent(start + std::chrono::milliseconds(25));
    EXPECT_FALSE(debouncer.shouldFire(start + std::chrono::milliseconds(30)));

    EXPECT_TRUE(debouncer.finish()) << "exactly one more run should follow";
    EXPECT_TRUE(debouncer.shouldFire(start + std::chrono::milliseconds(40)));
    EXPECT_FALSE(debouncer.finish()) << "and then no more";
}

// --- startup read gate -------------------------------------------------------
// Decision table for RepositorySession::refreshWorkingCopyStatusWhenIdle():
// holds back the speculative cold-scan on repo open until the history walk has
// something to show, without ever losing or duplicating the held request. See
// docs/reports/vscode-graph-performance.md, bottleneck #2.

TEST(StartupReadGate, HoldsTheFirstRequestWhileClosed) {
    StartupReadGate gate;
    EXPECT_FALSE(gate.isOpen());
    EXPECT_FALSE(gate.requestOrHold());
}

TEST(StartupReadGate, RepeatedRequestsWhileClosedStayCoalescedIntoOne) {
    // A burst of setSession()/resync calls before the graph paints must not
    // fan out into one scan per call once the gate opens.
    StartupReadGate gate;
    EXPECT_FALSE(gate.requestOrHold());
    EXPECT_FALSE(gate.requestOrHold());
    EXPECT_FALSE(gate.requestOrHold());

    EXPECT_TRUE(gate.release());
    EXPECT_TRUE(gate.isOpen());
}

TEST(StartupReadGate, ReleaseWithNoPendingRequestStillOpens) {
    // A repository with no commits at all publishes no chunk before the walk's
    // other terminal paths (error, cancel, fingerprint-skip) run -- the gate
    // must still open so the panel is never stuck empty.
    StartupReadGate gate;
    EXPECT_FALSE(gate.release());
    EXPECT_TRUE(gate.isOpen());
}

TEST(StartupReadGate, ReleaseIsIdempotent) {
    StartupReadGate gate;
    EXPECT_FALSE(gate.requestOrHold());
    EXPECT_TRUE(gate.release());
    EXPECT_FALSE(gate.release()) << "a second release must not re-run the held request";
}

TEST(StartupReadGate, OnceOpenEveryRequestRunsImmediately) {
    StartupReadGate gate;
    gate.release();
    ASSERT_TRUE(gate.isOpen());
    EXPECT_TRUE(gate.requestOrHold());
    EXPECT_TRUE(gate.requestOrHold());
}

// --- refresh coalescer -------------------------------------------------------
// Decision table for RepositorySession's refresh entry points
// (refreshRefs()/refreshHistory()/refreshRefsAndHistory()/setHistoryFilter()):
// merges a burst of requests into one for-each-ref load instead of spawning
// one per call. See docs/reports/vscode-graph-performance.md, bottleneck #6.
//
// Every dispatch (onTimeout() or fireNow()) is tagged with a Generation.
// finishRefresh()-equivalents (onFinished()) must pass back the generation
// they were dispatched with; a stale generation (superseded by a newer
// dispatch before this one reported back) is a safe no-op rather than
// touching state a newer, still-in-flight refresh now owns. This replaced an
// earlier design that tried to infer staleness from CancellationToken state
// instead -- code review found that approach missed startRefsOnly(), which
// uses a different, never-superseded cancellation source, so its report could
// still corrupt a concurrently fire-now()'d refresh's state.

TEST(RefreshCoalescer, ABurstOfRequestsInsideTheWindowYieldsOneFire) {
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    EXPECT_EQ(coalescer.request(true, true, GraphUpdateOrigin::Explicit, start),
              RefreshCoalescer::RefreshAction::Arm);
    EXPECT_EQ(coalescer.request(true, true, GraphUpdateOrigin::Explicit,
                                start + std::chrono::milliseconds(50)),
              RefreshCoalescer::RefreshAction::Arm)
        << "still idle -- no refresh has started firing yet";

    EXPECT_EQ(coalescer.onTimeout(start + std::chrono::milliseconds(100)), 0u)
        << "quiet period restarted by the second request, not yet elapsed";
    EXPECT_NE(coalescer.onTimeout(start + std::chrono::milliseconds(250)), 0u)
        << "150ms after the last request in the burst";
}

TEST(RefreshCoalescer, RefreshRefsFoldsIntoAPendingRefreshRefsAndHistoryAsTheUnion) {
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    coalescer.request(/*wantsRefs=*/true, /*wantsHistory=*/true, GraphUpdateOrigin::Explicit,
                      start);
    coalescer.request(/*wantsRefs=*/true, /*wantsHistory=*/false, GraphUpdateOrigin::Explicit,
                      start + std::chrono::milliseconds(10));

    ASSERT_NE(coalescer.onTimeout(start + std::chrono::milliseconds(200)), 0u);
    const RefreshCoalescer::PendingRefresh pending = coalescer.takePending();
    EXPECT_TRUE(pending.wantsRefs);
    EXPECT_TRUE(pending.wantsHistory)
        << "a refreshRefs()-only request must not drop a still-pending history refresh";
}

TEST(RefreshCoalescer, ARequestArrivingWhileRunningFoldsAndIsDeliveredByOnFinished) {
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    coalescer.request(true, true, GraphUpdateOrigin::Explicit, start);
    const RefreshCoalescer::Generation generation =
        coalescer.onTimeout(start + std::chrono::milliseconds(200));
    ASSERT_NE(generation, 0u);
    coalescer.takePending();

    EXPECT_EQ(coalescer.request(true, false, GraphUpdateOrigin::Explicit,
                                start + std::chrono::milliseconds(210)),
              RefreshCoalescer::RefreshAction::Fold)
        << "a refresh is already running -- the timer must not be re-armed";

    EXPECT_TRUE(coalescer.onFinished(generation)) << "exactly one more run should follow";
    const RefreshCoalescer::PendingRefresh pending = coalescer.takePending();
    EXPECT_TRUE(pending.wantsRefs);
    EXPECT_FALSE(pending.wantsHistory);
}

TEST(RefreshCoalescer, OnFinishedWithNothingFoldedReturnsFalse) {
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    coalescer.request(true, true, GraphUpdateOrigin::Explicit, start);
    const RefreshCoalescer::Generation generation =
        coalescer.onTimeout(start + std::chrono::milliseconds(200));
    ASSERT_NE(generation, 0u);
    coalescer.takePending();

    EXPECT_FALSE(coalescer.onFinished(generation))
        << "no request arrived while running -- nothing to redo";
}

TEST(RefreshCoalescer, OnFinishedWithAStaleGenerationIsANoOp) {
    // The core of the fix: a walk whose report arrives after a newer
    // dispatch has already superseded it (e.g. setHistoryFilter()'s
    // fireNow() racing an in-flight startRefsOnly() walk, which is never
    // itself cancelled -- see the class doc comment) must not be able to
    // corrupt state the newer dispatch now owns.
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    coalescer.request(true, true, GraphUpdateOrigin::Explicit, start);
    const RefreshCoalescer::Generation staleGeneration =
        coalescer.onTimeout(start + std::chrono::milliseconds(200));
    ASSERT_NE(staleGeneration, 0u);

    const RefreshCoalescer::Generation currentGeneration = coalescer.fireNow(
        false, true, GraphUpdateOrigin::Explicit, start + std::chrono::milliseconds(210));
    ASSERT_NE(currentGeneration, staleGeneration);

    EXPECT_FALSE(coalescer.onFinished(staleGeneration))
        << "the stale report must not be able to end the newer generation's run";

    // A request arriving now must still correctly Fold against the newer
    // generation, proving its running_ state survived the stale report.
    EXPECT_EQ(coalescer.request(true, false, GraphUpdateOrigin::Explicit,
                                start + std::chrono::milliseconds(220)),
              RefreshCoalescer::RefreshAction::Fold);
    EXPECT_TRUE(coalescer.onFinished(currentGeneration))
        << "the current generation's own report still ends its run and delivers the fold";
}

TEST(RefreshCoalescer, ResetClearsPendingRunningAndDirtyState) {
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    coalescer.request(true, true, GraphUpdateOrigin::Explicit, start);
    const RefreshCoalescer::Generation generation =
        coalescer.onTimeout(start + std::chrono::milliseconds(200));
    ASSERT_NE(generation, 0u);
    // Folds while running, which would otherwise leave a dirty follow-up owed.
    coalescer.request(true, false, GraphUpdateOrigin::Explicit,
                      start + std::chrono::milliseconds(210));

    coalescer.reset();

    EXPECT_FALSE(coalescer.onFinished(generation))
        << "reset must drop the fold -- a torn-down session cannot leave one wedged";
    EXPECT_EQ(coalescer.request(true, true, GraphUpdateOrigin::Explicit,
                                start + std::chrono::milliseconds(220)),
              RefreshCoalescer::RefreshAction::Arm)
        << "reset must also clear running_, or every request after teardown would fold forever";
}

TEST(RefreshCoalescer, ExplicitOutranksAutoFetchResyncInTheMerge) {
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    coalescer.request(true, true, GraphUpdateOrigin::AutoFetchResync, start);
    coalescer.request(true, false, GraphUpdateOrigin::Explicit,
                      start + std::chrono::milliseconds(10));

    ASSERT_NE(coalescer.onTimeout(start + std::chrono::milliseconds(200)), 0u);
    EXPECT_EQ(coalescer.takePending().origin, GraphUpdateOrigin::Explicit)
        << "a real user action folded into a silent auto-fetch window must still log as Explicit";
}

TEST(RefreshCoalescer, TakePendingClearsTheBatchForTheNextWindow) {
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    coalescer.request(true, true, GraphUpdateOrigin::Explicit, start);
    const RefreshCoalescer::Generation firstGeneration =
        coalescer.onTimeout(start + std::chrono::milliseconds(200));
    ASSERT_NE(firstGeneration, 0u);
    coalescer.takePending();
    ASSERT_FALSE(coalescer.onFinished(firstGeneration));

    // A fresh window after the run finished must start from an empty batch,
    // not still report the previous window's flags.
    coalescer.request(false, true, GraphUpdateOrigin::AutoFetchResync,
                      start + std::chrono::milliseconds(400));
    ASSERT_NE(coalescer.onTimeout(start + std::chrono::milliseconds(600)), 0u);
    const RefreshCoalescer::PendingRefresh pending = coalescer.takePending();
    EXPECT_FALSE(pending.wantsRefs);
    EXPECT_TRUE(pending.wantsHistory);
    EXPECT_EQ(pending.origin, GraphUpdateOrigin::AutoFetchResync);
}

TEST(RefreshCoalescer, FireNowMarksRunningSoALaterRequestFoldsInstead) {
    // RepositorySession::setHistoryFilter() bypasses the delay window (a
    // filter change must be seen immediately) but must still occupy the
    // coalescer the same way a real fire would -- otherwise a request
    // arriving during the filter's own walk would Arm a second, independent
    // walk and cancel the filter's walk out from under it.
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    coalescer.fireNow(false, true, GraphUpdateOrigin::Explicit, start);

    EXPECT_EQ(coalescer.request(true, false, GraphUpdateOrigin::Explicit,
                                start + std::chrono::milliseconds(10)),
              RefreshCoalescer::RefreshAction::Fold);
}

TEST(RefreshCoalescer, ARequestDuringAnImmediateFireIsDeliveredByOnFinished) {
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    const RefreshCoalescer::Generation generation =
        coalescer.fireNow(false, true, GraphUpdateOrigin::Explicit, start);
    coalescer.request(true, false, GraphUpdateOrigin::Explicit,
                      start + std::chrono::milliseconds(10));

    EXPECT_TRUE(coalescer.onFinished(generation))
        << "the folded request must run once the fire completes";
    const RefreshCoalescer::PendingRefresh pending = coalescer.takePending();
    EXPECT_TRUE(pending.wantsRefs);
    EXPECT_FALSE(pending.wantsHistory);
}

TEST(RefreshCoalescer, FireNowWhileIdleFiresImmediatelyWithItsOwnWant) {
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    const RefreshCoalescer::Generation generation =
        coalescer.fireNow(true, true, GraphUpdateOrigin::Explicit, start);
    ASSERT_NE(generation, 0u);

    const RefreshCoalescer::PendingRefresh pending = coalescer.takePending();
    EXPECT_TRUE(pending.wantsRefs);
    EXPECT_TRUE(pending.wantsHistory);
    EXPECT_EQ(pending.origin, GraphUpdateOrigin::Explicit);
    EXPECT_FALSE(coalescer.onFinished(generation))
        << "nothing folded in after an idle immediate fire";
}

TEST(RefreshCoalescer, FireNowMergesRatherThanDiscardsAnyAlreadyPendingBatch) {
    // The other half of the fix: setHistoryFilter() must not silently drop a
    // refreshRefs() that was already armed (or folded into an in-flight run)
    // when the filter change arrives -- fireNow() absorbs it into the
    // immediate fire's own batch instead of discarding it.
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    coalescer.request(/*wantsRefs=*/true, /*wantsHistory=*/false,
                      GraphUpdateOrigin::AutoFetchResync, start);
    const RefreshCoalescer::Generation generation = coalescer.fireNow(
        /*wantsRefs=*/false, /*wantsHistory=*/true, GraphUpdateOrigin::Explicit,
        start + std::chrono::milliseconds(5));

    const RefreshCoalescer::PendingRefresh pending = coalescer.takePending();
    EXPECT_TRUE(pending.wantsRefs) << "the already-pending refreshRefs() must survive the merge";
    EXPECT_TRUE(pending.wantsHistory) << "the filter's own history want must also be present";
    EXPECT_EQ(pending.origin, GraphUpdateOrigin::Explicit)
        << "the filter's Explicit origin must win the merge";
    EXPECT_FALSE(coalescer.onFinished(generation))
        << "nothing new folded in after the merge -- the absorbed batch already left via "
           "takePending()";
}

TEST(RefreshCoalescer, FireNowWhileAlreadyRunningSupersedesTheOlderGeneration) {
    RefreshCoalescer coalescer;
    const auto start = RefreshCoalescer::Clock::now();

    coalescer.request(true, true, GraphUpdateOrigin::Explicit, start);
    const RefreshCoalescer::Generation olderGeneration =
        coalescer.onTimeout(start + std::chrono::milliseconds(200));
    ASSERT_NE(olderGeneration, 0u);
    coalescer.takePending();

    const RefreshCoalescer::Generation newerGeneration = coalescer.fireNow(
        false, true, GraphUpdateOrigin::Explicit, start + std::chrono::milliseconds(210));
    EXPECT_NE(newerGeneration, olderGeneration);

    EXPECT_FALSE(coalescer.onFinished(olderGeneration))
        << "the superseded generation's report must be ignored, not clear running_ for the "
           "newer generation that's actually in flight";

    // A request arriving now correctly folds against the newer generation --
    // proof running_ survived the stale report above.
    EXPECT_EQ(coalescer.request(true, false, GraphUpdateOrigin::Explicit,
                                start + std::chrono::milliseconds(220)),
              RefreshCoalescer::RefreshAction::Fold);
    EXPECT_TRUE(coalescer.onFinished(newerGeneration))
        << "the newer generation's own report correctly ends its run and delivers the fold";
}

// --- git version detection -------------------------------------------------

TEST(GitVersion, ParsesVendorSuffixedVersions) {
    EXPECT_EQ(GitVersion::parse("git version 2.43.0").minor, 43);
    EXPECT_EQ(GitVersion::parse("git version 2.39.3 (Apple Git-146)").patch, 3);
    EXPECT_EQ(GitVersion::parse("git version 2.45.1.windows.1").minor, 45);

    const GitVersion version = GitVersion::parse("git version 2.30.2");
    EXPECT_TRUE(version >= GitInstallation::minimumSupported());
    EXPECT_FALSE(GitVersion::parse("git version 2.29.0") >= GitInstallation::minimumSupported());
}

TEST(GitInstallation, WarnsAboutMissingCapabilities) {
    // Because the backend is CLI-only, the user's git version is a hard feature
    // boundary. Surfacing it beats letting commands fail mysteriously later.
    GitInstallation old;
    old.executable = "/usr/bin/git";
    old.version = {2, 31, 0};
    EXPECT_TRUE(old.isUsable());
    EXPECT_FALSE(old.warnings().empty());

    GitInstallation modern;
    modern.executable = "/usr/bin/git";
    modern.version = {2, 45, 0};
    modern.capabilities.fsMonitor = true;
    modern.capabilities.mergeTreeWriteTree = true;
    modern.capabilities.changedPathBloom = true;
    EXPECT_TRUE(modern.warnings().empty());
}

// --- rev-list parsing ------------------------------------------------------

TEST(HistoryProvider, ParsesTimestampParentsAndOid) {
    const auto record = HistoryProvider::parseRevListLine(
        "1699999999 0123456789abcdef0123456789abcdef01234567 "
        "1111111111111111111111111111111111111111 "
        "2222222222222222222222222222222222222222");

    ASSERT_TRUE(record.valid);
    EXPECT_EQ(record.commitTime, 1699999999u);
    EXPECT_EQ(record.oid.hex(), "0123456789abcdef0123456789abcdef01234567");
    ASSERT_EQ(record.parents.size(), 2u);
    EXPECT_EQ(record.parents[0].hex(), std::string(40, '1'));
}

TEST(HistoryProvider, ParsesARootCommitWithNoParents) {
    const auto record = HistoryProvider::parseRevListLine("1000000000 " + std::string(40, 'a'));
    ASSERT_TRUE(record.valid);
    EXPECT_TRUE(record.parents.empty());
}

TEST(HistoryProvider, RejectsMalformedRecordsWithoutThrowing) {
    // Malformed rows are skipped, not fatal: one unparseable record must not
    // abandon the entire history walk.
    EXPECT_FALSE(HistoryProvider::parseRevListLine("").valid);
    EXPECT_FALSE(HistoryProvider::parseRevListLine("not-a-number abc").valid);
    EXPECT_FALSE(HistoryProvider::parseRevListLine("1699999999 tooshort").valid);
    EXPECT_FALSE(HistoryProvider::parseRevListLine("1699999999").valid);
}

TEST(HistoryQuery, UsesTopoOrderAndSeedsTipsBeforeAll) {
    HistoryQuery query;
    query.seedRefs = {"refs/heads/main"};
    const auto args = query.toRevListArgs();

    ASSERT_FALSE(args.empty());
    EXPECT_EQ(args[0], "rev-list");
    EXPECT_NE(std::find(args.begin(), args.end(), "--topo-order"), args.end())
        << "date order would interleave branches and break lane continuity";
    EXPECT_NE(std::find(args.begin(), args.end(), "--parents"), args.end());
    EXPECT_NE(std::find(args.begin(), args.end(), "--timestamp"), args.end());

    // The seed tip must precede --all: the graph builder gives lane 0 to the
    // first tip it sees, which is how the trunk stays leftmost.
    const auto tipAt = std::find(args.begin(), args.end(), "refs/heads/main");
    const auto allAt = std::find(args.begin(), args.end(), "--all");
    ASSERT_NE(tipAt, args.end());
    ASSERT_NE(allAt, args.end());
    EXPECT_LT(tipAt - args.begin(), allAt - args.begin());
}

TEST(HistoryQuery, NarrowsToIncludeRefsWithoutAll) {
    // includeRefs (the graph branch filter) must actually narrow the walk,
    // not just reorder --all's tips -- --all must be absent entirely.
    HistoryQuery query;
    query.seedRefs = {"refs/heads/main"};  // Must be ignored once includeRefs is set.
    query.includeRefs = {"refs/heads/feature-a", "refs/heads/feature-b"};
    const auto args = query.toRevListArgs();

    EXPECT_EQ(std::find(args.begin(), args.end(), "--all"), args.end());
    EXPECT_EQ(std::find(args.begin(), args.end(), "refs/heads/main"), args.end());
    EXPECT_NE(std::find(args.begin(), args.end(), "refs/heads/feature-a"), args.end());
    EXPECT_NE(std::find(args.begin(), args.end(), "refs/heads/feature-b"), args.end());
}

TEST(HistoryQuery, PushesFilteringDownIntoGit) {
    HistoryQuery query;
    query.author = "someone";
    query.grep = "fix";
    query.pathFilter = "src/main.cpp";
    query.maxCount = 500;

    const auto args = query.toRevListArgs();
    EXPECT_NE(std::find(args.begin(), args.end(), "--author=someone"), args.end());
    EXPECT_NE(std::find(args.begin(), args.end(), "--grep=fix"), args.end());
    EXPECT_NE(std::find(args.begin(), args.end(), "--max-count=500"), args.end());
    // Path filtering must come after a "--" separator or a path that looks like a
    // ref would be misread.
    const auto separator = std::find(args.begin(), args.end(), "--");
    const auto path = std::find(args.begin(), args.end(), "src/main.cpp");
    ASSERT_NE(separator, args.end());
    ASSERT_NE(path, args.end());
    EXPECT_LT(separator - args.begin(), path - args.begin());
}

// --- GraphUpdateOrigin -------------------------------------------------------
// See docs/reports/vscode-graph-performance.md, bottleneck #3: a
// maybeAutoFetch()-triggered resync used to be indistinguishable from the
// initial walk just running slowly. toString() is what both the
// RepositorySession log line and any future test/gate read to tell them apart.

TEST(GraphUpdateOrigin, ExplicitDescribesAnyDirectWalk) {
    EXPECT_EQ(toString(GraphUpdateOrigin::Explicit), "explicit");
}

TEST(GraphUpdateOrigin, AutoFetchResyncDescribesTheBackgroundResync) {
    EXPECT_EQ(toString(GraphUpdateOrigin::AutoFetchResync), "auto-fetch resync");
}

// --- walk timing -------------------------------------------------------------
// Formats the bridge-boundary timing line RepositorySession emits per history
// refresh when GBM_TIMING=1. See docs/reports/vscode-graph-performance.md,
// bottleneck #4: the Qt/bridge overhead was undocumented and volatile (62ms
// core-only vs. 83-1069ms in the real app for the same walk) because nothing
// recorded it. RepositorySession itself has no test harness, so the parsing
// and formatting logic lives here, pure and Qt-free.

TEST(WalkTimingEnabled, OnlyTheLiteralOneTurnsItOn) {
    EXPECT_FALSE(walkTimingEnabledForValue(nullptr));
    EXPECT_FALSE(walkTimingEnabledForValue(""));
    EXPECT_FALSE(walkTimingEnabledForValue("0"));
    EXPECT_FALSE(walkTimingEnabledForValue("true"));
    EXPECT_FALSE(walkTimingEnabledForValue("yes"));
    EXPECT_TRUE(walkTimingEnabledForValue("1"));
}

TEST(WalkOutcomeToString, LabelsEveryOutcome) {
    EXPECT_EQ(toString(WalkOutcome::FirstChunk), "first-chunk");
    EXPECT_EQ(toString(WalkOutcome::Complete), "complete");
    EXPECT_EQ(toString(WalkOutcome::Skipped), "skipped");
    EXPECT_EQ(toString(WalkOutcome::Failed), "failed");
    EXPECT_EQ(toString(WalkOutcome::Cancelled), "cancelled");
}

TEST(FormatWalkTiming, RendersEverySegmentWhenTheFullChainWasReached) {
    WalkMarks marks;
    marks.firedMs = 1;
    marks.workerStartedMs = 3;
    marks.refsLoadedMs = 44;
    marks.chunkBuiltMs = 106;
    marks.chunkDeliveredMs = 114;
    marks.uiAppliedMs = 133;

    const std::string line = formatWalkTiming("explicit", WalkOutcome::FirstChunk, 256, marks);

    EXPECT_EQ(line,
              "gbm-timing walk origin=explicit outcome=first-chunk rows=256 "
              "coalesce_ms=1 queue_ms=2 refs_ms=41 walk_ms=62 hop_ms=8 apply_ms=19 total_ms=133");
}

TEST(FormatWalkTiming, PrintsADashForEverySegmentThatNeverReachedItsEndMark) {
    // The fingerprint fast path (RepositorySession::walkHistoryWithRefs())
    // republishes the previous graph without running rev-list at all -- no
    // chunk is ever built, so walk_ms/hop_ms must not read as a suspiciously
    // fast zero.
    WalkMarks marks;
    marks.firedMs = 1;
    marks.workerStartedMs = 2;
    marks.refsLoadedMs = 9;
    // chunkBuiltMs, chunkDeliveredMs, uiAppliedMs stay unreached (-1).

    const std::string line = formatWalkTiming("explicit", WalkOutcome::Skipped, 4000, marks);

    EXPECT_EQ(line,
              "gbm-timing walk origin=explicit outcome=skipped rows=4000 "
              "coalesce_ms=1 queue_ms=1 refs_ms=7 walk_ms=- hop_ms=- apply_ms=- total_ms=9");
}

TEST(FormatWalkTiming, TotalMsIsTheLastMarkReachedNotAlwaysUiApplied) {
    // Failed/cancelled/skipped refreshes never reach MainWindow, so there is
    // no UI-apply leg -- total_ms must fall back to whatever mark the refresh
    // actually got to rather than reading as "-" or as a misleadingly small
    // number.
    WalkMarks marks;
    marks.firedMs = 0;
    marks.workerStartedMs = 1;
    marks.refsLoadedMs = 5;
    // The for-each-ref load itself failed, so nothing past refsLoadedMs runs.

    const std::string line = formatWalkTiming("explicit", WalkOutcome::Failed, 0, marks);

    EXPECT_EQ(line,
              "gbm-timing walk origin=explicit outcome=failed rows=0 "
              "coalesce_ms=0 queue_ms=1 refs_ms=4 walk_ms=- hop_ms=- apply_ms=- total_ms=5");
}

TEST(FormatWalkTiming, EmitsAutoFetchResyncOriginVerbatim) {
    // origin is threaded straight through from GraphUpdateOrigin::toString()
    // (see the GraphUpdateOrigin section above) -- this only checks
    // formatWalkTiming doesn't reformat or truncate it.
    WalkMarks marks;
    marks.firedMs = 0;
    marks.workerStartedMs = 1;
    marks.refsLoadedMs = 2;
    marks.chunkBuiltMs = 3;
    marks.chunkDeliveredMs = 4;
    marks.uiAppliedMs = 5;

    const std::string line =
        formatWalkTiming("auto-fetch resync", WalkOutcome::Complete, 12000, marks);

    EXPECT_EQ(line,
              "gbm-timing walk origin=auto-fetch resync outcome=complete rows=12000 "
              "coalesce_ms=0 queue_ms=1 refs_ms=1 walk_ms=1 hop_ms=1 apply_ms=1 total_ms=5");
}

TEST(FormatWalkTiming, CoalesceMsReflectsTheRefreshCoalescerWindowWait) {
    // See docs/reports/vscode-graph-performance.md bottleneck #6: with a
    // coalescing window in front of the walk, queue_ms alone would silently
    // absorb the debounce delay -- coalesce_ms keeps it labelled instead.
    WalkMarks marks;
    marks.firedMs = 150;
    marks.workerStartedMs = 152;
    // Nothing past workerStartedMs was reached.

    const std::string line = formatWalkTiming("explicit", WalkOutcome::Failed, 0, marks);

    EXPECT_EQ(line,
              "gbm-timing walk origin=explicit outcome=failed rows=0 "
              "coalesce_ms=150 queue_ms=2 refs_ms=- walk_ms=- hop_ms=- apply_ms=- total_ms=152");
}

TEST(FormatWalkTiming, PrintsADashForCoalesceAndQueueWhenFiredWasNeverReached) {
    // A refresh cancelled before RefreshCoalescer ever fired it (superseded
    // while still folded) never marks firedMs -- must read as absent, not as
    // an implausibly instant 0.
    WalkMarks marks;

    const std::string line = formatWalkTiming("explicit", WalkOutcome::Cancelled, 0, marks);

    EXPECT_EQ(line,
              "gbm-timing walk origin=explicit outcome=cancelled rows=0 "
              "coalesce_ms=- queue_ms=- refs_ms=- walk_ms=- hop_ms=- apply_ms=- total_ms=-");
}

TEST(FormatWalkTiming, TotalMsFallsBackToFiredMsWhenNothingElseWasReached) {
    WalkMarks marks;
    marks.firedMs = 7;
    // Every later mark stays unreached (-1).

    const std::string line = formatWalkTiming("explicit", WalkOutcome::Cancelled, 0, marks);

    EXPECT_EQ(line,
              "gbm-timing walk origin=explicit outcome=cancelled rows=0 "
              "coalesce_ms=7 queue_ms=- refs_ms=- walk_ms=- hop_ms=- apply_ms=- total_ms=7");
}

// --- commit object parsing -------------------------------------------------

TEST(CommitMeta, ParsesARawCommitObject) {
    const std::string raw =
        "tree 1111111111111111111111111111111111111111\n"
        "parent 2222222222222222222222222222222222222222\n"
        "parent 3333333333333333333333333333333333333333\n"
        "author Ada Lovelace <ada@example.invalid> 1699999999 +0200\n"
        "committer Ada Lovelace <ada@example.invalid> 1700000000 -0700\n"
        "\n"
        "Fix the thing\n"
        "\n"
        "A longer explanation.\n";

    const ObjectId oid = ObjectId::fromHex(std::string(40, 'f'));
    const CommitMeta meta = CommitMeta::parseRawCommit(oid, raw);

    EXPECT_EQ(meta.tree.hex(), std::string(40, '1'));
    ASSERT_EQ(meta.parents.size(), 2u);
    EXPECT_EQ(meta.author.name, "Ada Lovelace");
    EXPECT_EQ(meta.author.email, "ada@example.invalid");
    EXPECT_EQ(meta.author.when, 1699999999);
    EXPECT_EQ(meta.author.tzOffsetMinutes, 120);
    EXPECT_EQ(meta.committer.tzOffsetMinutes, -7 * 60);
    EXPECT_EQ(meta.subject, "Fix the thing");
    EXPECT_EQ(meta.body, "A longer explanation.");
}

TEST(CommitMeta, SkipsUnknownAndMultiLineHeaders) {
    // gpgsig spans many continuation lines. Treating an unfamiliar header as an
    // error would break history browsing on plenty of real repositories.
    const std::string raw =
        "tree 1111111111111111111111111111111111111111\n"
        "author A <a@example.invalid> 1 +0000\n"
        "committer A <a@example.invalid> 1 +0000\n"
        "gpgsig -----BEGIN PGP SIGNATURE-----\n"
        " \n"
        " iQEcBAABCgAGBQJ...\n"
        " -----END PGP SIGNATURE-----\n"
        "encoding ISO-8859-1\n"
        "mergetag object 4444444444444444444444444444444444444444\n"
        " type commit\n"
        "\n"
        "Signed commit\n";

    const CommitMeta meta =
        CommitMeta::parseRawCommit(ObjectId::fromHex(std::string(40, 'a')), raw);
    EXPECT_TRUE(meta.signedCommit);
    EXPECT_EQ(meta.subject, "Signed commit");
    EXPECT_EQ(meta.author.name, "A");
}

TEST(Signature, HandlesNamesContainingAngleBrackets) {
    // Scanning for the email from the left would truncate this name.
    const Signature signature = parseSignature("Weird <Name> <real@example.invalid> 100 +0000");
    EXPECT_EQ(signature.email, "real@example.invalid");
    EXPECT_EQ(signature.name, "Weird <Name>");
    EXPECT_EQ(signature.when, 100);
}

// --- ref name validation ---------------------------------------------------

TEST(RefStore, ValidatesBranchNamesBeforeSpawningGit) {
    EXPECT_TRUE(RefStore::isValidBranchName("feature/thing"));
    EXPECT_TRUE(RefStore::isValidBranchName("release-1.2"));

    EXPECT_FALSE(RefStore::isValidBranchName(""));
    EXPECT_FALSE(RefStore::isValidBranchName(".hidden"));
    EXPECT_FALSE(RefStore::isValidBranchName("trailing/"));
    EXPECT_FALSE(RefStore::isValidBranchName("with space"));
    EXPECT_FALSE(RefStore::isValidBranchName("a..b"));
    EXPECT_FALSE(RefStore::isValidBranchName("caret^"));
    EXPECT_FALSE(RefStore::isValidBranchName("colon:name"));
    EXPECT_FALSE(RefStore::isValidBranchName("star*"));
    EXPECT_FALSE(RefStore::isValidBranchName("thing.lock"));
    EXPECT_FALSE(RefStore::isValidBranchName("at@{brace"));
}

// --- repository paths ------------------------------------------------------

TEST(RepoPaths, DistinguishesLinkedWorktreesFromNormalCheckouts) {
    // Getting this wrong means reading another worktree's HEAD, so the split
    // between per-worktree and shared state is asserted directly.
    const RepoPaths normal("/repo", "/repo/.git", "/repo/.git");
    EXPECT_FALSE(normal.isLinkedWorktree());
    EXPECT_FALSE(normal.isBare());
    EXPECT_EQ(normal.commandDir(), std::filesystem::path("/repo"));
    EXPECT_EQ(normal.displayName(), "repo");

    const RepoPaths worktree("/wt", "/repo/.git/worktrees/wt", "/repo/.git");
    EXPECT_TRUE(worktree.isLinkedWorktree());
    // HEAD and index are private to the worktree...
    EXPECT_EQ(worktree.headFile(), std::filesystem::path("/repo/.git/worktrees/wt/HEAD"));
    EXPECT_EQ(worktree.indexFile(), std::filesystem::path("/repo/.git/worktrees/wt/index"));
    // ...while objects and packed-refs are shared.
    EXPECT_EQ(worktree.objectsDir(), std::filesystem::path("/repo/.git/objects"));
    EXPECT_EQ(worktree.packedRefsFile(), std::filesystem::path("/repo/.git/packed-refs"));

    const RepoPaths bare({}, "/mirror.git", "/mirror.git");
    EXPECT_TRUE(bare.isBare());
    EXPECT_EQ(bare.commandDir(), std::filesystem::path("/mirror.git"));
}

TEST(RepoPaths, DerivesADisplayNameFromTheParentOfDotGit) {
    const RepoPaths paths("", "/some/project/.git", "/some/project/.git");
    EXPECT_EQ(paths.displayName(), "project");
}

// --- M3: askpass handshake --------------------------------------------------

TEST(Askpass, WireAddsTheAskpassEnvironmentOverrides) {
    GitCommand command;
    askpass::wire(command, "/tmp/gbm-askpass-test-dir");

    auto find = [&command](const std::string& key) -> std::optional<std::string> {
        for (const auto& [k, v] : command.envOverrides) {
            if (k == key) {
                return v;
            }
        }
        return std::nullopt;
    };

    EXPECT_TRUE(find("GIT_ASKPASS").has_value());
    EXPECT_TRUE(find("SSH_ASKPASS").has_value());
    EXPECT_EQ(find("GBM_ASKPASS_MODE"), "1");
    EXPECT_EQ(find("GBM_ASKPASS_DIR"), "/tmp/gbm-askpass-test-dir");
}

TEST(Askpass, WireIsANoOpWithAnEmptyDirectory) {
    GitCommand command;
    askpass::wire(command, {});
    EXPECT_TRUE(command.envOverrides.empty())
        << "a command with no askpass directory must behave exactly as it did before M3";
}

TEST(Askpass, ClientWritesTheRequestAndFailsPromptlyOnCancel) {
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());

    std::thread responder([&dir] {
        // Give the client time to write its request before reacting to it.
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        std::ofstream cancel(dir / "cancel");
        cancel << "x";
    });

    const int exitCode = askpass::runClientForDir(dir, "Password for 'https://example.invalid': ");
    responder.join();

    EXPECT_EQ(exitCode, 1);

    // Scoped so the handle is closed before remove_all runs below: Windows
    // refuses to delete a file (or its parent directory) while anything still
    // has it open.
    {
        std::ifstream request(dir / "request");
        std::string contents((std::istreambuf_iterator<char>(request)),
                             std::istreambuf_iterator<char>());
        EXPECT_EQ(contents, "Password for 'https://example.invalid': ");
    }

    std::filesystem::remove_all(dir);
}

TEST(Askpass, ClientPrintsTheAnswerOnceAResponseArrives) {
    const auto dir = askpass::makeRequestDir();
    ASSERT_FALSE(dir.empty());

    std::thread responder([&dir] {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        std::ofstream response(dir / "response", std::ios::binary);
        response << "s3cret";
    });

    const int exitCode = askpass::runClientForDir(dir, "Password: ");
    responder.join();

    EXPECT_EQ(exitCode, 0);
    // The response file is consumed, matching a real one-shot credential prompt.
    EXPECT_FALSE(std::filesystem::exists(dir / "response"));

    std::filesystem::remove_all(dir);
}

}  // namespace
}  // namespace gbm
