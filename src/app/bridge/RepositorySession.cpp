#include "app/bridge/RepositorySession.h"

#include "core/base/Logging.h"
#include "core/git/AskpassHelper.h"

#include <QLatin1Char>
#include <QMetaObject>
#include <QMetaType>
#include <QSettings>
#include <QString>
#include <QTimer>

#include <cstdint>
#include <utility>

namespace gbm {

namespace {

/// Mirrors RepositoryPage::kDefaultMaxGraphRows / settingsKeyPrefix() exactly
/// -- both read the same `repositoryPerf/<path>/*` QSettings keys, so the two
/// must agree on the key format. Duplicated rather than shared because
/// RepositoryPage (a UI widget) is not something this bridge-layer class
/// should depend on; if the key format ever changes it needs updating in
/// both places.
constexpr int kDefaultMaxGraphRows = 5000;

QString performanceSettingsKeyPrefix(const RepoPaths& paths) {
    QString path = QString::fromStdString(paths.commandDir().string());
    path.replace(QLatin1Char('/'), QLatin1Char('_'));
    path.replace(QLatin1Char('\\'), QLatin1Char('_'));
    path.replace(QLatin1Char(':'), QLatin1Char('_'));
    return QStringLiteral("repositoryPerf/%1/").arg(path);
}

/// 0 (no cap) when large-repository mode is off or unset for this repo.
std::uint32_t maxGraphRowsSetting(const RepoPaths& paths) {
    const QString prefix = performanceSettingsKeyPrefix(paths);
    if (prefix.isEmpty()) {
        return 0;
    }
    QSettings settings;
    const bool largeRepoMode =
        settings.value(prefix + QStringLiteral("largeRepoMode"), false).toBool();
    if (!largeRepoMode) {
        return 0;
    }
    const int maxRows =
        settings.value(prefix + QStringLiteral("maxGraphRows"), kDefaultMaxGraphRows).toInt();
    return maxRows > 0 ? static_cast<std::uint32_t>(maxRows) : 0;
}

/// Mirrors RepositoryPage's "Sync" card checkbox; same key format note as
/// maxGraphRowsSetting above. Defaults to on.
bool autoFetchOnOpenSetting(const RepoPaths& paths) {
    const QString prefix = performanceSettingsKeyPrefix(paths);
    if (prefix.isEmpty()) {
        return true;
    }
    QSettings settings;
    return settings.value(prefix + QStringLiteral("autoFetchOnOpen"), true).toBool();
}

/// Mirrors RepositoryPage's "Keep commit-graph up to date" checkbox, same key
/// format note as above. Defaults to Unset (never written before), which is
/// the only state shouldOfferCommitGraph() treats as "still worth asking".
CommitGraphPreference commitGraphPreferenceSetting(const RepoPaths& paths) {
    const QString prefix = performanceSettingsKeyPrefix(paths);
    if (prefix.isEmpty()) {
        return CommitGraphPreference::Unset;
    }
    QSettings settings;
    const QString value =
        settings.value(prefix + QStringLiteral("commitGraph"), QStringLiteral("unset")).toString();
    if (value == QStringLiteral("enabled")) {
        return CommitGraphPreference::Enabled;
    }
    if (value == QStringLiteral("declined")) {
        return CommitGraphPreference::Declined;
    }
    return CommitGraphPreference::Unset;
}

std::uint64_t combineHash(std::uint64_t seed, std::uint64_t value) {
    // boost::hash_combine's mixing constant/shifts; good enough for a cache
    // key, no cryptographic properties needed.
    seed ^= value + 0x9e3779b97f4a7c15ULL + (seed << 6) + (seed >> 2);
    return seed;
}

/// A cheap stand-in for "did anything the history walk depends on change".
/// Folds HEAD's target plus every ref's name and target oid, so any branch/
/// tag move, create, or delete changes the fingerprint -- exactly the set of
/// events that can change what `git rev-list` would produce.
std::uint64_t fingerprintRefs(const RefSnapshot& refs) {
    std::uint64_t fp = combineHash(0, refs.head.target.hash());
    for (const RefInfo& ref : refs.refs) {
        fp = combineHash(fp, std::hash<std::string>{}(ref.fullName));
        fp = combineHash(fp, ref.target.hash());
    }
    return fp;
}

bool historyQueryEquals(const HistoryQuery& a, const HistoryQuery& b) {
    return a.seedRefs == b.seedRefs && a.includeRefs == b.includeRefs &&
           a.excludeRefs == b.excludeRefs && a.pathFilter == b.pathFilter && a.grep == b.grep &&
           a.author == b.author && a.since == b.since && a.until == b.until &&
           a.firstParentOnly == b.firstParentOnly && a.includeReflog == b.includeReflog &&
           a.dateOrder == b.dateOrder && a.maxCount == b.maxCount;
}

}  // namespace

RepositorySession::RepositorySession(GitInstallation installation,
                                     RepoPaths paths,
                                     ThreadPool& readPool,
                                     QObject* parent)
    : QObject(parent),
      installation_(std::move(installation)),
      paths_(std::move(paths)),
      readPool_(readPool) {
    runner_ = makeProcessRunner(installation_.executable);
    catFile_ = std::make_unique<CatFileBatch>(installation_.executable, paths_);
    refStore_ = std::make_unique<RefStore>(*runner_, paths_);
    history_ = std::make_unique<HistoryProvider>(*runner_, paths_);
    diffs_ = std::make_unique<DiffService>(*runner_, paths_);
    operations_ = std::make_unique<OperationRunner>(*runner_, paths_);
    workingCopyStatusReader_ = std::make_unique<WorkingCopyStatusReader>(*runner_, paths_);
    stashStore_ = std::make_unique<StashStore>(*runner_, paths_);
    worktreeStore_ = std::make_unique<WorktreeStore>(*runner_, paths_);
    remoteStore_ = std::make_unique<RemoteStore>(*runner_, paths_);
    blameStore_ = std::make_unique<BlameStore>(*runner_, paths_);
    fileHistoryStore_ = std::make_unique<FileHistoryStore>(*runner_, paths_);
    reflogStore_ = std::make_unique<ReflogStore>(*runner_, paths_);
    submoduleStore_ = std::make_unique<SubmoduleStore>(*runner_, paths_);
    bisectStore_ = std::make_unique<BisectStore>(*runner_, paths_);
    lfsStore_ = std::make_unique<LfsStore>(*runner_, paths_);
    localIdentityStore_ = std::make_unique<LocalIdentityStore>(*runner_, paths_);

    askpass_ = new AskpassWatcher(this);
    connect(
        askpass_, &AskpassWatcher::promptReceived, this, &RepositorySession::credentialRequested);

    // Single-shot, restarted on every requestRefresh() call that returns Arm
    // -- see refreshCoalescer_'s doc comment and
    // docs/reports/vscode-graph-performance.md, bottleneck #6.
    refreshTimer_ = new QTimer(this);
    refreshTimer_->setSingleShot(true);
    connect(refreshTimer_, &QTimer::timeout, this, &RepositorySession::onRefreshTimeout);
}

RepositorySession::~RepositorySession() {
    // Cancel first, then let the members go: a worker still holding a reference to
    // this session's services must not outlive them.
    historyCancel_.cancel();
    readCancel_.cancel();
    if (catFile_) {
        catFile_->stop();
    }
}

QString RepositorySession::displayName() const {
    return QString::fromStdString(paths_.displayName());
}

RepoState RepositorySession::state() const {
    return RepoState::read(paths_);
}

void RepositorySession::setBusy(bool busy) {
    // Reference-counted: several reads may be in flight, and the indicator should
    // only clear when the last one finishes.
    const bool wasBusy = busyCount_ > 0;
    busyCount_ += busy ? 1 : -1;
    if (busyCount_ < 0) {
        busyCount_ = 0;
    }
    const bool isBusy = busyCount_ > 0;
    if (isBusy != wasBusy) {
        emit busyChanged(isBusy);
    }
}

void RepositorySession::refreshHistory(HistoryQuery query) {
    requestRefresh(
        /*wantsRefs=*/false, /*wantsHistory=*/true, std::move(query), GraphUpdateOrigin::Explicit);
}

void RepositorySession::refreshRefsAndHistory(HistoryQuery query, GraphUpdateOrigin origin) {
    requestRefresh(/*wantsRefs=*/true, /*wantsHistory=*/true, std::move(query), origin);
}

void RepositorySession::requestRefresh(bool wantsRefs,
                                       bool wantsHistory,
                                       HistoryQuery query,
                                       GraphUpdateOrigin origin) {
    // A refreshRefs()-only request has no opinion about the history query --
    // must not clobber a real filter a preceding request already set for
    // this same window.
    if (wantsHistory) {
        pendingRefreshQuery_ = std::move(query);
    }

    // Timestamp zero for this window's gbm-timing line -- see
    // WalkTimingProbe's doc comment and
    // docs/reports/vscode-graph-performance.md, bottlenecks #4 and #6. Null
    // (and free to check against) whenever GBM_TIMING=1 wasn't set. Created
    // once per window, on its first request -- later requests in the same
    // window reuse it so requestedAt_ stays the window's actual start.
    if (!pendingRefreshProbe_ && walkTimingEnabled()) {
        pendingRefreshProbe_ = std::make_shared<WalkTimingProbe>(origin);
    }

    if (refreshCoalescer_.request(wantsRefs, wantsHistory, origin) ==
        RefreshCoalescer::RefreshAction::Arm) {
        refreshTimer_->start(RefreshCoalescer::kDelay);
    }
    // Fold: a refresh is already running and refreshTimer_ must be left
    // alone -- finishRefresh() re-arms it (with zero delay) once that
    // refresh's terminal path reports it done.
}

void RepositorySession::onRefreshTimeout() {
    const RefreshCoalescer::Generation generation = refreshCoalescer_.onTimeout();
    if (generation == 0) {
        // The QTimer firing no earlier than its interval means this should
        // never actually happen -- see RefreshCoalescer.h's doc comment --
        // but if it somehow does, there is nothing to dispatch yet.
        return;
    }

    const RefreshCoalescer::PendingRefresh pending = refreshCoalescer_.takePending();
    WalkTimingProbePtr timing = std::move(pendingRefreshProbe_);
    if (timing) {
        // The probe was created at the window's first request, before the
        // final merged origin (Explicit always wins) was known.
        timing->setOrigin(pending.origin);
        timing->markFired();
    }
    HistoryQuery query = std::move(pendingRefreshQuery_);
    pendingRefreshQuery_ = HistoryQuery{};

    if (pending.wantsRefs && pending.wantsHistory) {
        startRefsAndHistory(std::move(query), pending.origin, std::move(timing), generation);
    } else if (pending.wantsHistory) {
        startHistoryOnly(std::move(query), std::move(timing), generation);
    } else if (pending.wantsRefs) {
        startRefsOnly(generation);
    }
}

void RepositorySession::finishRefresh(RefreshCoalescer::Generation generation) {
    if (refreshCoalescer_.onFinished(generation)) {
        // Debouncer::finish() already reset its internal clock to fire
        // immediately (no second wait) -- start(0) queues onRefreshTimeout()
        // for the next event loop tick rather than re-entering it directly
        // from inside this terminal handler.
        refreshTimer_->start(0);
    }
}

void RepositorySession::startHistoryOnly(HistoryQuery query,
                                         WalkTimingProbePtr timing,
                                         RefreshCoalescer::Generation generation) {
    // Means "refresh with whatever's currently selected" -- if
    // setHistoryFilter() has set a branch filter, substitute it here rather
    // than letting an incidental refresh silently revert the graph to "show
    // everything".
    if (historyQueryEquals(query, HistoryQuery{}) &&
        !historyQueryEquals(activeHistoryQuery_, HistoryQuery{})) {
        query = activeHistoryQuery_;
    }

    // Apply this repository's "large-repository mode" cap (Repository
    // Settings > Performance) when the caller hasn't already asked for a
    // specific limit -- read on this (the UI) thread since QSettings access
    // from a worker isn't worth the risk for a value read once per call.
    if (query.maxCount == 0) {
        query.maxCount = maxGraphRowsSetting(paths_);
    }

    // Supersede rather than queue: the previous walk's results are no longer what
    // the user is looking at.
    historyCancel_.cancel();
    historyCancel_ = CancellationSource();
    const CancellationToken token = historyCancel_.token();

    setBusy(true);

    readPool_.post([this, query = std::move(query), token, timing, generation]() mutable {
        if (timing) {
            timing->markWorkerStarted();
        }
        // Re-read refs here rather than trusting refs_.current(): a caller
        // that calls this alone (no adjacent refreshRefs()) has no other
        // guarantee refs_ reflects anything that happened since the last
        // refresh. Callers that DO have a fresh RefSnapshotPtr in hand
        // already -- refreshRefs() immediately followed by refreshHistory(),
        // which is every other call site -- should call
        // refreshRefsAndHistory() instead, which shares one `for-each-ref`
        // load between the two rather than paying for this one twice.
        auto freshRefs = refStore_->load(token);
        if (!freshRefs && freshRefs.error().code == GitError::Code::Cancelled) {
            // This call was itself superseded (historyCancel_ was cancelled
            // and reassigned) before it even reached walkHistoryWithRefs().
            // `generation` is therefore guaranteed stale by now (historyCancel_
            // is only ever reassigned alongside a new RefreshCoalescer
            // dispatch -- see RepositorySession.h's finishRefresh() doc
            // comment), so finishRefresh() below is a safe no-op and does not
            // need a token check first. No timing line either: the superseding
            // call's own probe covers it, and initialWorkingCopyGate_ is left
            // for that superseding call's own terminal path to release.
            QMetaObject::invokeMethod(
                this,
                [this, generation] {
                    setBusy(false);
                    finishRefresh(generation);
                },
                Qt::QueuedConnection);
            return;
        }
        if (timing) {
            timing->markRefsLoaded();
        }
        const RefSnapshotPtr refsForSeed = freshRefs ? *freshRefs : refs_.current();
        walkHistoryWithRefs(
            std::move(query), refsForSeed, token, GraphUpdateOrigin::Explicit, timing, generation);
    });
}

void RepositorySession::startRefsAndHistory(HistoryQuery query,
                                            GraphUpdateOrigin origin,
                                            WalkTimingProbePtr timing,
                                            RefreshCoalescer::Generation generation) {
    if (historyQueryEquals(query, HistoryQuery{}) &&
        !historyQueryEquals(activeHistoryQuery_, HistoryQuery{})) {
        query = activeHistoryQuery_;
    }
    if (query.maxCount == 0) {
        query.maxCount = maxGraphRowsSetting(paths_);
    }

    historyCancel_.cancel();
    historyCancel_ = CancellationSource();
    const CancellationToken token = historyCancel_.token();

    setBusy(true);

    readPool_.post([this, query = std::move(query), token, origin, timing, generation]() mutable {
        if (timing) {
            timing->markWorkerStarted();
        }
        auto freshRefs = refStore_->load(token);
        if (!freshRefs) {
            if (freshRefs.error().code != GitError::Code::Cancelled) {
                GitError error = std::move(freshRefs).error();
                QMetaObject::invokeMethod(
                    this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
            }
            // No walk is going to run for this call, so this is the only
            // chance to log a line for it -- neither emitGraphUpdated() nor
            // noteGraphApplied() will ever run. refsLoadedMs stays unreached
            // (-1) deliberately: the for-each-ref call is exactly what
            // failed or was cancelled here.
            if (timing) {
                const WalkOutcome outcome = freshRefs.error().code == GitError::Code::Cancelled
                                                ? WalkOutcome::Cancelled
                                                : WalkOutcome::Failed;
                logTiming(
                    formatWalkTiming(toString(timing->origin()), outcome, 0, timing->snapshot()));
            }
            // Refs could not be loaded at all, so no walk is going to run for
            // this call. finishRefresh(generation) is unconditional -- a
            // stale generation (this call was superseded) is a safe no-op,
            // see RepositorySession.h's finishRefresh() doc comment.
            // Release initialWorkingCopyGate_ only when this was a genuine
            // error (token not cancelled) -- that is a true terminal state,
            // and the panel must not stay stuck empty because a repository
            // failed to load its refs. When this was instead a
            // supersede-cancellation, the newer call that cancelled this one
            // is already underway and owns releasing the gate itself once it
            // reaches its own terminal path; releasing here too would open
            // the gate before that newer call has a result, letting the cold
            // status scan race ahead of the very walk this ordering fix
            // exists to protect.
            QMetaObject::invokeMethod(
                this,
                [this, token, generation] {
                    setBusy(false);
                    finishRefresh(generation);
                    if (token.isCancelled()) {
                        return;
                    }
                    releaseInitialWorkingCopyGate();
                },
                Qt::QueuedConnection);
            return;
        }
        if (timing) {
            timing->markRefsLoaded();
        }
        const RefSnapshotPtr refsForSeed = *freshRefs;
        refs_.publish(refsForSeed);
        QMetaObject::invokeMethod(this, [this] { emit refsUpdated(); }, Qt::QueuedConnection);
        walkHistoryWithRefs(std::move(query), refsForSeed, token, origin, timing, generation);
    });
}

void RepositorySession::walkHistoryWithRefs(HistoryQuery query,
                                            RefSnapshotPtr refsForSeed,
                                            CancellationToken token,
                                            GraphUpdateOrigin origin,
                                            WalkTimingProbePtr timing,
                                            RefreshCoalescer::Generation generation) {
    // Always seed from the refs so the trunk lands in lane 0 -- this is
    // ordering only (HistoryQuery::toRevListArgs), never narrowing: it is
    // followed by --all whenever includeRefs (the branch filter) is
    // empty, and ignored outright when includeRefs is set.
    if (refsForSeed) {
        query.seedRefs = RefStore::historySeedRefs(*refsForSeed);
    }

    // The branch filter (query.includeRefs) is sticky -- see
    // setHistoryFilter -- and can go stale between when it was chosen
    // and when this refresh actually runs: a filtered-on branch or
    // remote-tracking ref can be deleted or pruned in between. Drop
    // anything no longer present in the fresh snapshot rather than
    // handing rev-list a dead name, which would abort the entire walk.
    // If everything gets dropped, toRevListArgs' includeRefs.empty()
    // check falls back to "show everything", same as an unset filter.
    if (!query.includeRefs.empty() && refsForSeed) {
        std::vector<std::string> stillValid;
        stillValid.reserve(query.includeRefs.size());
        for (const std::string& ref : query.includeRefs) {
            if (RefStore::refExists(*refsForSeed, ref)) {
                stillValid.push_back(ref);
            } else {
                GBM_LOG_WARN("Branch filter: '" + ref +
                             "' no longer exists, dropping it from the graph filter");
            }
        }
        query.includeRefs = std::move(stillValid);
    }

    const std::uint64_t fingerprint = refsForSeed ? fingerprintRefs(*refsForSeed) : 0;
    if (hasLastWalk_ && fingerprint == lastWalkFingerprint_ &&
        historyQueryEquals(query, lastWalkQuery_)) {
        if (const GraphSnapshotPtr current = graph_.current(); current && current->complete) {
            // Nothing that could change the walk's result has happened
            // since the last completed walk with this same query -- skip
            // re-running `rev-list` and just republish what we have.
            QMetaObject::invokeMethod(
                this,
                [this, token, origin, timing, generation] {
                    setBusy(false);
                    // finishRefresh(generation) is unconditional -- a stale
                    // generation (this call was superseded) is a safe no-op.
                    // Same reasoning as the final catch-all below: if `token`
                    // is cancelled, this call was itself superseded before
                    // reaching here, and the newer call that superseded it
                    // owns emitting and releasing the gate once it has its
                    // own result -- doing either here too would let the cold
                    // status scan (and a stale graph snapshot) race ahead of
                    // that still-in-flight walk, exactly the bottleneck #2
                    // serialization this gate exists to prevent.
                    finishRefresh(generation);
                    if (token.isCancelled()) {
                        return;
                    }
                    // No rev-list ran, so this line must read outcome=skipped
                    // rather than emitGraphUpdated()'s complete=true
                    // suggesting a real walk finished -- see
                    // WalkTimingProbe::markSkipped().
                    if (timing) {
                        timing->markSkipped();
                    }
                    emitGraphUpdated(true, origin, timing);
                    releaseInitialWorkingCopyGate();
                },
                Qt::QueuedConnection);
            return;
        }
    }

    auto result = history_->walk(
        query,
        [this, token, origin, timing](GraphSnapshotPtr chunk) {
            if (token.isCancelled()) {
                return;
            }
            const bool complete = chunk->complete;
            if (timing) {
                timing->markChunkBuilt();
            }
            graph_.publish(std::move(chunk));
            // Queued, so the UI thread picks it up in its own event loop.
            // Also releases initialWorkingCopyGate_ on the first chunk --
            // idempotent on every chunk after that -- so the speculative
            // repo-open status scan runs once the graph has something to
            // show instead of waiting for the entire walk to finish. See
            // docs/reports/vscode-graph-performance.md, bottleneck #2.
            QMetaObject::invokeMethod(
                this,
                [this, complete, origin, timing] {
                    emitGraphUpdated(complete, origin, timing);
                    releaseInitialWorkingCopyGate();
                },
                Qt::QueuedConnection);
        },
        token);

    if (result) {
        QMetaObject::invokeMethod(
            this,
            [this, fingerprint, query] {
                lastWalkFingerprint_ = fingerprint;
                lastWalkQuery_ = query;
                hasLastWalk_ = true;
            },
            Qt::QueuedConnection);
    } else if (result.error().code != GitError::Code::Cancelled) {
        GitError error = std::move(result).error();
        // A genuine walk failure never reaches emitGraphUpdated(), so this is
        // the only chance to log it -- unlike the fingerprint-skip path
        // above, this really doesn't reach MainWindow.
        if (timing) {
            logTiming(formatWalkTiming(
                toString(timing->origin()), WalkOutcome::Failed, 0, timing->snapshot()));
        }
        QMetaObject::invokeMethod(
            this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
    }
    // The last thing this function does: covers the success/error paths, and
    // is the only release point reached when history_->walk() fails before
    // ever publishing a chunk (e.g. rev-list itself fails to start).
    // setBusy(false) stays unconditional -- it must run regardless of
    // cancellation to balance this call's setBusy(true), or the busy
    // indicator would stick on. The gate release does not: when `token` is
    // cancelled, this walk was itself superseded (historyCancel_ reassigned
    // by a newer refreshHistory()/refreshRefsAndHistory() call -- e.g. from
    // maybeAutoFetch(), resyncOpenSession(), or a rapid user action shortly
    // after repo open), and releasing here would open the gate -- letting
    // the cold status scan start -- before the walk that actually superseded
    // this one has a result. That newer call's own terminal path owns the
    // release instead.
    QMetaObject::invokeMethod(
        this,
        [this, token, timing, generation] {
            setBusy(false);
            // finishRefresh(generation) is unconditional -- a stale
            // generation (this walk was superseded) is a safe no-op, so it
            // does not need a token check first (see RepositorySession.h's
            // finishRefresh() doc comment).
            finishRefresh(generation);
            if (token.isCancelled()) {
                // This walk was itself superseded (historyCancel_ reassigned
                // by a newer call) -- that newer call's own terminal path
                // owns releasing the gate instead; releasing it here too
                // would let the cold status scan race ahead of that
                // still-in-flight refresh. A walk that already delivered a
                // chunk (firstChunkLogged()) has already logged for this
                // probe -- e.g. it was streaming when a newer refresh
                // superseded it. Logging Cancelled here too would be a
                // second, redundant line for the same probe; only log when
                // this walk never got that far.
                if (timing && !timing->firstChunkLogged()) {
                    logTiming(formatWalkTiming(
                        toString(timing->origin()), WalkOutcome::Cancelled, 0, timing->snapshot()));
                }
                return;
            }
            releaseInitialWorkingCopyGate();
        },
        Qt::QueuedConnection);
}

void RepositorySession::emitGraphUpdated(bool complete,
                                         GraphUpdateOrigin origin,
                                         WalkTimingProbePtr timing) {
    // AutoFetchResync at Info: this is exactly the case
    // docs/reports/vscode-graph-performance.md bottleneck #3 flagged as
    // silent -- a second graphUpdated() a moment after the first, with no way
    // to tell it apart from "the walk was just slow". Every other origin logs
    // at Debug, matching the log-noise level GBM_LOG_WARN's neighbours in
    // this file already use for routine per-walk detail.
    const std::string message = std::string("Graph updated (") + std::string(toString(origin)) +
                                ", " + (complete ? "complete)" : "partial)");
    if (origin == GraphUpdateOrigin::AutoFetchResync) {
        GBM_LOG_INFO(message);
    } else {
        GBM_LOG_DEBUG(message);
    }

    if (timing) {
        timing->markChunkDelivered();
        // Set before emit: graphUpdated() is connected same-thread, so
        // MainWindow::onGraphUpdated() -> noteGraphApplied() runs
        // synchronously inside this emit, and needs to find it here.
        pendingTimingProbe_ = std::move(timing);
    }

    emit graphUpdated(complete, origin);
}

void RepositorySession::noteGraphApplied(bool complete, std::size_t rows) {
    if (!pendingTimingProbe_) {
        return;
    }
    // Consumed unconditionally, whether or not this call ends up logging a
    // line -- either way, this probe's UI-apply leg is now accounted for.
    const WalkTimingProbePtr timing = std::move(pendingTimingProbe_);
    timing->markUiApplied();

    WalkOutcome outcome;
    if (timing->consumeSkipped()) {
        outcome = WalkOutcome::Skipped;
    } else if (complete) {
        outcome = WalkOutcome::Complete;
    } else if (!timing->firstChunkLogged()) {
        outcome = WalkOutcome::FirstChunk;
    } else {
        // An intermediate chunk between the first and the last -- see
        // HistoryProvider.h's geometric publish schedule. Not logged, so a
        // walk produces at most a first-chunk and a complete line rather
        // than one per chunk.
        return;
    }
    timing->setFirstChunkLogged();
    logTiming(formatWalkTiming(toString(timing->origin()), outcome, rows, timing->snapshot()));
}

void RepositorySession::setHistoryFilter(HistoryQuery query) {
    activeHistoryQuery_ = query;

    // Bypasses the coalescing *delay*: a filter change alters *what* the
    // user is looking at, and folding it behind an in-flight walk would
    // leave the wrong graph on screen for up to a full walk -- the one
    // deliberate exception to bottleneck #6's coalescing (see
    // docs/reports/vscode-graph-performance.md and refreshHistory()'s doc
    // comment). It does not bypass refreshCoalescer_ itself: fireNow()
    // still marks it running (under a fresh generation), so a request
    // arriving while this walk is in flight correctly folds and is
    // delivered afterward, rather than arming its own independent walk that
    // would cancel this one out from under it.
    refreshTimer_->stop();

    // Merges this filter change's own want (wantsHistory only) with
    // whatever was already pending -- an armed-but-unfired or
    // folded-but-undelivered refreshRefs() from just before the filter
    // change must not be silently dropped just because this call bypasses
    // the delay. See RefreshCoalescer::fireNow()'s doc comment.
    const RefreshCoalescer::Generation generation = refreshCoalescer_.fireNow(
        /*wantsRefs=*/false, /*wantsHistory=*/true, GraphUpdateOrigin::Explicit);
    const RefreshCoalescer::PendingRefresh pending = refreshCoalescer_.takePending();

    // The superseded window's own query/probe are irrelevant here: this
    // call's `query` (the new filter) always wins over whatever was queued
    // for the window fireNow() just superseded.
    pendingRefreshQuery_ = HistoryQuery{};
    pendingRefreshProbe_.reset();

    WalkTimingProbePtr timing;
    if (walkTimingEnabled()) {
        timing = std::make_shared<WalkTimingProbe>(GraphUpdateOrigin::Explicit);
        timing->markFired();
    }

    if (pending.wantsRefs) {
        startRefsAndHistory(
            std::move(query), GraphUpdateOrigin::Explicit, std::move(timing), generation);
    } else {
        startHistoryOnly(std::move(query), std::move(timing), generation);
    }
}

void RepositorySession::refreshRefs() {
    requestRefresh(
        /*wantsRefs=*/true, /*wantsHistory=*/false, HistoryQuery{}, GraphUpdateOrigin::Explicit);
}

void RepositorySession::startRefsOnly(RefreshCoalescer::Generation generation) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token, generation] {
        auto snapshot = refStore_->load(token);
        if (snapshot) {
            refs_.publish(*snapshot);
            QMetaObject::invokeMethod(this, [this] { emit refsUpdated(); }, Qt::QueuedConnection);
        } else if (snapshot.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(snapshot).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(
            this,
            [this, generation] {
                setBusy(false);
                finishRefresh(generation);
            },
            Qt::QueuedConnection);
    });
}

void RepositorySession::requestCommitMetadata(std::vector<ObjectId> oids) {
    if (oids.empty()) {
        return;
    }
    const CancellationToken token = readCancel_.token();

    // postFront: the newest request reflects where the user is actually looking,
    // so it must jump ahead of stale viewport requests still in the queue.
    readPool_.postFront([this, oids = std::move(oids), token] {
        if (token.isCancelled()) {
            return;
        }
        if (auto started = catFile_->start(); !started) {
            GitError error = std::move(started).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
            return;
        }
        std::vector<CommitMeta> metadata = catFile_->readCommits(oids, token);
        if (token.isCancelled() || metadata.empty()) {
            return;
        }
        QMetaObject::invokeMethod(
            this,
            [this, metadata = std::move(metadata)] { emit commitMetadataReady(metadata); },
            Qt::QueuedConnection);
    });
}

void RepositorySession::requestCommitDetails(const ObjectId& commit) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, commit, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }

        const DiffOptions options;
        auto files = diffs_->changedFiles(commit, options, token);
        auto diff = diffs_->commitDiff(commit, options, token);

        if (!token.isCancelled() && files && diff) {
            auto filesPtr = *files;
            auto diffPtr = *diff;
            QMetaObject::invokeMethod(
                this,
                [this, commit, filesPtr, diffPtr] {
                    emit commitDetailsReady(commit, filesPtr, diffPtr);
                },
                Qt::QueuedConnection);
        } else if (files && !files->get()) {
            // Nothing to show; not an error worth a dialog.
        } else if (!files && files.error().code != GitError::Code::Cancelled) {
            GitError error = files.error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }

        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::checkout(const CheckoutRequest& request) {
    setBusy(true);
    operations_->submit(makeCheckoutOperation(request), [this](OperationOutcome outcome) {
        // Runs on the operation runner's serial thread; hop to the UI thread and
        // refresh what the checkout changed.
        QMetaObject::invokeMethod(
            this,
            [this, outcome = std::move(outcome)] {
                setBusy(false);
                emit operationFinished(outcome);
                if (outcome.succeeded) {
                    refreshRefsAndHistory();
                }
            },
            Qt::QueuedConnection);
    });
}

// --- Sidebar (Phase 2): branch mutation -------------------------------------

void RepositorySession::createBranch(const CreateBranchRequest& request) {
    submitAndRefresh(makeCreateBranchOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::renameBranch(const RenameBranchRequest& request) {
    submitAndRefresh(makeRenameBranchOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::deleteBranch(const DeleteBranchRequest& request) {
    // Unlike FetchRequest/PushRequest/DeleteTagRequest, DeleteBranchRequest has
    // no askpassDir field -- DeleteBranchOperation's `git push --delete` path
    // (core/git/ops/BranchOps.cpp) never calls askpass::wire(). Adding that
    // field is a src/core change and out of scope here, so a remote delete
    // that needs credentials fails the same way an unauthenticated push
    // would (GIT_TERMINAL_PROMPT=0), rather than prompting.
    submitAndRefresh(makeDeleteBranchOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::cancelPendingReads() {
    readCancel_.cancel();
    readCancel_ = CancellationSource();
    // historyCancel_ is otherwise only touched by refreshHistory() itself
    // (superseding the previous walk on every new one) -- without cancelling
    // it here too, a history walk in flight when the session is about to be
    // destroyed would only be noticed inside ~RepositorySession(), by which
    // point the caller (MainWindow::closeRepository) has no chance to wait
    // for the worker to actually stop before the destructor runs.
    historyCancel_.cancel();
    historyCancel_ = CancellationSource();

    // Backstop for refreshCoalescer_: a session about to be destroyed must
    // not leave a Fold wedged (see RefreshCoalescer::reset()'s doc comment)
    // -- nothing would ever call finishRefresh() again to clear it once this
    // session's remaining terminal paths finish landing.
    refreshCoalescer_.reset();
    refreshTimer_->stop();
    pendingRefreshQuery_ = HistoryQuery{};
    pendingRefreshProbe_.reset();
}

void RepositorySession::refreshWorkingCopyStatus() {
    // Always runs, and always opens initialWorkingCopyGate_ -- a user-driven
    // or post-operation refresh must never itself be held back by the
    // repo-open gate, and once real data has been requested this way there is
    // nothing left for the gate to usefully defer. release()'s own return
    // value is unused here: if a refreshWorkingCopyStatusWhenIdle() call was
    // pending, this call already supersedes it.
    initialWorkingCopyGate_.release();

    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto status = workingCopyStatusReader_->read(token);
        if (status) {
            workingCopyStatus_.publish(*status);
            QMetaObject::invokeMethod(
                this, [this] { emit workingCopyStatusUpdated(); }, Qt::QueuedConnection);
        } else if (status.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(status).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::refreshWorkingCopyStatusWhenIdle() {
    // Speculative repo-open call -- see the doc comment on this method in
    // RepositorySession.h and releaseInitialWorkingCopyGate() below for why
    // this is held back rather than run unconditionally.
    if (initialWorkingCopyGate_.requestOrHold()) {
        refreshWorkingCopyStatus();
    }
}

void RepositorySession::releaseInitialWorkingCopyGate() {
    if (initialWorkingCopyGate_.release()) {
        refreshWorkingCopyStatus();
    }
}

void RepositorySession::requestWorkingCopyDiff(const std::string& path, bool staged) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    // postFront: mirrors requestCommitDetails -- the newest selection is what
    // the user is looking at, so it must not wait behind a stale request.
    readPool_.postFront([this, path, staged, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }

        auto diff = diffs_->workingTreeDiff(staged, {path}, DiffOptions{}, token);
        if (diff) {
            auto diffPtr = *diff;
            const QString qpath = QString::fromStdString(path);
            QMetaObject::invokeMethod(
                this,
                [this, qpath, staged, diffPtr] {
                    emit workingCopyDiffReady(qpath, staged, diffPtr);
                },
                Qt::QueuedConnection);
        } else if (diff.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(diff).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::requestCompareWithWorkingCopy(const ObjectId& commit) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    // postFront: mirrors requestWorkingCopyDiff -- the newest request is what
    // the user is looking at.
    readPool_.postFront([this, commit, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }

        auto diff = diffs_->commitVsWorkingTree(commit, DiffOptions{}, token);
        if (diff) {
            auto diffPtr = *diff;
            QMetaObject::invokeMethod(
                this,
                [this, commit, diffPtr] { emit compareWithWorkingCopyReady(commit, diffPtr); },
                Qt::QueuedConnection);
        } else if (diff.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(diff).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::submitWorkingCopyOperation(std::unique_ptr<Operation> operation,
                                                   bool alsoRefreshHistory) {
    setBusy(true);
    operations_->submit(std::move(operation), [this, alsoRefreshHistory](OperationOutcome outcome) {
        // Runs on the operation runner's serial thread; hop to the UI thread
        // before touching anything Qt.
        QMetaObject::invokeMethod(
            this,
            [this, outcome = std::move(outcome), alsoRefreshHistory] {
                setBusy(false);
                emit workingCopyOperationFinished(outcome);
                if (outcome.succeeded) {
                    refreshWorkingCopyStatus();
                    if (alsoRefreshHistory) {
                        // A commit moved HEAD, so both the ref list and the
                        // graph need to reflect it.
                        refreshRefsAndHistory();
                    }
                }
            },
            Qt::QueuedConnection);
    });
}

void RepositorySession::stageFiles(std::vector<std::string> paths) {
    StageFilesRequest request;
    request.paths = std::move(paths);
    submitWorkingCopyOperation(makeStageFilesOperation(std::move(request)), false);
}

void RepositorySession::unstageFiles(std::vector<std::string> paths) {
    UnstageFilesRequest request;
    request.paths = std::move(paths);
    submitWorkingCopyOperation(makeUnstageFilesOperation(std::move(request)), false);
}

void RepositorySession::applyPatch(std::string patch, bool reverse) {
    ApplyPatchRequest request;
    request.patch = std::move(patch);
    request.reverse = reverse;
    submitWorkingCopyOperation(makeApplyPatchOperation(std::move(request)), false);
}

void RepositorySession::commitChanges(const CommitRequest& request) {
    submitWorkingCopyOperation(makeCommitOperation(request), true);
}

void RepositorySession::mergeBranch(const MergeRequest& request) {
    submitWorkingCopyOperation(makeMergeOperation(request), true);
}

void RepositorySession::abortMerge() {
    submitWorkingCopyOperation(makeMergeAbortOperation(), true);
}

void RepositorySession::cherryPick(const CherryPickRequest& request) {
    submitWorkingCopyOperation(makeCherryPickOperation(request), true);
}

void RepositorySession::continueCherryPick() {
    submitWorkingCopyOperation(makeCherryPickContinueOperation(), true);
}

void RepositorySession::skipCherryPick() {
    submitWorkingCopyOperation(makeCherryPickSkipOperation(), true);
}

void RepositorySession::abortCherryPick() {
    submitWorkingCopyOperation(makeCherryPickAbortOperation(), true);
}

void RepositorySession::revertCommit(const RevertRequest& request) {
    submitWorkingCopyOperation(makeRevertOperation(request), true);
}

void RepositorySession::resolveConflict(const ResolveConflictRequest& request) {
    // Never moves HEAD, so no refreshRefs/refreshHistory -- just the
    // working-copy status, to update the conflicted list.
    submitWorkingCopyOperation(makeResolveConflictOperation(request), false);
}

void RepositorySession::requestConflictSides(const std::string& path,
                                             const std::string& ancestorBlob,
                                             const std::string& oursBlob,
                                             const std::string& theirsBlob) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, path, ancestorBlob, oursBlob, theirsBlob, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }
        if (auto started = catFile_->start(); !started) {
            GitError error = std::move(started).error();
            QMetaObject::invokeMethod(
                this,
                [this, error] {
                    setBusy(false);
                    emit errorOccurred(error);
                },
                Qt::QueuedConnection);
            return;
        }

        // Best-effort: a stage that fails to read (or does not exist) shows as
        // empty rather than failing the whole request, so the two sides that
        // did read are still shown. Checked between the three reads (not just
        // once above): a cancellation arriving while the first blob is being
        // fetched should stop the remaining two from starting.
        auto readOrEmpty = [this, token](const std::string& blob) {
            if (blob.empty() || token.isCancelled()) {
                return std::string();
            }
            auto object = catFile_->read(blob, token);
            return object ? object->content : std::string();
        };
        const std::string ancestor = readOrEmpty(ancestorBlob);
        const std::string ours = readOrEmpty(oursBlob);
        const std::string theirs = readOrEmpty(theirsBlob);

        const QString qpath = QString::fromStdString(path);
        QMetaObject::invokeMethod(
            this,
            [this, qpath, ancestor, ours, theirs] {
                setBusy(false);
                emit conflictSidesReady(qpath,
                                        QString::fromStdString(ancestor),
                                        QString::fromStdString(ours),
                                        QString::fromStdString(theirs));
            },
            Qt::QueuedConnection);
    });
}

void RepositorySession::requestFileContent(const std::string& path, const std::string& revision) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, path, revision, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }
        if (auto started = catFile_->start(); !started) {
            GitError error = std::move(started).error();
            QMetaObject::invokeMethod(
                this,
                [this, error] {
                    setBusy(false);
                    emit errorOccurred(error);
                },
                Qt::QueuedConnection);
            return;
        }

        // `revision:path`, e.g. "HEAD:src/main.cpp" or ":src/main.cpp" for the
        // index -- the same syntax CatFileBatch::read documents accepting.
        const std::string object = revision + ":" + path;
        auto result = catFile_->read(object, token);
        // Best-effort, like requestConflictSides: a missing object (untracked
        // file, or a path that did not exist at `revision`) is a normal
        // display state, not a failure worth surfacing as an error.
        const bool exists = static_cast<bool>(result);
        const std::string content = exists ? result->content : std::string();

        const QString qpath = QString::fromStdString(path);
        const QString qrevision = QString::fromStdString(revision);
        QMetaObject::invokeMethod(
            this,
            [this, qpath, qrevision, content, exists] {
                setBusy(false);
                emit fileContentReady(qpath, qrevision, QString::fromStdString(content), exists);
            },
            Qt::QueuedConnection);
    });
}

void RepositorySession::submitAndRefresh(std::unique_ptr<Operation> operation,
                                         std::function<void(bool)> afterFinished,
                                         bool drivesBusy) {
    if (drivesBusy) {
        setBusy(true);
    }
    operations_->submit(
        std::move(operation),
        [this, afterFinished = std::move(afterFinished), drivesBusy](OperationOutcome outcome) {
            // Runs on the operation runner's serial thread; hop to the UI
            // thread before touching anything Qt, same as
            // submitWorkingCopyOperation.
            QMetaObject::invokeMethod(
                this,
                [this, outcome = std::move(outcome), afterFinished, drivesBusy] {
                    if (drivesBusy) {
                        setBusy(false);
                    }
                    emit workingCopyOperationFinished(outcome);
                    if (afterFinished) {
                        afterFinished(outcome.succeeded);
                    }
                },
                Qt::QueuedConnection);
        });
}

// --- M3: stashes -------------------------------------------------------

void RepositorySession::refreshStashes() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto list = stashStore_->list(token);
        if (list) {
            stashes_.publish(std::make_shared<std::vector<StashEntry>>(std::move(*list)));
            QMetaObject::invokeMethod(
                this, [this] { emit stashesUpdated(); }, Qt::QueuedConnection);
        } else if (list.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(list).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::saveStash(const StashSaveRequest& request) {
    submitAndRefresh(makeStashSaveOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorkingCopyStatus();
            refreshStashes();
        }
    });
}

void RepositorySession::applyStash(const StashApplyRequest& request) {
    submitAndRefresh(makeStashApplyOperation(request), [this](bool succeeded) {
        // Even a conflicting apply/pop leaves the working tree changed.
        refreshWorkingCopyStatus();
        if (succeeded) {
            refreshStashes();
        }
    });
}

void RepositorySession::dropStash(const StashDropRequest& request) {
    submitAndRefresh(makeStashDropOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshStashes();
        }
    });
}

void RepositorySession::branchFromStash(const StashBranchRequest& request) {
    submitAndRefresh(makeStashBranchOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorkingCopyStatus();
            refreshStashes();
            refreshRefsAndHistory();
        }
    });
}

void RepositorySession::requestStashDiff(int index) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    // postFront: mirrors requestCompareWithWorkingCopy -- the newest request
    // is what the user is looking at.
    readPool_.postFront([this, index, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }

        auto diff = diffs_->stashDiff(index, /*includeUntracked=*/true, DiffOptions{}, token);
        if (diff) {
            auto diffPtr = *diff;
            QMetaObject::invokeMethod(
                this,
                [this, index, diffPtr] { emit stashDiffReady(index, diffPtr); },
                Qt::QueuedConnection);
        } else if (diff.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(diff).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

// --- M3: tags ------------------------------------------------------------

void RepositorySession::createTag(const CreateTagRequest& request) {
    submitAndRefresh(makeCreateTagOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::deleteTag(const DeleteTagRequest& request) {
    DeleteTagRequest wired = request;
    if (wired.alsoRemote) {
        wired.askpassDir = askpass::makeRequestDir();
        if (!wired.askpassDir.empty()) {
            askpass_->start(wired.askpassDir);
        }
    }
    submitAndRefresh(makeDeleteTagOperation(wired), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::pushTag(const PushTagRequest& request) {
    PushTagRequest wired = request;
    wired.askpassDir = askpass::makeRequestDir();
    if (!wired.askpassDir.empty()) {
        askpass_->start(wired.askpassDir);
    }
    submitAndRefresh(makePushTagOperation(wired), [this](bool) { askpass_->stop(); });
}

// --- M3: worktrees ---------------------------------------------------------

void RepositorySession::refreshWorktrees() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto list = worktreeStore_->list(token);
        if (list) {
            worktrees_.publish(std::make_shared<std::vector<WorktreeInfo>>(std::move(*list)));
            QMetaObject::invokeMethod(
                this, [this] { emit worktreesUpdated(); }, Qt::QueuedConnection);
        } else if (list.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(list).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::addWorktree(const AddWorktreeRequest& request) {
    submitAndRefresh(makeAddWorktreeOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorktrees();
        }
    });
}

void RepositorySession::removeWorktree(const RemoveWorktreeRequest& request) {
    submitAndRefresh(makeRemoveWorktreeOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorktrees();
        }
    });
}

void RepositorySession::pruneWorktrees() {
    submitAndRefresh(makePruneWorktreesOperation(PruneWorktreesRequest{}), [this](bool succeeded) {
        if (succeeded) {
            refreshWorktrees();
        }
    });
}

void RepositorySession::lockWorktree(const LockWorktreeRequest& request) {
    submitAndRefresh(makeLockWorktreeOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorktrees();
        }
    });
}

void RepositorySession::unlockWorktree(const UnlockWorktreeRequest& request) {
    submitAndRefresh(makeUnlockWorktreeOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshWorktrees();
        }
    });
}

// --- M3: remotes -----------------------------------------------------------

void RepositorySession::refreshRemotes() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto list = remoteStore_->list(token);
        if (list) {
            remotes_.publish(std::make_shared<std::vector<RemoteInfo>>(std::move(*list)));
            QMetaObject::invokeMethod(
                this, [this] { emit remotesUpdated(); }, Qt::QueuedConnection);
        } else if (list.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(list).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::fetchRemote(FetchRequest request) {
    request.askpassDir = askpass::makeRequestDir();
    if (!request.askpassDir.empty()) {
        askpass_->start(request.askpassDir);
    }
    submitAndRefresh(makeFetchOperation(std::move(request)), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            // A fetch can bring in new commits on remote-tracking refs; without
            // this the graph kept showing "not pulled yet" until the user
            // pulled or merged, even though the commits were already fetched.
            refreshRefsAndHistory();
        }
    });
}

void RepositorySession::fetchRemoteSilently() {
    // No askpassDir wiring: an empty FetchRequest::askpassDir means "no
    // credential prompt is possible", so an auth failure fails fast instead
    // of starting the askpass watcher that would otherwise surface a dialog.
    // prune = true so a deleted remote branch's remote-tracking ref actually
    // goes away here, instead of lingering as a `[gone]` upstream that
    // historySeedRefs has to keep filtering out on every refresh.
    FetchRequest request;
    request.prune = true;
    // drivesBusy = false: this runs automatically (repo open, window
    // re-activation), not from a user action, so the UI must not read as
    // stalled for a network round trip nobody asked for.
    submitAndRefresh(
        makeFetchOperation(std::move(request)),
        [this](bool succeeded) {
            if (succeeded) {
                // fetchRemoteSilently()'s only caller is maybeAutoFetch(), so
                // this resync is always the "silent second graph rebuild"
                // case -- see docs/reports/vscode-graph-performance.md,
                // bottleneck #3.
                refreshRefsAndHistory({}, GraphUpdateOrigin::AutoFetchResync);
            }
        },
        /*drivesBusy=*/false);
}

void RepositorySession::maybeAutoFetch() {
    if (!autoFetchOnOpenSetting(paths_)) {
        return;
    }
    const auto now = std::chrono::steady_clock::now();
    if (lastAutoFetchAt_ && now - *lastAutoFetchAt_ < kAutoFetchMinInterval) {
        return;
    }
    lastAutoFetchAt_ = now;
    fetchRemoteSilently();
}

// --- Commit-graph maintenance -----------------------------------------------

bool RepositorySession::hasCommitGraph() const {
    return gbm::hasCommitGraph(paths_);
}

CommitGraphPreference RepositorySession::commitGraphPreference() const {
    return commitGraphPreferenceSetting(paths_);
}

void RepositorySession::writeCommitGraph() {
    WriteCommitGraphRequest request;
    request.split = installation_.capabilities.commitGraphSplit;
    request.changedPaths = installation_.capabilities.changedPathBloom;
    // No refreshRefsAndHistory() on success, unlike every other mutation above:
    // the commits are unchanged, so the ref fingerprint walkHistoryWithRefs()
    // caches is unchanged too, and a re-walk would just short-circuit on that
    // cache while still paying for a second for-each-ref -- see
    // walkHistoryWithRefs()'s fingerprint check above. The graph is consulted
    // lazily by the next real history walk regardless of whether one runs now.
    // afterFinished already runs on the UI thread -- submitAndRefresh's own
    // completion lambda is what does the hop, same as every other caller
    // below (e.g. initSubmodules) -- so this just emits directly.
    submitAndRefresh(makeWriteCommitGraphOperation(request),
                     [this](bool succeeded) { emit commitGraphWriteFinished(succeeded); });
}

void RepositorySession::pullChanges(PullRequest request) {
    request.askpassDir = askpass::makeRequestDir();
    if (!request.askpassDir.empty()) {
        askpass_->start(request.askpassDir);
    }
    submitAndRefresh(makePullOperation(std::move(request)), [this](bool succeeded) {
        askpass_->stop();
        refreshWorkingCopyStatus();
        if (succeeded) {
            refreshRefsAndHistory();
        }
    });
}

void RepositorySession::pushChanges(PushRequest request) {
    request.askpassDir = askpass::makeRequestDir();
    if (!request.askpassDir.empty()) {
        askpass_->start(request.askpassDir);
    }
    submitAndRefresh(makePushOperation(std::move(request)), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshRefs();
        }
    });
}

void RepositorySession::provideCredential(const QString& secret) {
    askpass_->answer(secret);
}

void RepositorySession::cancelCredential() {
    askpass_->cancel();
}

// --- M4: reset / restore / clean --------------------------------------------

void RepositorySession::resetTo(const ResetRequest& request) {
    submitWorkingCopyOperation(makeResetOperation(request), true);
}

void RepositorySession::restorePaths(const RestoreRequest& request) {
    submitWorkingCopyOperation(makeRestoreOperation(request), false);
}

void RepositorySession::requestCleanPreview(bool includeIgnored) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, includeIgnored, token] {
        CleanPreviewer previewer(*runner_, paths_);
        auto preview = previewer.preview(includeIgnored, token);
        if (preview) {
            auto entries = *preview;
            QMetaObject::invokeMethod(
                this,
                [this, entries = std::move(entries)] { emit cleanPreviewReady(entries); },
                Qt::QueuedConnection);
        } else if (preview.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(preview).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::cleanUntracked(const CleanRequest& request) {
    submitWorkingCopyOperation(makeCleanOperation(request), false);
}

// --- M4: rebase --------------------------------------------------------------

void RepositorySession::requestRebasePlan(const std::string& upstream) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, upstream, token] {
        RebasePlanner planner(*runner_, paths_);
        auto plan = planner.plan(upstream, token);
        if (plan) {
            auto entries = *plan;
            QMetaObject::invokeMethod(
                this,
                [this, entries = std::move(entries)] { emit rebasePlanReady(entries); },
                Qt::QueuedConnection);
        } else if (plan.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(plan).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::startInteractiveRebase(const RebaseInteractiveRequest& request) {
    submitWorkingCopyOperation(makeRebaseInteractiveOperation(request), true);
}

void RepositorySession::startRebase(const RebaseRequest& request) {
    submitWorkingCopyOperation(makeRebaseOperation(request), true);
}

void RepositorySession::continueRebase() {
    submitWorkingCopyOperation(makeRebaseContinueOperation(), true);
}

void RepositorySession::skipRebase() {
    submitWorkingCopyOperation(makeRebaseSkipOperation(), true);
}

void RepositorySession::abortRebase() {
    submitWorkingCopyOperation(makeRebaseAbortOperation(), true);
}

// --- M4: blame -----------------------------------------------------------------

void RepositorySession::requestBlame(const std::string& path,
                                     const std::string& revision,
                                     int startLine,
                                     int endLine) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, path, revision, startLine, endLine, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }
        auto result = blameStore_->blame(path, revision, startLine, endLine, token);
        if (result) {
            auto resultPtr = *result;
            QMetaObject::invokeMethod(
                this, [this, resultPtr] { emit blameReady(resultPtr); }, Qt::QueuedConnection);
        } else if (result.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(result).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

// --- M4: file and line history ------------------------------------------------

void RepositorySession::requestFileHistory(const std::string& path,
                                           const std::string& startRevision) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, path, startRevision, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }
        auto entries = fileHistoryStore_->fileHistory(path, startRevision, token);
        if (entries) {
            auto result = *entries;
            QMetaObject::invokeMethod(
                this,
                [this, result = std::move(result)] { emit fileHistoryReady(result); },
                Qt::QueuedConnection);
        } else if (entries.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(entries).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::requestLineHistory(const std::string& path,
                                           int startLine,
                                           int endLine,
                                           const std::string& startRevision) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.postFront([this, path, startLine, endLine, startRevision, token] {
        if (token.isCancelled()) {
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }
        auto chunks =
            fileHistoryStore_->lineHistory(path, startLine, endLine, startRevision, token);
        if (chunks) {
            auto result = *chunks;
            QMetaObject::invokeMethod(
                this,
                [this, result = std::move(result)] { emit lineHistoryReady(result); },
                Qt::QueuedConnection);
        } else if (chunks.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(chunks).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

// --- M4: reflog and undo --------------------------------------------------------

void RepositorySession::requestReflog(const std::string& ref) {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, ref, token] {
        auto entries = reflogStore_->list(ref, token);
        if (entries) {
            auto result = *entries;
            QMetaObject::invokeMethod(
                this,
                [this, result = std::move(result)] { emit reflogReady(result); },
                Qt::QueuedConnection);
        } else if (entries.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(entries).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::undoLastOperation() {
    const auto& journal = operations_->undoJournal();
    if (journal.empty()) {
        return;
    }
    const auto& last = journal.back();
    UndoRequest request;
    request.headBefore = last.headBefore;
    request.branchBefore = last.branchBefore;
    submitWorkingCopyOperation(makeUndoOperation(request), true);
}

// --- M5: submodules ----------------------------------------------------------

void RepositorySession::refreshSubmodules() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto list = submoduleStore_->list(token);
        if (list) {
            submodules_.publish(std::make_shared<std::vector<SubmoduleInfo>>(std::move(*list)));
            QMetaObject::invokeMethod(
                this, [this] { emit submodulesUpdated(); }, Qt::QueuedConnection);
        } else if (list.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(list).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::addSubmodule(const AddSubmoduleRequest& request) {
    AddSubmoduleRequest wired = request;
    wired.askpassDir = askpass::makeRequestDir();
    if (!wired.askpassDir.empty()) {
        askpass_->start(wired.askpassDir);
    }
    submitAndRefresh(makeAddSubmoduleOperation(wired), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshSubmodules();
        }
    });
}

void RepositorySession::initSubmodules(const SubmodulePathsRequest& request) {
    submitAndRefresh(makeInitSubmodulesOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshSubmodules();
        }
    });
}

void RepositorySession::updateSubmodules(const UpdateSubmodulesRequest& request) {
    UpdateSubmodulesRequest wired = request;
    wired.askpassDir = askpass::makeRequestDir();
    if (!wired.askpassDir.empty()) {
        askpass_->start(wired.askpassDir);
    }
    submitAndRefresh(makeUpdateSubmodulesOperation(wired), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshSubmodules();
        }
    });
}

void RepositorySession::syncSubmodules(const SubmodulePathsRequest& request) {
    submitAndRefresh(makeSyncSubmodulesOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshSubmodules();
        }
    });
}

void RepositorySession::deinitSubmodules(const DeinitSubmodulesRequest& request) {
    submitAndRefresh(makeDeinitSubmodulesOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshSubmodules();
        }
    });
}

// --- M5: bisect ----------------------------------------------------------

void RepositorySession::refreshBisectStatus() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto status = bisectStore_->status(token);
        if (status) {
            bisectStatus_.publish(std::make_shared<BisectStatus>(std::move(*status)));
            QMetaObject::invokeMethod(
                this, [this] { emit bisectStatusUpdated(); }, Qt::QueuedConnection);
        } else if (status.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(status).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::startBisect(const BisectStartRequest& request) {
    submitAndRefresh(makeBisectStartOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshBisectStatus();
        }
    });
}

void RepositorySession::markBisect(const BisectMarkRequest& request) {
    submitAndRefresh(makeBisectMarkOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshBisectStatus();
        }
    });
}

void RepositorySession::skipBisect(const BisectSkipRequest& request) {
    submitAndRefresh(makeBisectSkipOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshBisectStatus();
        }
    });
}

void RepositorySession::resetBisect(const BisectResetRequest& request) {
    submitAndRefresh(makeBisectResetOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshBisectStatus();
        }
    });
}

// --- M5: LFS ---------------------------------------------------------------

void RepositorySession::refreshLfs() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto installation = detectLfs(*runner_, paths_, token);
        if (!installation) {
            if (installation.error().code != GitError::Code::Cancelled) {
                GitError error = std::move(installation).error();
                QMetaObject::invokeMethod(
                    this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
            }
            QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
            return;
        }

        const bool available = installation->available;
        LfsInstallation installationValue = *installation;
        QMetaObject::invokeMethod(
            this,
            [this, installationValue] { lfsInstallation_ = installationValue; },
            Qt::QueuedConnection);

        if (!available) {
            QMetaObject::invokeMethod(
                this,
                [this] {
                    emit lfsUpdated();
                    setBusy(false);
                },
                Qt::QueuedConnection);
            return;
        }

        auto patterns = lfsStore_->trackedPatterns(token);
        if (patterns) {
            lfsPatterns_.publish(std::make_shared<std::vector<std::string>>(std::move(*patterns)));
        }
        auto files = lfsStore_->listFiles(token);
        if (files) {
            lfsFiles_.publish(std::make_shared<std::vector<LfsFileInfo>>(std::move(*files)));
        }
        QMetaObject::invokeMethod(
            this,
            [this] {
                emit lfsUpdated();
                setBusy(false);
            },
            Qt::QueuedConnection);
    });
}

void RepositorySession::installLfs() {
    submitAndRefresh(makeLfsInstallOperation(), [this](bool succeeded) {
        if (succeeded) {
            refreshLfs();
        }
    });
}

void RepositorySession::trackLfsPattern(const LfsTrackRequest& request) {
    submitAndRefresh(makeLfsTrackOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshLfs();
        }
    });
}

void RepositorySession::untrackLfsPattern(const LfsUntrackRequest& request) {
    submitAndRefresh(makeLfsUntrackOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshLfs();
        }
    });
}

void RepositorySession::pullLfs(const LfsTransferRequest& request) {
    LfsTransferRequest wired = request;
    wired.askpassDir = askpass::makeRequestDir();
    if (!wired.askpassDir.empty()) {
        askpass_->start(wired.askpassDir);
    }
    submitAndRefresh(makeLfsPullOperation(wired), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshLfs();
        }
    });
}

void RepositorySession::fetchLfs(const LfsTransferRequest& request) {
    LfsTransferRequest wired = request;
    wired.askpassDir = askpass::makeRequestDir();
    if (!wired.askpassDir.empty()) {
        askpass_->start(wired.askpassDir);
    }
    submitAndRefresh(makeLfsFetchOperation(wired), [this](bool succeeded) {
        askpass_->stop();
        if (succeeded) {
            refreshLfs();
        }
    });
}

void RepositorySession::pruneLfs(const LfsPruneRequest& request) {
    submitAndRefresh(makeLfsPruneOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshLfs();
        }
    });
}

// --- M5: patch import/export ------------------------------------------------

void RepositorySession::exportPatches(const ExportPatchesRequest& request) {
    submitAndRefresh(makeExportPatchesOperation(request), nullptr);
}

void RepositorySession::applyPatchFiles(const ApplyPatchFilesRequest& request) {
    submitWorkingCopyOperation(makeApplyPatchFilesOperation(request), false);
}

void RepositorySession::importPatches(const ImportPatchesRequest& request) {
    submitWorkingCopyOperation(makeImportPatchesOperation(request), true);
}

void RepositorySession::continueImport() {
    submitWorkingCopyOperation(makeAmContinueOperation(), true);
}

void RepositorySession::skipImport() {
    submitWorkingCopyOperation(makeAmSkipOperation(), true);
}

void RepositorySession::abortImport() {
    submitWorkingCopyOperation(makeAmAbortOperation(), true);
}

// --- Phase 6: per-repository Git identity override --------------------------

void RepositorySession::refreshLocalIdentity() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto identity = localIdentityStore_->read(token);
        if (identity) {
            localIdentity_.publish(std::make_shared<LocalIdentity>(std::move(*identity)));
            QMetaObject::invokeMethod(
                this, [this] { emit localIdentityUpdated(); }, Qt::QueuedConnection);
        } else if (identity.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(identity).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::refreshEffectiveIdentity() {
    const CancellationToken token = readCancel_.token();
    setBusy(true);

    readPool_.post([this, token] {
        auto identity = localIdentityStore_->readEffective(token);
        if (identity) {
            effectiveIdentity_.publish(std::make_shared<EffectiveIdentity>(std::move(*identity)));
            QMetaObject::invokeMethod(
                this, [this] { emit effectiveIdentityUpdated(); }, Qt::QueuedConnection);
        } else if (identity.error().code != GitError::Code::Cancelled) {
            GitError error = std::move(identity).error();
            QMetaObject::invokeMethod(
                this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
        }
        QMetaObject::invokeMethod(this, [this] { setBusy(false); }, Qt::QueuedConnection);
    });
}

void RepositorySession::setLocalIdentityOverride(const SetLocalIdentityRequest& request) {
    submitAndRefresh(makeSetLocalIdentityOperation(request), [this](bool succeeded) {
        if (succeeded) {
            refreshLocalIdentity();
            refreshEffectiveIdentity();
        }
    });
}

void RepositorySession::clearLocalIdentityOverride() {
    submitAndRefresh(makeClearLocalIdentityOperation(), [this](bool succeeded) {
        if (succeeded) {
            refreshLocalIdentity();
            refreshEffectiveIdentity();
        }
    });
}

}  // namespace gbm
