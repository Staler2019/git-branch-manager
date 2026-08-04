#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/CommitMeta.h"
#include "core/git/RepoPaths.h"

#include <filesystem>
#include <memory>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace gbm {

/// A long-lived `git cat-file --batch` process, one per open repository.
///
/// This is the single most important consequence of the CLI-only backend. A
/// process spawn costs 20-40 ms on Windows (worse with an antivirus filter
/// driver), so fetching commit metadata by spawning a process per object would
/// make scrolling impossible. Instead one process stays alive for as long as the
/// repository is open and answers requests over its stdin/stdout.
///
/// The batch protocol is length-prefixed, so it is binary-safe and needs no
/// escaping: for each request we get `<oid> SP <type> SP <size> LF`, then exactly
/// `size` bytes of payload, then a single LF.
class CatFileBatch {
public:
    CatFileBatch(std::filesystem::path gitExecutable, RepoPaths paths);
    ~CatFileBatch();

    CatFileBatch(const CatFileBatch&) = delete;
    CatFileBatch& operator=(const CatFileBatch&) = delete;

    /// Spawns the child. Safe to call more than once; a running child is kept.
    GitResult<void> start();

    void stop();

    bool isRunning() const;

    struct Object {
        ObjectId oid;
        std::string type;
        std::string content;
    };

    /// Reads one object by any revision expression git accepts (`<oid>`,
    /// `HEAD:path`, `<oid>^{tree}`). Returns NotFound for a missing object
    /// without tearing down the co-process.
    ///
    /// `token` is checked once at entry, before any I/O, so a request that is
    /// still queued behind a cancellation (repository switch, closing the
    /// session) never starts. It is *not* checked mid-flight: the read/write
    /// calls to the child's pipe are plain blocking calls with no deadline, so
    /// a request already in progress runs to completion (or to the child's own
    /// I/O error) before this returns. That is a real, currently-unbounded
    /// wait if the child process itself hangs. It is accepted rather than
    /// fixed here because the child is a `git cat-file --batch` process this
    /// app spawns and owns, expected to answer promptly -- a hang there is a
    /// distinct failure mode from the freed-object crash this cancellation
    /// exists to prevent (see `ThreadPool::cancelQueuedAndDrain`).
    GitResult<Object> read(std::string_view revision, CancellationToken token = {});

    /// Reads and parses a commit. The common case, called in viewport batches.
    GitResult<CommitMeta> readCommit(const ObjectId& oid, CancellationToken token = {});

    /// Batch form. A failure on one object does not abort the rest; missing
    /// entries are simply absent from the result, so a partially-corrupt
    /// repository still browses.
    ///
    /// `token` is checked before each object, not just once before the whole
    /// batch: a viewport request can ask for hundreds of oids, and this is
    /// what lets a cancellation (repository switch, closing the session) stop
    /// the loop from *starting* further requests immediately, rather than
    /// continuing to issue them against a `CatFileBatch` that may already be
    /// mid-`stop()` on another thread. See `read()`'s doc for what this does
    /// not cover: a request already in flight when cancellation fires still
    /// runs to completion.
    std::vector<CommitMeta> readCommits(const std::vector<ObjectId>& oids, CancellationToken token);

private:
    class Impl;

    /// The child speaks a strictly sequential protocol, so every request holds
    /// the lock. Requests are short (a memcpy from a pipe), and callers already
    /// batch, so this is not a contention point in practice.
    mutable std::mutex mutex_;
    std::unique_ptr<Impl> impl_;
    std::filesystem::path git_;
    RepoPaths paths_;
    /// Set after a protocol desynchronisation; forces a restart on next use
    /// rather than returning data from the wrong request.
    bool poisoned_ = false;
};

}  // namespace gbm
