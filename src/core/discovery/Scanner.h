#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/FsUtil.h"
#include "core/cache/RepoIndexDb.h"
#include "core/discovery/RepoClassifier.h"
#include "core/discovery/SkipRules.h"

#include <atomic>
#include <cstdint>
#include <deque>
#include <filesystem>
#include <functional>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

namespace gbm {

enum class ScanMode {
    /// Uses stored directory signatures to skip unchanged subtrees. What the
    /// Refresh button does.
    Incremental,
    /// Re-stats everything and rebuilds signatures. What Force Refresh does.
    Full,
};

struct ScanProgress {
    std::int64_t directoriesScanned = 0;
    std::int64_t directoriesSkipped = 0;
    std::int64_t reposFound = 0;
    std::string currentPath;
};

struct ScanResult {
    std::int64_t directoriesScanned = 0;
    std::int64_t directoriesSkipped = 0;
    std::int64_t reposFound = 0;
    std::int64_t reposMarkedMissing = 0;
    std::int64_t elapsedMs = 0;
    bool cancelled = false;
};

/// Walks base folders looking for git repositories.
///
/// Two properties make this usable on a real machine:
///
///  * **Cancellation never destroys data.** A cancelled scan commits whatever it
///    found but skips the mark-missing sweep entirely. Marking every unvisited
///    repository as gone because the user hit Cancel would be far worse than
///    having a slightly stale list.
///  * **Incremental pruning.** A directory whose mtime and child count are
///    unchanged, and which held no repository last time, is skipped wholesale.
///    That turns a repeat scan of a large tree from tens of seconds into a couple.
class Scanner {
public:
    /// Both callbacks are invoked on scan worker threads, never on the caller's,
    /// but never concurrently with each other or with themselves: the scanner
    /// serialises them, so a callback may touch its own state without locking.
    using ProgressCallback = std::function<void(const ScanProgress&)>;
    /// Called with each batch of newly found repositories, so the UI can insert
    /// rows as they appear rather than waiting for the whole scan.
    using BatchCallback = std::function<void(const std::vector<RepoRecord>&)>;

    /// Repositories are reported (and committed) in batches of this size.
    static constexpr std::size_t kBatchSize = 20;

    Scanner(RepoIndexDb& db, SkipRules rules = SkipRules{});

    /// Scans one base folder. Runs on the caller's thread, which must not be the
    /// UI thread.
    GitResult<ScanResult> scan(const BaseFolderRecord& baseFolder,
                               ScanMode mode,
                               CancellationToken token,
                               const ProgressCallback& onProgress = nullptr,
                               const BatchCallback& onBatch = nullptr);

    /// Worker count for a base folder. Parallel readdir helps on local SSDs and
    /// actively hurts on network mounts, so those drop to a single worker.
    static std::size_t workerCountFor(const std::filesystem::path& path);

private:
    struct WorkItem {
        std::filesystem::path path;
        int depth = 0;
    };

    struct SharedState {
        std::mutex mutex;
        std::deque<WorkItem> queue;
        std::unordered_set<fsutil::FileId, fsutil::FileIdHash> visited;
        std::vector<RepoRecord> pending;
        std::int64_t scanned = 0;
        std::int64_t skipped = 0;
        std::int64_t found = 0;
        std::size_t activeWorkers = 0;
        std::vector<DirSignature> signatures;
        bool failed = false;
        GitError error;
    };

    void workerLoop(SharedState& state,
                    const BaseFolderRecord& baseFolder,
                    ScanMode mode,
                    std::int64_t generation,
                    CancellationToken token,
                    const ProgressCallback& onProgress,
                    const BatchCallback& onBatch);

    GitResult<void> flushPending(SharedState& state, const BatchCallback& onBatch);

    RepoIndexDb& db_;
    SkipRules rules_;

    /// Serialises the progress and batch callbacks, so callers get the guarantee
    /// documented on ProgressCallback instead of concurrent invocations.
    std::mutex callbackMutex_;
};

}  // namespace gbm
