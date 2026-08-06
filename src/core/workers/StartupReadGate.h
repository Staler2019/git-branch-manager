#pragma once

namespace gbm {

/// Holds back at most one speculative background read until a release signal
/// fires, then lets every later request through immediately.
///
/// Built for RepositorySession::refreshWorkingCopyStatusWhenIdle(): on repo
/// open, the cold `git status` scan can cost tens of seconds on a large,
/// freshly-cloned tree (see docs/reports/vscode-graph-performance.md,
/// bottleneck #2), and the read pool is only guaranteed 2 threads
/// (ThreadPool::defaultThreadCount()). Without this gate, that scan can queue
/// ahead of the history walk and delay the very first thing the user opened
/// the repository to see. The gate lets the walk start unconditionally while
/// coalescing every speculative status request that arrives before the
/// walk's first result into exactly one, run once release() is called.
///
/// Deliberately not thread-safe: every call site (RepositorySession's request
/// path and its release on the walk's terminal paths) runs on the UI thread,
/// hopped there via `QMetaObject::invokeMethod(..., Qt::QueuedConnection)`.
class StartupReadGate {
public:
    /// Closed: the first call records the request and returns false (caller
    /// must not run yet, and will be run by release() instead). Open: every
    /// call returns true immediately, forever after.
    bool requestOrHold() {
        if (open_) {
            return true;
        }
        pending_ = true;
        return false;
    }

    /// Opens the gate. Returns true when a held request must now run --
    /// false when there was nothing pending (still opens either way, so a
    /// walk that never published anything, e.g. an empty repository or an
    /// error, doesn't leave the gate permanently closed). Idempotent: a
    /// second call always returns false.
    bool release() {
        open_ = true;
        if (pending_) {
            pending_ = false;
            return true;
        }
        return false;
    }

    bool isOpen() const noexcept { return open_; }

private:
    bool open_ = false;
    bool pending_ = false;
};

}  // namespace gbm
