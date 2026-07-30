#pragma once

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
    GitResult<Object> read(std::string_view revision);

    /// Reads and parses a commit. The common case, called in viewport batches.
    GitResult<CommitMeta> readCommit(const ObjectId& oid);

    /// Batch form. A failure on one object does not abort the rest; missing
    /// entries are simply absent from the result, so a partially-corrupt
    /// repository still browses.
    std::vector<CommitMeta> readCommits(const std::vector<ObjectId>& oids);

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
