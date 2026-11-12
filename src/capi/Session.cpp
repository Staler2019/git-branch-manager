#include "capi/Session.h"

#include "capi/CloneJob.h"
#include "capi/JsonCodec.h"
#include "capi/JsonWriter.h"
#include "core/base/ExceptionDiagnostic.h"
#include "core/base/FsUtil.h"
#include "core/discovery/RepoClassifier.h"
#include "core/git/AskpassHelper.h"
#include "core/git/OperationLogScope.h"
#include "core/git/OriginalOperationMessage.h"
#include "core/git/TextTraits.h"
#include "core/git/ops/CheckoutOp.h"
#include "core/workers/ThreadPool.h"

#include <algorithm>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <mutex>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace gbm::capi {

namespace {

/// Runs a callback on every exit path out of a scope, including the early
/// returns a lambda body accumulates. Local to this file because its one
/// caller, postRead()'s onAlways, serves the one place in capi where missing
/// a terminal path is silently fatal rather than merely wrong
/// (Session::dispatchRefresh): an unreported refresh leaves RefreshCoalescer
/// stuck in `running_` and every later request folds into a batch nothing
/// will ever drive.
class ScopeExit {
public:
    explicit ScopeExit(std::function<void()> onExit) : onExit_(std::move(onExit)) {}

    ~ScopeExit() {
        if (onExit_) {
            onExit_();
        }
    }

    ScopeExit(const ScopeExit&) = delete;
    ScopeExit& operator=(const ScopeExit&) = delete;
    ScopeExit(ScopeExit&&) = delete;
    ScopeExit& operator=(ScopeExit&&) = delete;

private:
    std::function<void()> onExit_;
};

// The process-wide registry of open Sessions, keyed implicitly by work tree
// (Session::paths().workDir()) -- see Session::dispatchOperationLogRecord()'s
// doc comment for why this exists: gbm::Log's operation sink is a single
// process-wide callback with no notion of which session a given git
// invocation belongs to, so the sink has to fan the record back out itself.
std::mutex& liveSessionsMutex() {
    static std::mutex mutex;
    return mutex;
}

std::vector<Session*>& liveSessions() {
    static std::vector<Session*> sessions;
    return sessions;
}

void registerLiveSession(Session* session) {
    std::lock_guard<std::mutex> lock(liveSessionsMutex());
    liveSessions().push_back(session);
}

void unregisterLiveSession(Session* session) {
    std::lock_guard<std::mutex> lock(liveSessionsMutex());
    auto& sessions = liveSessions();
    sessions.erase(std::remove(sessions.begin(), sessions.end(), session), sessions.end());
}

std::mutex& gitInstallationMutex() {
    static std::mutex mutex;
    return mutex;
}

bool& gitInstallationResolved() {
    static bool resolved = false;
    return resolved;
}

GitResult<GitInstallation>& cachedGitInstallation() {
    static GitResult<GitInstallation> cached = fail(GitError::Code::NotFound, "not yet resolved");
    return cached;
}

// The reply payloads a read builds on its ordinary path and again in its
// postRead() failure reply, so the two cannot drift apart: the caller waits
// on the reply by a key (requestId, destPath, source, path) that
// GBM_EVENT_ERROR_OCCURRED does not carry.

std::string messagePayload(const std::string& message, const GitError* error = nullptr) {
    std::string payload = "{\"message\":";
    jsonAppendEscaped(payload, message);
    if (error != nullptr) {
        payload += ",\"error\":";
        payload += toJson(*error);
    }
    payload += '}';
    return payload;
}

std::string squashMessagePayload(const std::string& source,
                                 const std::string& headOid,
                                 const std::string& sourceOid,
                                 const std::string& message,
                                 const GitError* error) {
    std::string payload = "{\"source\":";
    jsonAppendEscaped(payload, source);
    payload += ",\"headOid\":";
    jsonAppendEscaped(payload, headOid);
    payload += ",\"sourceOid\":";
    jsonAppendEscaped(payload, sourceOid);
    payload += ",\"message\":";
    jsonAppendEscaped(payload, message);
    if (error != nullptr) {
        payload += ",\"error\":";
        payload += toJson(*error);
    }
    payload += '}';
    return payload;
}

std::string workingTreeContentPayload(const std::string& path,
                                      const std::string& content,
                                      bool editable) {
    std::string payload = "{\"path\":";
    jsonAppendEscaped(payload, path);
    payload += ",\"content\":";
    jsonAppendEscaped(payload, content);
    payload += ",\"editable\":";
    jsonAppendBool(payload, editable);
    payload += '}';
    return payload;
}

std::string fileAtRevisionPayload(const std::string& revision,
                                  const std::string& path,
                                  const std::string& destPath,
                                  const GitError* error) {
    std::string payload = "{\"revision\":";
    jsonAppendEscaped(payload, revision);
    payload += ",\"path\":";
    jsonAppendEscaped(payload, path);
    payload += ",\"destPath\":";
    jsonAppendEscaped(payload, destPath);
    payload += ",\"succeeded\":";
    jsonAppendBool(payload, error == nullptr);
    if (error != nullptr) {
        payload += ",\"error\":";
        payload += toJson(*error);
    }
    payload += '}';
    return payload;
}

std::string branchDeletionProbePayload(std::uint64_t requestId,
                                       const std::vector<BranchDeletionProbe>& probes,
                                       const GitError* error) {
    std::string payload = "{\"requestId\":";
    jsonAppendInt(payload, static_cast<std::int64_t>(requestId));
    payload += ",\"error\":";
    payload += error != nullptr ? toJson(*error) : std::string("null");
    payload += ",\"probes\":";
    payload += error != nullptr ? std::string("[]") : toJson(probes);
    payload += '}';
    return payload;
}
}  // namespace

GitResult<GitInstallation> sharedGitInstallation() {
    std::lock_guard<std::mutex> lock(gitInstallationMutex());
    if (!gitInstallationResolved()) {
        // GBM_GIT_PATH lets someone with several gits installed (or one
        // blocked from running by an OS policy the app cannot see around, e.g.
        // macOS sandboxing) pin the exact executable rather than depend on
        // GitExecutable::detect()'s PATH/fallback search order.
        const char* overridePath = std::getenv("GBM_GIT_PATH");
        cachedGitInstallation() = GitExecutable::detect(
            overridePath != nullptr ? fsutil::pathFromUtf8(overridePath) : std::filesystem::path{});
        // Only a *successful* detection is cached. Detection failing once (git
        // not yet installed, a permission problem not yet fixed) must not lock
        // that failure in for the rest of the process's lifetime -- the app has
        // no way to prompt a restart, so every later Session::open() would
        // otherwise keep failing even after the user fixes the underlying
        // problem.
        gitInstallationResolved() = cachedGitInstallation().hasValue();
    }
    return cachedGitInstallation();
}

void ensureOperationLogSinkInstalled() {
    static std::once_flag flag;
    std::call_once(flag,
                   [] { Log::instance().setOperationSink(&Session::dispatchOperationLogRecord); });
}

void resetSharedGitInstallationForTest() {
    std::lock_guard<std::mutex> lock(gitInstallationMutex());
    gitInstallationResolved() = false;
}

ThreadPool& sharedReadPool() {
    static ThreadPool pool("gbm_capi_read", ThreadPool::defaultThreadCount());
    return pool;
}

#if defined(GBM_CAPI_TEST_EXPORTS)
namespace {

struct ArmedFailure {
    std::mutex mutex;
    std::string where;
    const char* what;
};

ArmedFailure& armedReadFailure() {
    static ArmedFailure armed{{}, {}, "injected read failure"};
    return armed;
}

ArmedFailure& armedSubmitFailure() {
    static ArmedFailure armed{{}, {}, "injected submit failure"};
    return armed;
}

/// Compare-and-clear, so a name armed once fails exactly one read (or
/// submit) under it and none under any other name.
void throwIfArmedForTest(ArmedFailure& armed, const std::string& where) {
    {
        std::lock_guard<std::mutex> lock(armed.mutex);
        if (where.empty() || armed.where != where) {
            return;
        }
        armed.where.clear();
    }
    throw std::runtime_error(armed.what);
}

void throwIfArmedForTest(const std::string& where) {
    throwIfArmedForTest(armedReadFailure(), where);
}

void arm(ArmedFailure& armed, std::string where) {
    std::lock_guard<std::mutex> lock(armed.mutex);
    armed.where = std::move(where);
}

}  // namespace

void failReadForTest(std::string where) {
    arm(armedReadFailure(), std::move(where));
}

void failSubmitForTest(std::string where) {
    arm(armedSubmitFailure(), std::move(where));
}
#endif

namespace {

/// The one place a Session funnel hands work to its OperationRunner. Both
/// arguments are taken by value, so by the time anything here throws the
/// operation and its callback have left the funnel's hands, as they have
/// when the runner's own push_back throws.
OperationRunner::Handle submitToRunner(OperationRunner& runner,
                                       std::unique_ptr<Operation> operation,
                                       OperationRunner::CompletionCallback onDone,
                                       const std::string& where) {
#if defined(GBM_CAPI_TEST_EXPORTS)
    throwIfArmedForTest(armedSubmitFailure(), where);
#else
    (void)where;
#endif
    return runner.submit(std::move(operation), std::move(onDone));
}

/// For a callback a funnel or postRead still owes after the hand-off failed:
/// it runs on an FFI caller's thread, where an escaping throw would end the
/// process.
void runGuarded(const std::function<void()>& fn, std::string_view where) {
    try {
        if (fn) {
            fn();
        }
    } catch (...) {
        reportCurrentException(where);
    }
}

void reportException(const std::exception_ptr& failure, std::string_view where) {
    try {
        std::rethrow_exception(failure);
    } catch (...) {
        reportCurrentException(where);
    }
}

}  // namespace

namespace {

/// Same shape as OperationRunner's own catch, so Dart reads it like any other
/// failed git call. Called from inside a catch block.
void replyReadFailed(const std::function<void(const GitError&)>& onFailure) {
    try {
        onFailure(GitError(
            GitError::Code::Unknown, "The read failed unexpectedly", describeCurrentException()));
    } catch (...) {
        reportCurrentException("postRead failure reply");
    }
}

/// `job` is taken by value, so by the time anything here throws the read has
/// left postRead's hands, as it has when the pool's own push_back throws.
void handToReadPool(ReadLane lane, std::function<void()> job, const std::string& where) {
#if defined(GBM_CAPI_TEST_EXPORTS)
    throwIfArmedForTest("post:" + where);
#else
    (void)where;
#endif
    if (lane == ReadLane::Front) {
        sharedReadPool().postFront(std::move(job));
    } else {
        sharedReadPool().post(std::move(job));
    }
}

}  // namespace

void postRead(ReadLane lane,
              std::string where,
              std::function<void()> task,
              std::function<void(const GitError&)> onFailure,
              std::function<void()> onAlways) {
    // Shared with `run`, so a hand-off that throws after `run` has been moved
    // away can still answer from here.
    const auto failure =
        std::make_shared<const std::function<void(const GitError&)>>(std::move(onFailure));
    const auto always = std::make_shared<const std::function<void()>>(std::move(onAlways));
    try {
        auto run = [where, task = std::move(task), failure, always]() {
            // First, so it covers a throw before `task` starts -- the injected one
            // below, which is why dispatchRefresh's terminal-path guard lives here.
            const ScopeExit runAlways(*always);
            try {
#if defined(GBM_CAPI_TEST_EXPORTS)
                throwIfArmedForTest(where);
#endif
                task();
            } catch (...) {
                reportCurrentException(where);
                replyReadFailed(*failure);
            }
        };
        handToReadPool(lane, std::move(run), where);
    } catch (...) {
        // Nothing reached a worker: answer here, on the caller's thread. No
        // call site holds a lock either callback takes.
        reportCurrentException(where);
        replyReadFailed(*failure);
        runGuarded(*always, "postRead onAlways");
    }
}

std::unique_ptr<Session> Session::open(std::string workDir,
                                       std::string gitDir,
                                       std::string commonDir,
                                       GitError* outError) {
    const GitResult<GitInstallation> installation = sharedGitInstallation();
    if (!installation) {
        if (outError != nullptr) {
            *outError = installation.error();
        }
        return nullptr;
    }

    // A linked worktree's `<workDir>/.git` is a `gitdir:` pointer file, and the
    // Flutter side opens every repository as exactly that path with no
    // commonDir (`RepoIdentity.forWorkDir`). Left unresolved, every
    // per-worktree stat (MERGE_HEAD, rebase-merge/, index.lock) would look
    // under a file and report a clean tree mid-merge.
    std::filesystem::path gitDirPath = fsutil::pathFromUtf8(gitDir);
    std::filesystem::path commonDirPath = fsutil::pathFromUtf8(commonDir);
    std::error_code ec;
    if (std::filesystem::is_regular_file(gitDirPath, ec)) {
        if (auto target = RepoClassifier::resolveGitDirFile(gitDirPath, gitDirPath.parent_path())) {
            gitDirPath = std::move(*target);
            if (commonDirPath.empty()) {
                commonDirPath = RepoClassifier::resolveCommonDir(gitDirPath);
            }
        }
    }
    RepoPaths paths(fsutil::pathFromUtf8(workDir), std::move(gitDirPath), std::move(commonDirPath));
    if (!paths.isValid()) {
        if (outError != nullptr) {
            *outError = GitError(GitError::Code::InvalidArgument, "gitDir must not be empty");
        }
        return nullptr;
    }

    std::unique_ptr<IProcessRunner> runner = makeProcessRunner(installation.value().executable);
    return std::unique_ptr<Session>(
        new Session(installation.value(), std::move(paths), std::move(runner)));
}

Session::Session(GitInstallation installation,
                 RepoPaths paths,
                 std::unique_ptr<IProcessRunner> runner)
    : installation_(std::move(installation)),
      paths_(std::move(paths)),
      runner_(std::move(runner)),
      refStore_(std::make_unique<RefStore>(*runner_, paths_)),
      history_(std::make_unique<HistoryProvider>(*runner_, paths_)),
      operations_(std::make_unique<OperationRunner>(*runner_, paths_)),
      workingCopyStatusReader_(std::make_unique<WorkingCopyStatusReader>(*runner_, paths_)),
      diffs_(std::make_unique<DiffService>(*runner_, paths_)),
      stashStore_(std::make_unique<StashStore>(*runner_, paths_)),
      worktreeStore_(std::make_unique<WorktreeStore>(*runner_, paths_)),
      remoteStore_(std::make_unique<RemoteStore>(*runner_, paths_)),
      compareStore_(std::make_unique<CompareStore>(*runner_, paths_)),
      squashMessageStore_(std::make_unique<SquashMessageStore>(*runner_, paths_)),
      preparedMessageStore_(std::make_unique<PreparedMessageStore>(*runner_, paths_)),
      blobStore_(std::make_unique<BlobStore>(installation_.executable, paths_)),
      blameStore_(std::make_unique<BlameStore>(*runner_, paths_)),
      commitMetaStore_(std::make_unique<CommitMetaStore>(installation_.executable, paths_)),
      fileHistoryStore_(std::make_unique<FileHistoryStore>(*runner_, paths_)),
      reflogStore_(std::make_unique<ReflogStore>(*runner_, paths_)),
      submoduleStore_(std::make_unique<SubmoduleStore>(*runner_, paths_)),
      bisectStore_(std::make_unique<BisectStore>(*runner_, paths_)),
      lfsStore_(std::make_unique<LfsStore>(*runner_, paths_)),
      localIdentityStore_(std::make_unique<LocalIdentityStore>(*runner_, paths_)),
      refreshTimer_([this]() { onRefreshTimerFired(); }) {
    ensureOperationLogSinkInstalled();
    registerLiveSession(this);
}

Session::~Session() {
    // unregisterLiveSession() first, so gbm::Log's sink (which can fire from
    // any thread doing a git invocation) can never look this Session up
    // again once its teardown has started.
    unregisterLiveSession(this);

    // A working-copy operation is not in inFlight_, so cancelOperations(0) below
    // does not reach it: without this, each queued one waits out a live
    // index.lock in turn, on the thread closing the session.
    operations_->prepareForShutdown();

    // Cancel before draining, not merely alongside it: cancelOperations(0)
    // trips every in-flight/queued operation's token, so operations_->drain()
    // below waits on work this session's own cancellation already told to
    // stop instead of waiting for it to finish naturally -- ~~unbounded for
    // the ~28 commands GitCommand runs with no deadline~~ up to a whole
    // deadline (effectiveDeadlines(); every command has one since 2026-10-07). A cancelled
    // operation takes the failure branch, so it never reaches the onSuccess
    // path that chains a new sharedReadPool() post -- the ordering
    // invariant the comment below describes is unaffected by cancelling
    // first.
    cancelOperations(0);

    // operations_->drain() MUST run before historyCancel_/sharedReadPool()
    // below, not after: OperationRunner::drain() only returns once its
    // worker thread is idle, and that thread runs a submitted operation's
    // completion callback (OperationRunner.cpp's queued.onDone(...)) to
    // completion -- including everything the callback does -- before it
    // clears the busy flag drain() waits on. Several of those callbacks
    // (e.g. pullChanges()'s/fetchRemote()'s onSuccess, which calls
    // refreshHistory()) themselves post a *new* task to sharedReadPool().
    // Draining the shared pool first, as this used to, could run right
    // before that post() call rather than after it: the new task would
    // still be posted afterwards, live on unseen by that drain, and only
    // get to run once this destructor has gone on to free refStore_ and
    // friends below -- a real, ASan-confirmed use-after-free reachable from
    // any caller that closes a session immediately after an operation that
    // chains a refresh finishes (not merely a test-timing artifact: the
    // Flutter side's dispose lifecycle can race the same way). Draining
    // operations_ first guarantees any such post() has already happened,
    // so the sharedReadPool() drain below actually catches it.
    operations_->drain();

    // After operations_->drain(), because those completion callbacks are one
    // of the two things that arm this timer; before the pool drain below,
    // because firing it posts a *new* task onto sharedReadPool(). Any
    // armed-but-unfired deadline is simply dropped -- the session is going
    // away, so the refresh it would have run has no one to report to. A late
    // arm() from a still-unwinding completion path is a no-op after this
    // (DelayTimer::arm()'s contract).
    refreshTimer_.stop();

    // sharedReadPool() is process-wide (see its doc comment), so this is
    // coarser than RepositorySession::cancelPendingReads() +
    // ThreadPool::cancelQueuedAndDrain(), which safely assume a pool
    // dedicated to the one session being closed: cancelQueuedAndDrain() here
    // also discards any *other* session's not-yet-started work. Acceptable
    // for M0/M1 (repositories are opened and closed one at a time -- see the
    // workspace route's lazy-open/on-dispose lifecycle in the plan), but a
    // real multi-session-concurrently-open story needs a per-session
    // cancellation scope instead of a pool-wide drain. Still required here:
    // without it, a task queued or running on the shared pool could call
    // back into this Session after its destructor returns.
    {
        std::lock_guard<std::mutex> lock(refreshMutex_);
        historyCancel_.cancel();
    }
    // Cancels every background read this session posted to the shared pool,
    // for the same reason cancelOperations(0) above precedes
    // operations_->drain(): without it, cancelQueuedAndDrain() below waits
    // for this session's own in-flight reads to finish naturally rather than
    // being told to stop. See readCancel_'s own doc comment in Session.h.
    readCancel_.cancel();
    sharedReadPool().cancelQueuedAndDrain();

    askpass_.stop();
    // Explicit, not relying on member-destruction order: commitMetaStore_ and
    // blobStore_ are the stores that own a long-lived child process (both wrap
    // a `cat-file --batch` co-process; the others spawn per-call), so end them
    // up front alongside askpass_ rather than waiting for the destructor to
    // reach them.
    commitMetaStore_->stop();
    blobStore_->stop();
}

void Session::registerCallback(GbmEventCallback callback, void* userData) {
    callbacks_.set(static_cast<GbmSessionHandle>(this), callback, userData);
}

RepoState Session::repoState() const {
    return operations_->state();
}

bool Session::removeStaleIndexLock() {
    return operations_->removeStaleIndexLock();
}

std::uint64_t Session::refreshHistory() {
    // Not "cancel whatever is running, then post mine". That is what this
    // used to do, and it terminated a perfectly healthy `git` process on
    // every refresh that landed on a busy session -- the exit 143
    // (128 + SIGTERM) `for-each-ref` / `rev-list` lines that made the log
    // drawer look like the app was failing. See
    // HistoryRefreshApiTest.ABurstOfRefreshesTerminatesNoGitProcess.
    //
    // A request while a walk is running folds into a dirty bit instead, and
    // finishRefresh() drives the single follow-up. Nothing is cancelled, so
    // no record is produced at all.
    //
    // Both flags are always true and the origin is always Explicit: capi has
    // exactly one refresh entry point and it has always read refs *and*
    // walked history, and GraphUpdateOrigin is not plumbed through the FFI
    // surface at all. The merged batch is therefore constant today -- the
    // contract (takePending() exactly once per dispatch) is still honoured
    // so that a future refs-only entry point is a change of arguments rather
    // than a change of mechanism.
    bool needsArm = false;
    std::uint64_t request = 0;
    {
        std::lock_guard<std::mutex> lock(refreshMutex_);
        request = ++refreshRequestSeq_;
        needsArm = refreshCoalescer_.request(/*wantsRefs=*/true,
                                             /*wantsHistory=*/true,
                                             GraphUpdateOrigin::Explicit) ==
                   RefreshCoalescer::RefreshAction::Arm;
    }
    if (needsArm) {
        refreshTimer_.arm(RefreshCoalescer::kDelay);
    }
    return request;
}

void Session::onRefreshTimerFired() {
    RefreshCoalescer::Generation generation = 0;
    CancellationToken token;
    std::uint64_t covers = 0;
    {
        std::lock_guard<std::mutex> lock(refreshMutex_);
        generation = refreshCoalescer_.onTimeout();
        if (generation == 0) {
            // The quiet period has not actually elapsed -- a request re-armed
            // the timer after this firing was already scheduled.
            return;
        }
        (void)refreshCoalescer_.takePending();
        covers = refreshRequestSeq_;
        token = historyCancel_.token();
    }
    dispatchRefresh(generation, token, covers);
}

void Session::finishRefresh(RefreshCoalescer::Generation generation) {
    bool again = false;
    {
        std::lock_guard<std::mutex> lock(refreshMutex_);
        again = refreshCoalescer_.onFinished(generation);
    }
    // Outside the lock: arm() takes the timer's own lock and the timer thread
    // takes refreshMutex_ from its callback, so holding both at once here
    // would be the only place in this file where a lock order exists at all.
    if (again) {
        // Debouncer::finish()'s own contract -- "fire immediately, no second
        // wait" -- rather than a second kDelay window, so a request that
        // arrived mid-walk is not made to wait twice.
        refreshTimer_.arm(std::chrono::milliseconds{0});
    }
}

std::function<void(const GitError&)> Session::errorReply() {
    return
        [this](const GitError& error) { callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(error)); };
}

bool Session::claimPublishLocked(RefreshCoalescer::Generation generation) {
    if (generation < publishedGeneration_) {
        return false;
    }
    publishedGeneration_ = generation;
    return true;
}

void Session::dispatchRefresh(RefreshCoalescer::Generation generation,
                              CancellationToken token,
                              std::uint64_t coversRequest) {
    postRead(
        ReadLane::Back,
        "Session::dispatchRefresh",
        [this, generation, token, coversRequest]() {
            const GitResult<RefSnapshotPtr> refsResult = refStore_->load(token);
            if (!refsResult) {
                if (!token.isCancelled()) {
                    callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(refsResult.error()));
                }
                return;
            }
            {
                std::lock_guard<std::mutex> lock(graphMutex_);
                if (!claimPublishLocked(generation)) {
                    return;
                }
                refs_ = refsResult.value();
            }
            callbacks_.emit(GBM_EVENT_REFS_UPDATED,
                            "{\"coversRequest\":" + std::to_string(coversRequest) + "}");

            HistoryQuery query;
            query.seedRefs = RefStore::historySeedRefs(*refsResult.value());
            {
                std::lock_guard<std::mutex> lock(graphMutex_);
                // Only refs that still exist. rev-list aborts the *entire* walk
                // with "unknown revision" on one stale name, so a branch deleted
                // or pruned while the filter was set would blank the whole graph
                // rather than just stop narrowing it. Dropping every stale name
                // can empty the list, which falls back to the unfiltered walk --
                // the same thing the user sees after clearing the filter.
                for (const std::string& ref : historyIncludeRefs_) {
                    if (RefStore::refExists(*refsResult.value(), ref)) {
                        query.includeRefs.push_back(ref);
                    }
                }
                query.firstParentOnly = historyFirstParentOnly_;
                query.noMerges = historyNoMerges_;
            }

            // Lane 0 belongs to HEAD's branch (spec P02's 「目前開發中的分支永遠佔
            // lane 0」).
            //
            // **Only for an unfiltered walk.** A narrowed one need not contain
            // HEAD's tip at all, and a reservation nothing claims leaves the
            // leftmost column blank for the whole graph. `includeRefs` is checked
            // after the loop above, because a filter whose refs have all gone stale
            // is dropped there and falls back to the unfiltered walk -- reading the
            // member instead would reserve nothing on exactly that path.
            if (query.includeRefs.empty()) {
                // Deliberately re-read HEAD here rather than reusing
                // refsResult's head.target: that snapshot was captured *before*
                // refStore_->load()'s own for-each-ref call, and the walk below
                // spawns a third, independent process that re-resolves
                // historySeedRefs()'s HEAD *name* fresh, at whatever moment it
                // actually runs. Anything that moves the branch tip in that
                // window -- another tool touching this repository, e.g. -- left
                // this reservation permanently unclaimed by the row that really
                // is current, so lane 0 stayed blank and History's
                // uncommitted-row connector never drew. Process creation costs
                // roughly two orders of magnitude more on Windows than on Linux
                // (docs/reports/windows-process-cost.md), which is why that
                // window matters there in particular. This costs one extra git
                // process on every unfiltered refresh -- the same cost
                // readHead()'s single-invocation merge was written to avoid --
                // but a stale trunk-tip identity is a correctness bug, not a
                // rounding error.
                //
                // A failure of this second read must not cost the whole history
                // walk over a connector-only concern: refs_ and REFS_UPDATED
                // (already published above) keep today's snapshot regardless, so
                // falling back to its target here is free.
                const GitResult<HeadInfo> freshHead = refStore_->readHead(token);
                query.trunkTip = freshHead ? freshHead->target : refsResult.value()->head.target;
            }

            const GitResult<GraphSnapshotPtr> walkResult = history_->walk(
                query,
                [this, generation](GraphSnapshotPtr chunk) {
                    publishGraph(std::move(chunk), generation);
                },
                token);

            if (!walkResult && !token.isCancelled()) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(walkResult.error()));
            }
        },
        errorReply(),
        // onFinished() must run on *every* terminal path: miss one and the
        // coalescer stays running_ forever, every later request folds into a
        // dirty bit nothing will ever drive, and refreshes silently stop.
        // postRead's onAlways rather than a guard inside the body, which has
        // three early returns and is not even entered when a read fails before
        // it starts -- the same reasoning that put an onAlways hook on
        // submitOperation().
        [this, generation]() { finishRefresh(generation); });
}

void Session::setHistoryFilter(std::vector<std::string> includeRefs,
                               bool firstParentOnly,
                               bool noMerges) {
    {
        std::lock_guard<std::mutex> lock(graphMutex_);
        historyIncludeRefs_ = std::move(includeRefs);
        historyFirstParentOnly_ = firstParentOnly;
        historyNoMerges_ = noMerges;
    }

    // fireNow(), not request(): the Flutter side already debounces the filter
    // box by 250 ms (branchFilterQueryProvider -> historyFilterRequestProvider),
    // so stacking another 150 ms window on top would make a settled query wait
    // twice. This is also the one caller that genuinely supersedes an
    // in-flight walk rather than folding into it -- that walk is now applying
    // a filter the user has already changed, so letting it finish is pure
    // waste. Cancelling it is what leaves a `cancelled` record behind; a
    // deliberate, user-initiated filter change is rare and honest about it,
    // unlike the per-operation churn refreshHistory() used to produce.
    //
    // fireNow() also absorbs a refreshHistory() request still in the delay
    // window, or folded into the walk this cancels, and leaves no follow-up
    // for it -- so this dispatch must report it as covered.
    RefreshCoalescer::Generation generation = 0;
    CancellationToken token;
    std::uint64_t covers = 0;
    {
        std::lock_guard<std::mutex> lock(refreshMutex_);
        historyCancel_.cancel();
        historyCancel_ = CancellationSource();
        token = historyCancel_.token();
        generation = refreshCoalescer_.fireNow(/*wantsRefs=*/true,
                                               /*wantsHistory=*/true,
                                               GraphUpdateOrigin::Explicit);
        (void)refreshCoalescer_.takePending();
        covers = refreshRequestSeq_;
    }
    dispatchRefresh(generation, token, covers);
}

GraphSnapshotPtr Session::currentGraph() const {
    std::lock_guard<std::mutex> lock(graphMutex_);
    return graph_;
}

RefSnapshotPtr Session::currentRefs() const {
    std::lock_guard<std::mutex> lock(graphMutex_);
    return refs_;
}

GraphSnapshotPtr Session::exportGraph() {
    exportedGraph_ = currentGraph();
    return exportedGraph_;
}

void Session::releaseExportedGraph() {
    exportedGraph_.reset();
}

void Session::publishGraph(GraphSnapshotPtr snapshot, RefreshCoalescer::Generation generation) {
    const bool complete = snapshot && snapshot->complete;
    {
        std::lock_guard<std::mutex> lock(graphMutex_);
        // Dropped rather than published when a newer dispatch has already
        // written here. Nothing cancels a superseded walk any more (see
        // refreshHistory()), so a walk that setHistoryFilter() overtook can
        // still be streaming chunks -- and its `complete:true` would tell
        // Dart the *newer* walk had finished.
        if (!claimPublishLocked(generation)) {
            return;
        }
        graph_ = std::move(snapshot);
    }
    std::string payload = "{\"complete\":";
    payload += complete ? "true" : "false";
    payload += '}';
    callbacks_.emit(GBM_EVENT_GRAPH_UPDATED, payload);
}

bool Session::checkout(CheckoutRequest request) {
    // The worktree list is republished by submitOperation, with the refs.
    return submitOperation(makeCheckoutOperation(std::move(request)),
                           /*refreshHistoryOnSuccess=*/true);
}

void Session::createBranch(CreateBranchRequest request) {
    submitOperation(makeCreateBranchOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true);
}

void Session::renameBranch(RenameBranchRequest request) {
    // Only the remote half can prompt for credentials, so only it needs the
    // askpass watch -- same conditional as deleteTag() below.
    const bool needsAskpass = request.renameRemote;
    if (needsAskpass) {
        request.askpassDir = beginAskpass();
    }
    submitOperation(
        makeRenameBranchOperation(std::move(request)),
        /*refreshHistoryOnSuccess=*/true,
        /*onSuccess=*/nullptr,
        /*onAlways=*/needsAskpass ? std::function<void()>([this]() { endAskpass(); }) : nullptr);
}

bool Session::deleteBranch(DeleteBranchRequest request) {
    return submitOperation(makeDeleteBranchOperation(std::move(request)),
                           /*refreshHistoryOnSuccess=*/true);
}

void Session::resetTo(ResetRequest request) {
    submitOperation(makeResetOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::maybeRefreshIndex() {
    {
        const auto now = std::chrono::steady_clock::now();
        std::lock_guard<std::mutex> lock(indexRefreshMutex_);
        if (!shouldRefreshIndex(lastIndexRefresh_, now)) {
            return;
        }
        lastIndexRefresh_ = now;
    }
    operations_->submit(makeRefreshIndexOperation(), nullptr);
}

void Session::refreshWorkingCopy() {
    maybeRefreshIndex();
    postRead(
        ReadLane::Back,
        "Session::refreshWorkingCopy",
        [this]() {
            const GitResult<WorkingCopyStatusPtr> result =
                workingCopyStatusReader_->read(readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            {
                std::lock_guard<std::mutex> lock(workingCopyMutex_);
                workingCopyStatus_ = result.value();
            }
            callbacks_.emitEmpty(GBM_EVENT_WORKING_COPY_STATUS_UPDATED);
        },
        errorReply());
}

WorkingCopyStatusPtr Session::currentWorkingCopyStatus() const {
    std::lock_guard<std::mutex> lock(workingCopyMutex_);
    return workingCopyStatus_;
}

void Session::requestWorkingCopyDiff(std::string path, std::string oldPath, bool staged) {
    // postFront, like requestBlame(): the user is looking at this exact file
    // right now, and the diff pane must not sit behind a refreshRepoStatus()
    // sweep's other members -- [CPP-interactive-reads-go-to-the-front].
    postRead(
        ReadLane::Front,
        "Session::requestWorkingCopyDiff",
        [this, path = std::move(path), oldPath = std::move(oldPath), staged]() {
            emitWorkingCopyDiff(
                path, oldPath, staged, DiffOptions{}, GBM_EVENT_WORKING_COPY_DIFF_READY);
        },
        errorReply());
}

void Session::requestWorkingCopyFullDiff(std::string path, std::string oldPath, bool staged) {
    // post, not postFront: this only fills the rows between the -U3 cards the
    // user is already looking at, so it must not take an interactive read's
    // place in the queue -- [CPP-interactive-reads-go-to-the-front].
    postRead(
        ReadLane::Back,
        "Session::requestWorkingCopyFullDiff",
        [this, path = std::move(path), oldPath = std::move(oldPath), staged]() {
            emitWorkingCopyDiff(path,
                                oldPath,
                                staged,
                                DiffOptions::fullFile(),
                                GBM_EVENT_WORKING_COPY_FULL_DIFF_READY);
        },
        errorReply());
}

void Session::emitWorkingCopyDiff(const std::string& path,
                                  const std::string& oldPath,
                                  bool staged,
                                  const DiffOptions& options,
                                  int32_t eventType) {
    // A staged rename's old path joins the pathspec: with the new path alone
    // git never sees the deleted half and reports the whole file as added.
    // Index vs HEAD only -- git does no rename detection against the work
    // tree, and the unstaged side's untracked fallback needs exactly one path.
    std::vector<std::string> pathspec{path};
    const bool pairsARename = staged && !oldPath.empty() && oldPath != path;
    if (pairsARename) {
        pathspec.insert(pathspec.begin(), oldPath);
    }
    const GitResult<DiffService::ParsedDiffPtr> result =
        diffs_->workingTreeDiff(staged, pathspec, options, readCancel_.token());
    if (!result) {
        callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
        return;
    }
    // Two pathspecs can answer with two files -- a new file staged at the old
    // path since the status was read -- and git sorts them by path, so
    // either may come first. The reply describes the one path it names, so
    // keep only that.
    ParsedDiff onlyRequested;
    const ParsedDiff* reply = result.value().get();
    if (pairsARename) {
        onlyRequested = *reply;
        std::erase_if(onlyRequested.files,
                      [&path](const DiffFile& file) { return file.newPath != path; });
        reply = &onlyRequested;
    }
    std::string payload = "{\"path\":";
    jsonAppendEscaped(payload, path);
    payload += ",\"staged\":";
    jsonAppendBool(payload, staged);
    payload += ",\"diff\":";
    payload += toJson(*reply);
    payload += '}';
    callbacks_.emit(eventType, payload);
}

bool Session::submitWorkingCopyOperationReading(
    std::unique_ptr<Operation> operation, std::function<void(const OperationOutcome&)> onSuccess) {
    try {
        submitToRunner(
            *operations_,
            std::move(operation),
            [this, onSuccess = std::move(onSuccess)](OperationOutcome outcome) {
                refreshUndoJournalCache();
                callbacks_.emit(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, toJson(outcome));
                if (outcome.succeeded && onSuccess) {
                    onSuccess(outcome);
                }
            },
            "Session::submitWorkingCopyOperationReading");
    } catch (...) {
        reportCurrentException("Session::submitWorkingCopyOperationReading");
        return false;
    }
    return true;
}

bool Session::submitWorkingCopyOperation(std::unique_ptr<Operation> operation,
                                         std::function<void()> onSuccess,
                                         std::function<void()> onAlways) {
    // Shared with the callback, so a hand-off that throws after the callback
    // has been moved away can still end what the caller began (an askpass
    // watch, say).
    const auto always = std::make_shared<const std::function<void()>>(std::move(onAlways));
    try {
        submitToRunner(
            *operations_,
            std::move(operation),
            [this, onSuccess = std::move(onSuccess), always](OperationOutcome outcome) {
                const bool succeeded = outcome.succeeded;
                refreshUndoJournalCache();
                callbacks_.emit(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED, toJson(outcome));
                if (*always) {
                    (*always)();
                }
                if (succeeded && onSuccess) {
                    onSuccess();
                }
            },
            "Session::submitWorkingCopyOperation");
    } catch (...) {
        reportCurrentException("Session::submitWorkingCopyOperation");
        runGuarded(*always, "Session::submitWorkingCopyOperation onAlways");
        return false;
    }
    return true;
}

void Session::stageFiles(std::vector<std::string> paths) {
    submitWorkingCopyOperation(makeStageFilesOperation(StageFilesRequest{std::move(paths)}),
                               [this]() { refreshWorkingCopy(); });
}

void Session::unstageFiles(std::vector<std::string> paths) {
    submitWorkingCopyOperation(makeUnstageFilesOperation(UnstageFilesRequest{std::move(paths)}),
                               [this]() { refreshWorkingCopy(); });
}

void Session::stageHunk(std::string path, std::size_t hunkIndex) {
    PartialStageRequest request;
    request.path = std::move(path);
    request.staged = false;
    request.hunkIndex = hunkIndex;
    submitWorkingCopyOperation(makePartialStageOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::unstageHunk(std::string path, std::string oldPath, std::size_t hunkIndex) {
    PartialStageRequest request;
    request.path = std::move(path);
    request.oldPath = std::move(oldPath);
    request.staged = true;
    request.hunkIndex = hunkIndex;
    submitWorkingCopyOperation(makePartialStageOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::stageLines(std::string path,
                         std::size_t hunkIndex,
                         std::vector<std::size_t> lineIndices) {
    PartialStageRequest request;
    request.path = std::move(path);
    request.staged = false;
    request.hunkIndex = hunkIndex;
    request.lineIndices = std::move(lineIndices);
    submitWorkingCopyOperation(makePartialStageOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::unstageLines(std::string path,
                           std::string oldPath,
                           std::size_t hunkIndex,
                           std::vector<std::size_t> lineIndices) {
    PartialStageRequest request;
    request.path = std::move(path);
    request.oldPath = std::move(oldPath);
    request.staged = true;
    request.hunkIndex = hunkIndex;
    request.lineIndices = std::move(lineIndices);
    submitWorkingCopyOperation(makePartialStageOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::discardLines(std::string path,
                           std::size_t hunkIndex,
                           std::vector<std::size_t> lineIndices) {
    DiscardLinesRequest request;
    request.path = std::move(path);
    request.hunkIndex = hunkIndex;
    request.lineIndices = std::move(lineIndices);
    submitWorkingCopyOperation(makeDiscardLinesOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::commitChanges(CommitRequest request) {
    submitWorkingCopyOperation(makeCommitOperation(std::move(request)), [this]() {
        refreshWorkingCopy();
        refreshHistory();
        refreshWorktrees();
    });
}

std::size_t Session::cancelOperations(std::uint64_t id) {
    // Copied out under the lock and tripped outside it: `cancel()` runs the
    // token's callbacks inline, and one of those reaches into ProcessRunner to
    // kill a live git process -- not work to do while holding a mutex the
    // completion callback also takes.
    std::vector<CancellationSource> targets;
    {
        std::lock_guard<std::mutex> lock(inFlightMutex_);
        for (auto& [key, source] : inFlight_) {
            if (id == 0 || key == id) {
                targets.push_back(source);
            }
        }
    }
    for (auto& source : targets) {
        source.cancel();
    }
    return targets.size();
}

std::int32_t Session::cancelOperation(std::uint64_t id) {
    if (id == 0) {
        return static_cast<std::int32_t>(cancelOperations(0));
    }
    std::string description;
    switch (operations_->cancel(id, &description)) {
        case OperationRunner::CancelResult::Cancelled:
            return 1;
        case OperationRunner::CancelResult::NotFound:
            return 0;
        case OperationRunner::CancelResult::NotCancellable:
            break;
    }
    GitError error(GitError::Code::NotCancellable,
                   "\"" + description + "\" can't be cancelled once it has started",
                   "It changes the repository (it takes a git lock) as one step; "
                   "stopping it part-way could leave the repository half-updated, "
                   "so it was left to finish.");
    callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(error));
    return -1;
}

bool Session::submitOperation(std::unique_ptr<Operation> operation,
                              bool refreshHistoryOnSuccess,
                              std::function<void()> onSuccess,
                              std::function<void()> onAlways) {
    // The `Handle` submit() returns has been discarded at every one of these
    // call sites since the runner was written -- which is why every
    // `timeout = 0` command's "cancel is the control the user needs, not a
    // timeout" comment named a control nothing could actually reach. Keeping
    // it here is the whole of what gbm_cancel_operation() needs.
    //
    // `idSlot` exists because the id is only known *after* submit() returns,
    // while the callback that must erase it is built before. **The lock is
    // held across submit() deliberately**: the callback's own first act is to
    // take inFlightMutex_, so a fast operation cannot complete and try to
    // erase an entry this side has not inserted yet. That orders the two by
    // construction instead of leaving a window to reason about -- and the
    // window is not one a test could force, so reasoning is all there would
    // have been. submit() only pushes onto a queue and notifies; it never
    // waits on the worker, so holding a second mutex across it cannot
    // deadlock.
    auto idSlot = std::make_shared<std::uint64_t>(0);
    // Shared with the callback, so a hand-off that throws after the callback
    // has been moved away can still end what the caller began.
    const auto always = std::make_shared<const std::function<void()>>(std::move(onAlways));
    // Both are reported, and `onAlways` run, only once the lock is released:
    // endAskpass() joins the poller's thread.
    std::exception_ptr handOffFailure;
    std::exception_ptr bookkeepingFailure;
    {
        std::lock_guard<std::mutex> registration(inFlightMutex_);
        try {
            const auto handle = submitToRunner(
                *operations_,
                std::move(operation),
                [this, idSlot, refreshHistoryOnSuccess, onSuccess = std::move(onSuccess), always](
                    OperationOutcome outcome) {
                    {
                        std::lock_guard<std::mutex> lock(inFlightMutex_);
                        inFlight_.erase(*idSlot);
                    }
                    const bool succeeded = outcome.succeeded;
                    // "Failed" and "changed nothing" are not the same claim. `git
                    // branch -d a b` deletes what it can and still exits 1 for the
                    // rest, so a refused multi-branch delete routinely lands here
                    // having already moved refs/heads -- and refs read only on
                    // `succeeded` left the sidebar drawing branches that no longer
                    // existed. Only an operation that measured the change sets this
                    // (see OperationOutcome::mutatedRefs); the AND with
                    // refreshHistoryOnSuccess is kept, so no operation starts
                    // refreshing that was not already going to.
                    const bool changedRefs = succeeded || outcome.mutatedRefs;
                    refreshUndoJournalCache();
                    callbacks_.emit(GBM_EVENT_OPERATION_FINISHED, toJson(outcome));
                    refreshWorkingCopy();
                    if (*always) {
                        (*always)();
                    }
                    if (changedRefs && refreshHistoryOnSuccess) {
                        refreshHistory();
                        // Each worktree's branch and headOid are refs too: the
                        // worktree panel draws them, keys its pending counts on
                        // `path@headOid`, and the Add worktree dialog's "already
                        // checked out" gate reads the branch. A checkout, rename,
                        // reset, merge or rebase changes them; ~6 ms on vscode.
                        refreshWorktrees();
                    }
                    if (succeeded && onSuccess) {
                        onSuccess();
                    }
                },
                "Session::submitOperation");
            // Queued is queued from here on: a throw costs this operation its
            // cancel-by-id, never its outcome.
            try {
#if defined(GBM_CAPI_TEST_EXPORTS)
                throwIfArmedForTest(armedSubmitFailure(), "after:Session::submitOperation");
#endif
                *idSlot = handle.id;
                inFlight_.emplace(handle.id, handle.cancel);
            } catch (...) {
                bookkeepingFailure = std::current_exception();
            }
        } catch (...) {
            handOffFailure = std::current_exception();
        }
    }
    if (bookkeepingFailure) {
        reportException(bookkeepingFailure, "Session::submitOperation bookkeeping");
    }
    if (handOffFailure) {
        reportException(handOffFailure, "Session::submitOperation");
        runGuarded(*always, "Session::submitOperation onAlways");
        return false;
    }
    return true;
}

void Session::mergeBranch(MergeRequest request) {
    submitOperation(makeMergeOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::abortMerge() {
    submitOperation(makeMergeAbortOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::cherryPick(CherryPickRequest request) {
    submitOperation(makeCherryPickOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::continueCherryPick() {
    submitOperation(makeCherryPickContinueOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::continueCherryPickWithMessage(std::string message) {
    writeCherryPickContinueMessage(paths_, message);
    continueCherryPick();
}

void Session::skipCherryPick() {
    submitOperation(makeCherryPickSkipOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::abortCherryPick() {
    submitOperation(makeCherryPickAbortOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::revertCommit(RevertRequest request) {
    submitOperation(makeRevertOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::resolveConflict(ResolveConflictRequest request) {
    submitWorkingCopyOperation(makeResolveConflictOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::requestOriginalOperationMessage() {
    postRead(
        ReadLane::Front,
        "Session::requestOriginalOperationMessage",
        [this]() {
            callbacks_.emit(GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY,
                            messagePayload(readOriginalOperationMessage(paths_)));
        },
        // Its only shape: no message is what the caller already handles when
        // there is no operation in progress.
        [this](const GitError&) {
            callbacks_.emit(GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY, messagePayload(""));
        });
}

void Session::requestSquashMessage(std::string source) {
    // postFront: the Merge dialog is open and waiting on this
    // ([CPP-interactive-reads-go-to-the-front]).
    auto fail = [this](const std::string& squashSource, const GitError& error) {
        // Also the ordinary error event (使用者裁定 2026-10-09「抓不到
        // capi應該跳錯誤」), so the reason reaches the window's banner and
        // the Log like any other failure. First, so it is already
        // recorded when READY ends the dialog's wait.
        callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(error));
        callbacks_.emit(GBM_EVENT_SQUASH_MESSAGE_READY,
                        squashMessagePayload(squashSource, "", "", "", &error));
    };
    postRead(
        ReadLane::Front,
        "Session::requestSquashMessage",
        [this, source, fail]() {
            const GitResult<SquashMessagePreview> result =
                squashMessageStore_->preview(source, readCancel_.token());
            if (!result) {
                fail(source, result.error());
                return;
            }
            callbacks_.emit(GBM_EVENT_SQUASH_MESSAGE_READY,
                            squashMessagePayload(source,
                                                 result->headOid.hex(),
                                                 result->sourceOid.hex(),
                                                 result->message,
                                                 nullptr));
        },
        [source, fail](const GitError& error) { fail(source, error); });
}

void Session::requestPreparedMessage() {
    // postFront: the Working Copy box is waiting on this to fill itself
    // ([CPP-interactive-reads-go-to-the-front]).
    auto fail = [this](const GitError& error) {
        // First, like requestSquashMessage(): the reason reaches the
        // window's banner and the Log before READY ends the wait.
        callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(error));
        callbacks_.emit(GBM_EVENT_PREPARED_MESSAGE_READY, messagePayload("", &error));
    };
    postRead(
        ReadLane::Front,
        "Session::requestPreparedMessage",
        [this, fail]() {
            const GitResult<std::string> result = preparedMessageStore_->read(readCancel_.token());
            if (!result) {
                fail(result.error());
                return;
            }
            callbacks_.emit(GBM_EVENT_PREPARED_MESSAGE_READY, messagePayload(*result));
        },
        fail);
}

void Session::requestWorkingTreeContent(std::string path) {
    // postFront, like requestWorkingCopyDiff(): this is the conflict
    // window's own file read, and it must not sit behind a
    // refreshRepoStatus() sweep's other members either --
    // [CPP-interactive-reads-go-to-the-front].
    postRead(
        ReadLane::Front,
        "Session::requestWorkingTreeContent",
        [this, path]() {
            // Above this, a conflicted file is treated the same as binary: shown
            // as "not editable" rather than loaded whole into the resolve
            // editor -- mirrors RepositorySession::requestWorkingTreeContent's
            // own cap exactly.
            constexpr std::size_t kMaxEditableWorkingTreeBytes = 8u * 1024u * 1024u;
            const std::filesystem::path target = paths_.workDir() / fsutil::pathFromUtf8(path);
            const std::optional<std::string> raw =
                fsutil::readSmallFile(target, kMaxEditableWorkingTreeBytes);

            bool editable = false;
            std::string content;
            if (raw.has_value()) {
                const TextTraits traits = detectTextTraits(*raw);
                // A conflicted path that fails this is shown read-only instead
                // of risking silent corruption from a lossy UTF-8 decode --
                // detectTextTraits already folds an embedded NUL into
                // EncodingKind::Binary, matching RepositorySession's own check.
                editable = traits.encoding == EncodingKind::Utf8 ||
                           traits.encoding == EncodingKind::Utf8Bom;
                if (editable) {
                    content = *raw;
                }
            }

            callbacks_.emit(GBM_EVENT_WORKING_TREE_CONTENT_READY,
                            workingTreeContentPayload(path, content, editable));
        },
        // What an unreadable file already gets: shown, not editable.
        [this, path](const GitError&) {
            callbacks_.emit(GBM_EVENT_WORKING_TREE_CONTENT_READY,
                            workingTreeContentPayload(path, "", false));
        });
}

void Session::exportFileAtRevision(std::string revision, std::string path, std::string destPath) {
    postRead(
        ReadLane::Back,
        "Session::exportFileAtRevision",
        [this, revision, path, destPath]() {
            FileAtRevisionRequest request;
            request.revision = revision;
            request.path = path;
            request.destination = fsutil::pathFromUtf8(destPath);
            const GitResult<std::uint64_t> result =
                blobStore_->exportFileAtRevision(std::move(request), readCancel_.token());

            // Reported in the reply rather than as GBM_EVENT_ERROR_OCCURRED: the
            // caller is waiting on this specific export to decide whether to
            // open the file or tell the user it was saved, and a separate error
            // event carries nothing to match it against.
            callbacks_.emit(GBM_EVENT_FILE_AT_REVISION_EXPORTED,
                            fileAtRevisionPayload(
                                revision, path, destPath, result ? nullptr : &result.error()));
        },
        [this, revision, path, destPath](const GitError& error) {
            callbacks_.emit(GBM_EVENT_FILE_AT_REVISION_EXPORTED,
                            fileAtRevisionPayload(revision, path, destPath, &error));
        });
}

// --- Stashes -------------------------------------------------------------

void Session::refreshStashes() {
    postRead(
        ReadLane::Back,
        "Session::refreshStashes",
        [this]() {
            const GitResult<std::vector<StashEntry>> result =
                stashStore_->list(readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            {
                std::lock_guard<std::mutex> lock(auxMutex_);
                stashes_ = std::make_shared<const std::vector<StashEntry>>(result.value());
            }
            callbacks_.emitEmpty(GBM_EVENT_STASHES_UPDATED);
        },
        errorReply());
}

StashListPtr Session::currentStashes() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return stashes_;
}

void Session::saveStash(StashSaveRequest request) {
    submitWorkingCopyOperation(makeStashSaveOperation(std::move(request)), [this]() {
        refreshWorkingCopy();
        refreshStashes();
    });
}

void Session::applyStash(StashApplyRequest request) {
    // Even a conflicting apply/pop leaves the working tree changed -- refresh
    // it unconditionally, matching RepositorySession::applyStash. The stash
    // list is refreshed only on success: pop does not drop its entry on
    // conflict, exactly as plain `git stash pop` does not.
    submitWorkingCopyOperation(
        makeStashApplyOperation(std::move(request)),
        [this]() { refreshStashes(); },
        [this]() { refreshWorkingCopy(); });
}

void Session::dropStash(StashDropRequest request) {
    submitWorkingCopyOperation(makeStashDropOperation(std::move(request)),
                               [this]() { refreshStashes(); });
}

void Session::branchFromStash(StashBranchRequest request) {
    submitWorkingCopyOperation(makeStashBranchOperation(std::move(request)), [this]() {
        refreshWorkingCopy();
        refreshStashes();
        refreshHistory();
        refreshWorktrees();
    });
}

void Session::requestStashDiff(int index) {
    postRead(
        ReadLane::Back,
        "Session::requestStashDiff",
        [this, index]() {
            const GitResult<DiffService::ParsedDiffPtr> result = diffs_->stashDiff(
                index, /*includeUntracked=*/true, DiffOptions{}, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            std::string payload = "{\"index\":";
            jsonAppendInt(payload, index);
            payload += ",\"diff\":";
            payload += toJson(*result.value());
            payload += '}';
            callbacks_.emit(GBM_EVENT_STASH_DIFF_READY, payload);
        },
        errorReply());
}

// --- Tags ------------------------------------------------------------------

void Session::createTag(CreateTagRequest request) {
    submitWorkingCopyOperation(makeCreateTagOperation(std::move(request)),
                               [this]() { refreshHistory(); });
}

void Session::deleteTag(DeleteTagRequest request) {
    if (request.alsoRemote) {
        request.askpassDir = beginAskpass();
    }
    submitWorkingCopyOperation(
        makeDeleteTagOperation(std::move(request)),
        [this]() { refreshHistory(); },
        [this]() { endAskpass(); });
}

void Session::pushTag(PushTagRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(makePushTagOperation(std::move(request)),
                               /*onSuccess=*/nullptr,
                               [this]() { endAskpass(); });
}

// --- Worktrees ---------------------------------------------------------

void Session::refreshWorktrees() {
    postRead(
        ReadLane::Back,
        "Session::refreshWorktrees",
        [this]() {
            const GitResult<std::vector<WorktreeInfo>> result =
                worktreeStore_->list(readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            {
                std::lock_guard<std::mutex> lock(auxMutex_);
                worktrees_ = std::make_shared<const std::vector<WorktreeInfo>>(result.value());
            }
            callbacks_.emitEmpty(GBM_EVENT_WORKTREES_UPDATED);
        },
        errorReply());
}

void Session::requestWorktreePendingCounts() {
    postRead(
        ReadLane::Back,
        "Session::requestWorktreePendingCounts",
        [this]() {
            GitResult<std::vector<WorktreeInfo>> result = worktreeStore_->list(readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            // Re-listed rather than counted onto the published snapshot: that
            // snapshot may be several operations old, and attaching counts to a
            // path that has since been removed would publish a number for a row
            // that no longer exists.
            attachPendingCounts(*runner_, result.value(), readCancel_.token());
            {
                std::lock_guard<std::mutex> lock(auxMutex_);
                worktrees_ = std::make_shared<const std::vector<WorktreeInfo>>(result.value());
            }
            callbacks_.emitEmpty(GBM_EVENT_WORKTREES_UPDATED);
        },
        errorReply());
}

WorktreeListPtr Session::currentWorktrees() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return worktrees_;
}

// Add, remove and prune change which worktree each branch is checked out
// in, and RefInfo.worktreePath (`%(worktreepath)`) carries that per ref: the
// sidebar's bulk "gone" selection excludes any branch whose worktreePath is
// set. refreshHistory() is the refs read every other ref-changing operation
// uses; without it a removed worktree's branch stayed unselectable.
void Session::addWorktree(AddWorktreeRequest request) {
    submitWorkingCopyOperation(makeAddWorktreeOperation(std::move(request)), [this]() {
        refreshWorktrees();
        refreshHistory();
    });
}

void Session::removeWorktree(RemoveWorktreeRequest request) {
    submitWorkingCopyOperation(makeRemoveWorktreeOperation(std::move(request)), [this]() {
        refreshWorktrees();
        refreshHistory();
    });
}

void Session::pruneWorktrees() {
    submitWorkingCopyOperation(makePruneWorktreesOperation(PruneWorktreesRequest{}), [this]() {
        refreshWorktrees();
        refreshHistory();
    });
}

void Session::lockWorktree(LockWorktreeRequest request) {
    submitWorkingCopyOperation(makeLockWorktreeOperation(std::move(request)),
                               [this]() { refreshWorktrees(); });
}

void Session::unlockWorktree(UnlockWorktreeRequest request) {
    submitWorkingCopyOperation(makeUnlockWorktreeOperation(std::move(request)),
                               [this]() { refreshWorktrees(); });
}

// --- Remotes -----------------------------------------------------------

void Session::refreshRemotes() {
    postRead(
        ReadLane::Back,
        "Session::refreshRemotes",
        [this]() {
            const GitResult<std::vector<RemoteInfo>> result =
                remoteStore_->list(readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            {
                std::lock_guard<std::mutex> lock(auxMutex_);
                remotes_ = std::make_shared<const std::vector<RemoteInfo>>(result.value());
            }
            callbacks_.emitEmpty(GBM_EVENT_REMOTES_UPDATED);
        },
        errorReply());
}

RemoteListPtr Session::currentRemotes() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return remotes_;
}

bool Session::fetchRemote(FetchRequest request) {
    if (request.background) {
        // No askpass watch at all: there is one poller per session, so a
        // background fetch that took it -- and released it on finishing --
        // would delete the request directory of a push submitted while it
        // ran, and that push's password prompt would never appear.
        // FetchOperation refuses every prompt for a background fetch anyway.
        request.refsBefore = currentRefs();
        return submitWorkingCopyOperationReading(makeFetchOperation(std::move(request)),
                                                 [this](const OperationOutcome& outcome) {
                                                     // A quiet remote costs no walk.
                                                     if (outcome.refsMoved.value_or(true)) {
                                                         refreshHistory();
                                                     }
                                                 });
    }
    request.askpassDir = beginAskpass();
    return submitWorkingCopyOperation(
        makeFetchOperation(std::move(request)),
        [this]() { refreshHistory(); },
        [this]() { endAskpass(); });
}

void Session::pullChanges(PullRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makePullOperation(std::move(request)),
        [this]() {
            refreshHistory();
            refreshWorktrees();
        },
        [this]() {
            endAskpass();
            refreshWorkingCopy();
        });
}

void Session::pushChanges(PushRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makePushOperation(std::move(request)),
        [this]() { refreshHistory(); },
        [this]() { endAskpass(); });
}

void Session::requestRemotePrunePreview(std::string remoteName) {
    postRead(
        ReadLane::Front,
        "Session::requestRemotePrunePreview",
        // Copied, not moved: the failure reply below needs the name too, and
        // the order these two arguments are built in is unspecified.
        [this, remoteName]() {
            const GitResult<std::vector<RemotePrunePreviewEntry>> result =
                remoteStore_->prunePreview(remoteName, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            std::string payload = "{\"remote\":";
            jsonAppendEscaped(payload, remoteName);
            payload += ",\"refs\":";
            payload += toJson(result.value());
            payload += '}';
            callbacks_.emit(GBM_EVENT_REMOTE_PRUNE_PREVIEW_READY, payload);
        },
        [this, remoteName](const GitError& thrown) {
            // Dart tells a fetch-triggered preview's failure from the Prune
            // dialog's by this argv alone (_isSuppressedAutoPrunePreviewError),
            // so a failure that never ran git still names the command it stood
            // for -- RemoteOps.cpp's prunePreview arguments.
            GitError error = thrown;
            error.argv = {"git", "remote", "prune", remoteName, "--dry-run"};
            callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(error));
        });
}

void Session::requestBranchDeletionProbe(std::uint64_t requestId, std::vector<std::string> names) {
    // postFront: a delete dialog's button waits on this reply
    // ([CPP-interactive-reads-go-to-the-front]).
    postRead(
        ReadLane::Front,
        "Session::requestBranchDeletionProbe",
        [this, requestId, names = std::move(names)]() mutable {
            BranchStore store(*runner_, paths_);
            const GitResult<std::vector<BranchDeletionProbe>> result =
                store.probeDeletion(std::move(names), readCancel_.token());
            callbacks_.emit(GBM_EVENT_BRANCH_DELETION_PROBE_READY,
                            result ? branchDeletionProbePayload(requestId, result.value(), nullptr)
                                   : branchDeletionProbePayload(requestId, {}, &result.error()));
        },
        [this, requestId](const GitError& error) {
            callbacks_.emit(GBM_EVENT_BRANCH_DELETION_PROBE_READY,
                            branchDeletionProbePayload(requestId, {}, &error));
        });
}

bool Session::pruneRemote(PruneRemoteRequest request) {
    // Not submitWorkingCopyOperation: pruning remote-tracking refs never
    // touches the working tree or index, only refs -- same shape as
    // deleteBranch(), which is why this reports through the plain
    // GBM_EVENT_OPERATION_FINISHED channel below (submitOperation), not
    // GBM_EVENT_WORKING_COPY_OPERATION_FINISHED.
    return submitOperation(makePruneRemoteOperation(std::move(request)),
                           /*refreshHistoryOnSuccess=*/true);
}

void Session::addRemote(AddRemoteRequest request) {
    // Not submitWorkingCopyOperation, same reasoning as pruneRemote():
    // this only touches repo config, never the working tree or index.
    submitOperation(makeAddRemoteOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/false,
                    [this]() { refreshRemotes(); });
}

void Session::removeRemote(RemoveRemoteRequest request) {
    submitOperation(makeRemoveRemoteOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/false,
                    [this]() { refreshRemotes(); });
}

void Session::provideCredential(std::string secret) {
    askpass_.answer(secret);
}

void Session::cancelCredential() {
    askpass_.cancelPrompt();
}

std::filesystem::path Session::beginAskpass() {
    std::filesystem::path dir = askpass::makeRequestDir();
    if (dir.empty()) {
        return dir;
    }
    askpass_.start(dir, [this](std::string prompt) {
        std::string payload = "{\"prompt\":";
        jsonAppendEscaped(payload, prompt);
        payload += '}';
        callbacks_.emit(GBM_EVENT_CREDENTIAL_REQUESTED, payload);
    });
    return dir;
}

void Session::endAskpass() {
    askpass_.stop();
}

void Session::publishOperationLogRecord(const OperationRecord& record) {
    callbacks_.emit(GBM_EVENT_OPERATION_LOG_RECORD, toJson(record));
}

void Session::dispatchOperationLogRecord(const OperationRecord& record) {
    // A clone job's records are its own, even when a session is open on a
    // directory the clone happens to match.
    if (CloneJob::dispatchLogRecord(record)) {
        return;
    }
    std::lock_guard<std::mutex> lock(liveSessionsMutex());
    for (Session* session : liveSessions()) {
        // Its own directory, plus every linked worktree it last listed:
        // attachPendingCounts runs `git status` in each of those, and an
        // exact string match against the work tree alone used to drop them.
        // auxMutex_ is never held across a git invocation, so taking it under
        // liveSessionsMutex() cannot invert a lock order.
        std::vector<std::filesystem::path> dirs{session->paths_.commandDir()};
        if (const WorktreeListPtr worktrees = session->currentWorktrees()) {
            for (const WorktreeInfo& worktree : *worktrees) {
                dirs.push_back(worktree.path);
            }
        }
        if (!recordBelongsToSession(record.repoDir, dirs)) {
            continue;
        }
        // Serialised per receiving session: only the session whose queue runs
        // the operation may name it for a Cancel. Taking the runner's mutex
        // here cannot invert a lock order -- the runner never holds it while
        // anything logs.
        if (record.queuedOperationId != 0 &&
            !session->operations_->runs(record.queuedOperationId)) {
            OperationRecord foreign = record;
            foreign.queuedOperationId = 0;
            session->publishOperationLogRecord(foreign);
        } else {
            session->publishOperationLogRecord(record);
        }
    }
}

// --- Blame / file history / line history / reflog / undo -----------------

void Session::requestBlame(std::string path, std::string revision, int startLine, int endLine) {
    // postFront, not post: a newer blame/file-history/line-history request
    // supersedes an older, still-queued one in interactive priority --
    // matches RepositorySession::requestBlame()'s use of readPool_.postFront.
    postRead(
        ReadLane::Front,
        "Session::requestBlame",
        [this, path = std::move(path), revision = std::move(revision), startLine, endLine]() {
            const GitResult<BlameResultPtr> result =
                blameStore_->blame(path, revision, startLine, endLine, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            callbacks_.emit(GBM_EVENT_BLAME_READY, toJson(*result.value()));
        },
        errorReply());
}

void Session::requestCommitMeta(std::vector<std::string> oids) {
    // postFront, like requestBlame(): a newer viewport (fast scroll) should
    // not wait behind a stale one still being answered.
    postRead(
        ReadLane::Front,
        "Session::requestCommitMeta",
        [this, oids = std::move(oids)]() {
            std::vector<ObjectId> parsed;
            parsed.reserve(oids.size());
            for (const std::string& oid : oids) {
                parsed.push_back(ObjectId::fromHex(oid));
            }
            const std::vector<CommitMeta> result =
                commitMetaStore_->read(parsed, readCancel_.token());
            callbacks_.emit(GBM_EVENT_COMMIT_META_READY, toJson(result));
        },
        // gbm_capi.h promises this always replies and never raises the error
        // event: an unanswered oid is simply missing from the batch.
        [this](const GitError&) { callbacks_.emit(GBM_EVENT_COMMIT_META_READY, "[]"); });
}

void Session::requestCommitFileCounts(std::vector<std::string> oids) {
    // postFront, like requestCommitMeta(): both answer the same viewport, and
    // a fast scroll should not leave the newest request behind a stale one.
    postRead(
        ReadLane::Front,
        "Session::requestCommitFileCounts",
        [this, oids = std::move(oids)]() {
            std::vector<ObjectId> parsed;
            parsed.reserve(oids.size());
            for (const std::string& oid : oids) {
                parsed.push_back(ObjectId::fromHex(oid));
            }
            const GitResult<std::vector<CommitFileCount>> result =
                diffs_->commitFileCounts(parsed, DiffOptions{}, readCancel_.token());
            if (!result) {
                // Deliberately not an error event. This backs a column that is off
                // by default and shows a number; failing the whole session's error
                // channel because one viewport could not be counted would be
                // louder than the feature is important. The caller sees the
                // absence instead, which is the same thing it must already handle
                // for an individual unanswerable oid.
                callbacks_.emit(GBM_EVENT_COMMIT_FILE_COUNTS_READY, "[]");
                return;
            }
            std::string payload = "[";
            bool first = true;
            for (const CommitFileCount& entry : *result) {
                if (!first) {
                    payload += ',';
                }
                first = false;
                payload += "{\"oid\":";
                jsonAppendEscaped(payload, entry.commit.hex());
                payload += ",\"fileCount\":";
                payload += std::to_string(entry.fileCount);
                payload += '}';
            }
            payload += ']';
            callbacks_.emit(GBM_EVENT_COMMIT_FILE_COUNTS_READY, payload);
        },
        // The same deliberate no-error shape as a failed count above.
        [this](const GitError&) { callbacks_.emit(GBM_EVENT_COMMIT_FILE_COUNTS_READY, "[]"); });
}

void Session::requestCommitFiles(std::string oid) {
    postRead(
        ReadLane::Front,
        "Session::requestCommitFiles",
        [this, oid = std::move(oid)]() {
            const ObjectId commitOid = ObjectId::fromHex(oid);
            const GitResult<DiffService::ChangedFilesPtr> result =
                diffs_->changedFiles(commitOid, DiffOptions{}, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            std::string payload = "{\"oid\":";
            jsonAppendEscaped(payload, oid);
            payload += ",\"files\":";
            payload += toJson(*result.value());
            payload += '}';
            callbacks_.emit(GBM_EVENT_COMMIT_FILES_READY, payload);
        },
        errorReply());
}

void Session::requestCommitFileDiff(std::string oid, std::string path, std::string oldPath) {
    postRead(
        ReadLane::Front,
        "Session::requestCommitFileDiff",
        [this, oid = std::move(oid), path = std::move(path), oldPath = std::move(oldPath)]() {
            const ObjectId commitOid = ObjectId::fromHex(oid);
            const GitResult<DiffService::ParsedDiffPtr> result = diffs_->commitFileDiff(
                commitOid, path, oldPath, DiffOptions{}, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            // Same as emitWorkingCopyDiff: two pathspecs can answer with two
            // files (the commit also added a new file at the old name), and the
            // reply describes only the one it names.
            ParsedDiff onlyRequested = *result.value();
            if (!oldPath.empty() && oldPath != path) {
                std::erase_if(onlyRequested.files,
                              [&path](const DiffFile& file) { return file.newPath != path; });
            }
            std::string payload = "{\"oid\":";
            jsonAppendEscaped(payload, oid);
            payload += ",\"path\":";
            jsonAppendEscaped(payload, path);
            payload += ",\"diff\":";
            payload += toJson(onlyRequested);
            payload += '}';
            callbacks_.emit(GBM_EVENT_COMMIT_FILE_DIFF_READY, payload);
        },
        errorReply());
}

void Session::requestCompareRefs(std::string leftRef, std::string rightRef, bool threeDot) {
    postRead(
        ReadLane::Front,
        "Session::requestCompareRefs",
        [this, leftRef = std::move(leftRef), rightRef = std::move(rightRef), threeDot]() {
            CompareRequest request;
            request.leftRef = leftRef;
            request.rightRef = rightRef;
            request.threeDot = threeDot;
            const GitResult<CompareResult> result =
                compareStore_->compare(std::move(request), readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            std::string payload = "{\"left\":";
            jsonAppendEscaped(payload, leftRef);
            payload += ",\"right\":";
            jsonAppendEscaped(payload, rightRef);
            payload += ",\"threeDot\":";
            jsonAppendBool(payload, threeDot);
            payload += ",\"mergeBase\":";
            jsonAppendEscaped(payload, result->mergeBase.hex());
            payload += ",\"commits\":";
            payload += toJson(result->commits);
            payload += ",\"files\":";
            payload += toJson(result->files);
            payload += '}';
            callbacks_.emit(GBM_EVENT_COMPARE_READY, payload);
        },
        errorReply());
}

void Session::requestCompareFileDiff(std::string leftRef,
                                     std::string rightRef,
                                     bool threeDot,
                                     std::string path,
                                     std::string oldPath) {
    postRead(
        ReadLane::Front,
        "Session::requestCompareFileDiff",
        [this,
         leftRef = std::move(leftRef),
         rightRef = std::move(rightRef),
         threeDot,
         path = std::move(path),
         oldPath = std::move(oldPath)]() {
            CompareFileDiffRequest request;
            request.leftRef = leftRef;
            request.rightRef = rightRef;
            request.threeDot = threeDot;
            request.path = path;
            request.oldPath = oldPath;
            GitResult<ParsedDiff> result =
                compareStore_->compareFileDiff(std::move(request), readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            // Same as emitWorkingCopyDiff: two pathspecs can answer with two
            // files, and the reply describes only the one it names.
            if (!oldPath.empty() && oldPath != path) {
                std::erase_if(result->files,
                              [&path](const DiffFile& file) { return file.newPath != path; });
            }
            std::string payload = "{\"left\":";
            jsonAppendEscaped(payload, leftRef);
            payload += ",\"right\":";
            jsonAppendEscaped(payload, rightRef);
            payload += ",\"threeDot\":";
            jsonAppendBool(payload, threeDot);
            payload += ",\"path\":";
            jsonAppendEscaped(payload, path);
            payload += ",\"diff\":";
            payload += toJson(result.value());
            payload += '}';
            callbacks_.emit(GBM_EVENT_COMPARE_FILE_DIFF_READY, payload);
        },
        errorReply());
}

void Session::requestCompareWithWorkingCopy(std::string ref) {
    postRead(
        ReadLane::Front,
        "Session::requestCompareWithWorkingCopy",
        [this, ref = std::move(ref)]() {
            const GitResult<ObjectId> resolved =
                refStore_->resolveRevision(ref, readCancel_.token());
            if (!resolved) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(resolved.error()));
                return;
            }
            const GitResult<DiffService::ParsedDiffPtr> result =
                diffs_->commitVsWorkingTree(*resolved, DiffOptions{}, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            std::string payload = "{\"ref\":";
            jsonAppendEscaped(payload, ref);
            payload += ",\"diff\":";
            payload += toJson(*result.value());
            payload += '}';
            callbacks_.emit(GBM_EVENT_COMPARE_WITH_WORKING_COPY_READY, payload);
        },
        errorReply());
}

void Session::requestFileHistory(std::string path, std::string startRevision) {
    postRead(
        ReadLane::Front,
        "Session::requestFileHistory",
        [this, path = std::move(path), startRevision = std::move(startRevision)]() {
            const GitResult<std::vector<FileHistoryEntry>> result =
                fileHistoryStore_->fileHistory(path, startRevision, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            callbacks_.emit(GBM_EVENT_FILE_HISTORY_READY, toJson(result.value()));
        },
        errorReply());
}

void Session::requestLineHistory(std::string path,
                                 int startLine,
                                 int endLine,
                                 std::string startRevision) {
    postRead(
        ReadLane::Front,
        "Session::requestLineHistory",
        [this,
         path = std::move(path),
         startLine,
         endLine,
         startRevision = std::move(startRevision)]() {
            const GitResult<std::vector<LineHistoryChunk>> result = fileHistoryStore_->lineHistory(
                path, startLine, endLine, startRevision, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            callbacks_.emit(GBM_EVENT_LINE_HISTORY_READY, toJson(result.value()));
        },
        errorReply());
}

void Session::requestReflog(std::string ref) {
    // post, not postFront: matches RepositorySession::requestReflog(), the
    // one read-store request among these four that is not treated as
    // preempting other queued reads (see the M6 capi research notes on why
    // the Qt original draws that line here).
    postRead(
        ReadLane::Back,
        "Session::requestReflog",
        [this, ref = std::move(ref)]() {
            const GitResult<std::vector<ReflogEntry>> result =
                reflogStore_->list(ref, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            callbacks_.emit(GBM_EVENT_REFLOG_READY, toJson(result.value()));
        },
        errorReply());
}

void Session::refreshUndoJournalCache() {
    std::lock_guard<std::mutex> lock(undoMutex_);
    undoJournalCache_ = operations_->undoJournal();
}

std::vector<OperationRunner::UndoEntry> Session::undoJournal() const {
    std::lock_guard<std::mutex> lock(undoMutex_);
    return undoJournalCache_;
}

void Session::undoLastOperation() {
    std::vector<OperationRunner::UndoEntry> journal;
    {
        std::lock_guard<std::mutex> lock(undoMutex_);
        journal = undoJournalCache_;
    }
    if (journal.empty()) {
        return;
    }
    const OperationRunner::UndoEntry& last = journal.back();
    UndoRequest request;
    request.headBefore = last.headBefore;
    request.branchBefore = last.branchBefore;
    submitWorkingCopyOperation(makeUndoOperation(std::move(request)), [this]() {
        refreshWorkingCopy();
        refreshHistory();
        refreshWorktrees();
    });
}

// --- Restore / clean -------------------------------------------------------

void Session::restorePaths(RestoreRequest request) {
    submitWorkingCopyOperation(makeRestoreOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::requestCleanPreview(bool includeIgnored) {
    postRead(
        ReadLane::Back,
        "Session::requestCleanPreview",
        [this, includeIgnored]() {
            CleanPreviewer previewer(*runner_, paths_);
            const GitResult<std::vector<CleanEntry>> result =
                previewer.preview(includeIgnored, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            callbacks_.emit(GBM_EVENT_CLEAN_PREVIEW_READY, toJson(result.value()));
        },
        errorReply());
}

void Session::cleanUntracked(CleanRequest request) {
    submitWorkingCopyOperation(makeCleanOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

// --- Rebase ------------------------------------------------------------

void Session::requestRebasePlan(std::string upstream) {
    postRead(
        ReadLane::Back,
        "Session::requestRebasePlan",
        [this, upstream = std::move(upstream)]() {
            RebasePlanner planner(*runner_, paths_);
            const GitResult<std::vector<RebaseTodoEntry>> result =
                planner.plan(upstream, readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            callbacks_.emit(GBM_EVENT_REBASE_PLAN_READY, toJson(result.value()));
        },
        errorReply());
}

void Session::startInteractiveRebase(RebaseInteractiveRequest request) {
    submitOperation(makeRebaseInteractiveOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true);
}

void Session::startRebase(RebaseRequest request) {
    submitOperation(makeRebaseOperation(std::move(request)), /*refreshHistoryOnSuccess=*/true);
}

void Session::continueRebase() {
    submitOperation(makeRebaseContinueOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::continueRebaseWithMessage(std::string message) {
    writeRebaseContinueMessage(paths_, message);
    continueRebase();
}

void Session::skipRebase() {
    submitOperation(makeRebaseSkipOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::abortRebase() {
    submitOperation(makeRebaseAbortOperation(), /*refreshHistoryOnSuccess=*/true);
}

// --- Submodules ------------------------------------------------------------

void Session::refreshSubmodules() {
    postRead(
        ReadLane::Back,
        "Session::refreshSubmodules",
        [this]() {
            const GitResult<std::vector<SubmoduleInfo>> result =
                submoduleStore_->list(readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            {
                std::lock_guard<std::mutex> lock(auxMutex_);
                submodules_ = std::make_shared<const std::vector<SubmoduleInfo>>(result.value());
            }
            callbacks_.emitEmpty(GBM_EVENT_SUBMODULES_UPDATED);
        },
        errorReply());
}

SubmoduleListPtr Session::currentSubmodules() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return submodules_;
}

void Session::addSubmodule(AddSubmoduleRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makeAddSubmoduleOperation(std::move(request)),
        [this]() {
            refreshWorkingCopy();
            refreshSubmodules();
        },
        [this]() { endAskpass(); });
}

void Session::initSubmodules(SubmodulePathsRequest request) {
    submitWorkingCopyOperation(makeInitSubmodulesOperation(std::move(request)),
                               [this]() { refreshSubmodules(); });
}

void Session::updateSubmodules(UpdateSubmodulesRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makeUpdateSubmodulesOperation(std::move(request)),
        [this]() {
            refreshWorkingCopy();
            refreshSubmodules();
        },
        [this]() { endAskpass(); });
}

void Session::syncSubmodules(SubmodulePathsRequest request) {
    submitWorkingCopyOperation(makeSyncSubmodulesOperation(std::move(request)),
                               [this]() { refreshSubmodules(); });
}

void Session::deinitSubmodules(DeinitSubmodulesRequest request) {
    submitWorkingCopyOperation(makeDeinitSubmodulesOperation(std::move(request)),
                               [this]() { refreshSubmodules(); });
}

// --- Bisect ------------------------------------------------------------

void Session::refreshBisectStatus() {
    postRead(
        ReadLane::Back,
        "Session::refreshBisectStatus",
        [this]() {
            const GitResult<BisectStatus> result = bisectStore_->status(readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            {
                std::lock_guard<std::mutex> lock(auxMutex_);
                bisectStatus_ = std::make_shared<const BisectStatus>(result.value());
            }
            callbacks_.emitEmpty(GBM_EVENT_BISECT_STATUS_UPDATED);
        },
        errorReply());
}

BisectStatusPtr Session::currentBisectStatus() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return bisectStatus_;
}

void Session::startBisect(BisectStartRequest request) {
    submitOperation(makeBisectStartOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true,
                    [this]() { refreshBisectStatus(); });
}

void Session::markBisect(BisectMarkRequest request) {
    submitOperation(makeBisectMarkOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true,
                    [this]() { refreshBisectStatus(); });
}

void Session::skipBisect(BisectSkipRequest request) {
    submitOperation(makeBisectSkipOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true,
                    [this]() { refreshBisectStatus(); });
}

void Session::resetBisect(BisectResetRequest request) {
    submitOperation(makeBisectResetOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true,
                    [this]() { refreshBisectStatus(); });
}

// --- LFS ---------------------------------------------------------------

void Session::refreshLfs() {
    const bool needsInstallationProbe = [this]() {
        std::lock_guard<std::mutex> lock(auxMutex_);
        return !lfsInstallation_.has_value();
    }();
    postRead(
        ReadLane::Back,
        "Session::refreshLfs",
        [this, needsInstallationProbe]() {
            bool available;
            if (needsInstallationProbe) {
                // detectLfs() never fails (a missing `git-lfs` is a normal
                // result, not an error -- see its doc comment), so there is no
                // error branch to handle here.
                const LfsInstallation installation =
                    detectLfs(*runner_, paths_, readCancel_.token()).value();
                std::lock_guard<std::mutex> lock(auxMutex_);
                lfsInstallation_ = installation;
                available = installation.available;
            } else {
                std::lock_guard<std::mutex> lock(auxMutex_);
                available = lfsInstallation_->available;
            }

            if (!available) {
                // Matches RepositorySession::refreshLfs(): with no `git-lfs` on
                // PATH, `git lfs track`/`git lfs ls-files` would themselves fail
                // (git does not recognise the subcommand), so skip them rather
                // than surfacing that as an error -- there is nothing to list.
                callbacks_.emitEmpty(GBM_EVENT_LFS_UPDATED);
                return;
            }

            // Matches RepositorySession::refreshLfs(): an individual read
            // failing here is not fatal to the refresh as a whole -- whichever
            // of patterns/files succeeded is still published.
            const GitResult<std::vector<std::string>> patterns =
                lfsStore_->trackedPatterns(readCancel_.token());
            const GitResult<std::vector<LfsFileInfo>> files =
                lfsStore_->listFiles(readCancel_.token());
            {
                std::lock_guard<std::mutex> lock(auxMutex_);
                if (patterns) {
                    lfsPatterns_ =
                        std::make_shared<const std::vector<std::string>>(patterns.value());
                }
                if (files) {
                    lfsFiles_ = std::make_shared<const std::vector<LfsFileInfo>>(files.value());
                }
            }
            callbacks_.emitEmpty(GBM_EVENT_LFS_UPDATED);
        },
        // A failed read is not an error here either: answer with whatever was last published.
        [this](const GitError&) { callbacks_.emitEmpty(GBM_EVENT_LFS_UPDATED); });
}

std::optional<LfsInstallation> Session::currentLfsInstallation() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return lfsInstallation_;
}

LfsPatternListPtr Session::currentLfsPatterns() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return lfsPatterns_;
}

LfsFileListPtr Session::currentLfsFiles() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return lfsFiles_;
}

void Session::installLfs() {
    submitWorkingCopyOperation(makeLfsInstallOperation(), [this]() { refreshLfs(); });
}

void Session::trackLfsPattern(LfsTrackRequest request) {
    submitWorkingCopyOperation(makeLfsTrackOperation(std::move(request)),
                               [this]() { refreshLfs(); });
}

void Session::untrackLfsPattern(LfsUntrackRequest request) {
    submitWorkingCopyOperation(makeLfsUntrackOperation(std::move(request)),
                               [this]() { refreshLfs(); });
}

void Session::pullLfs(LfsTransferRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makeLfsPullOperation(std::move(request)),
        [this]() {
            refreshWorkingCopy();
            refreshLfs();
        },
        [this]() { endAskpass(); });
}

void Session::fetchLfs(LfsTransferRequest request) {
    request.askpassDir = beginAskpass();
    submitWorkingCopyOperation(
        makeLfsFetchOperation(std::move(request)),
        [this]() { refreshLfs(); },
        [this]() { endAskpass(); });
}

void Session::pruneLfs(LfsPruneRequest request) {
    submitWorkingCopyOperation(makeLfsPruneOperation(std::move(request)),
                               [this]() { refreshLfs(); });
}

// --- Patch import/export -------------------------------------------------

void Session::exportPatches(ExportPatchesRequest request) {
    submitWorkingCopyOperation(makeExportPatchesOperation(std::move(request)),
                               /*onSuccess=*/nullptr);
}

void Session::applyPatchFiles(ApplyPatchFilesRequest request) {
    submitWorkingCopyOperation(makeApplyPatchFilesOperation(std::move(request)),
                               [this]() { refreshWorkingCopy(); });
}

void Session::importPatches(ImportPatchesRequest request) {
    submitOperation(makeImportPatchesOperation(std::move(request)),
                    /*refreshHistoryOnSuccess=*/true);
}

void Session::continueImport() {
    submitOperation(makeAmContinueOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::skipImport() {
    submitOperation(makeAmSkipOperation(), /*refreshHistoryOnSuccess=*/true);
}

void Session::abortImport() {
    submitOperation(makeAmAbortOperation(), /*refreshHistoryOnSuccess=*/true);
}

// --- Local Git identity / commit-graph maintenance ------------------------

void Session::refreshLocalIdentity() {
    postRead(
        ReadLane::Back,
        "Session::refreshLocalIdentity",
        [this]() {
            const GitResult<LocalIdentity> result = localIdentityStore_->read(readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            {
                std::lock_guard<std::mutex> lock(auxMutex_);
                localIdentity_ = std::make_shared<const LocalIdentity>(result.value());
            }
            callbacks_.emitEmpty(GBM_EVENT_LOCAL_IDENTITY_UPDATED);
        },
        errorReply());
}

LocalIdentityPtr Session::currentLocalIdentity() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return localIdentity_;
}

void Session::refreshEffectiveIdentity() {
    postRead(
        ReadLane::Back,
        "Session::refreshEffectiveIdentity",
        [this]() {
            const GitResult<EffectiveIdentity> result =
                localIdentityStore_->readEffective(readCancel_.token());
            if (!result) {
                callbacks_.emit(GBM_EVENT_ERROR_OCCURRED, toJson(result.error()));
                return;
            }
            {
                std::lock_guard<std::mutex> lock(auxMutex_);
                effectiveIdentity_ = std::make_shared<const EffectiveIdentity>(result.value());
            }
            callbacks_.emitEmpty(GBM_EVENT_EFFECTIVE_IDENTITY_UPDATED);
        },
        errorReply());
}

EffectiveIdentityPtr Session::currentEffectiveIdentity() const {
    std::lock_guard<std::mutex> lock(auxMutex_);
    return effectiveIdentity_;
}

void Session::setLocalIdentityOverride(SetLocalIdentityRequest request) {
    submitWorkingCopyOperation(makeSetLocalIdentityOperation(std::move(request)), [this]() {
        refreshLocalIdentity();
        refreshEffectiveIdentity();
    });
}

void Session::clearLocalIdentityOverride() {
    submitWorkingCopyOperation(makeClearLocalIdentityOperation(), [this]() {
        refreshLocalIdentity();
        refreshEffectiveIdentity();
    });
}

bool Session::hasCommitGraph() const {
    return gbm::hasCommitGraph(paths_);
}

void Session::writeCommitGraph() {
    WriteCommitGraphRequest request;
    request.split = installation_.capabilities.commitGraphSplit;
    request.changedPaths = installation_.capabilities.changedPathBloom;
    operations_->submit(makeWriteCommitGraphOperation(request), [this](OperationOutcome outcome) {
        // Keeps undoJournalCache_ in sync with operations_->undoJournal(),
        // exactly like submitOperation()/submitWorkingCopyOperation() do --
        // this bypasses both helpers (it needs its own event, see
        // GBM_EVENT_COMMIT_GRAPH_WRITE_FINISHED's doc comment), but still
        // goes through operations_->submit(), so OperationRunner::
        // recordUndoPoint() still ran and appended an entry.
        refreshUndoJournalCache();
        std::string payload = "{\"succeeded\":";
        jsonAppendBool(payload, outcome.succeeded);
        payload += '}';
        callbacks_.emit(GBM_EVENT_COMMIT_GRAPH_WRITE_FINISHED, payload);
    });
}

}  // namespace gbm::capi
