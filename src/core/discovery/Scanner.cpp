#include "core/discovery/Scanner.h"

#include "core/base/Logging.h"
#include "core/base/ThreadCheck.h"

#include <algorithm>
#include <chrono>
#include <thread>
#include <utility>

namespace gbm {

namespace {

std::int64_t nowSeconds() {
    return std::chrono::duration_cast<std::chrono::seconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

}  // namespace

Scanner::Scanner(RepoIndexDb& db, SkipRules rules) : db_(db), rules_(std::move(rules)) {}

std::size_t Scanner::workerCountFor(const std::filesystem::path& path) {
    // On a network mount, concurrent readdir turns into contention on a single
    // connection and makes the scan slower, not faster.
    if (fsutil::isNetworkPath(path)) {
        return 1;
    }
    const unsigned hardware = std::thread::hardware_concurrency();
    return std::clamp<std::size_t>(hardware == 0 ? 2 : hardware / 2, 2, 4);
}

GitResult<void> Scanner::flushPending(SharedState& state, const BatchCallback& onBatch) {
    std::vector<RepoRecord> batch;
    {
        std::lock_guard<std::mutex> lock(state.mutex);
        batch.swap(state.pending);
    }
    if (batch.empty()) {
        return {};
    }

    // One transaction per batch rather than per row: 20 inserts in one commit is
    // roughly as fast as one, and 100k individual commits would take minutes.
    GitResult<void> committed;
    {
        std::lock_guard<std::mutex> dbLock(dbMutex_);
        committed = db_.database().transaction([this, &batch]() -> GitResult<void> {
            for (const RepoRecord& record : batch) {
                auto id = db_.upsertRepo(record);
                if (!id) {
                    return fail(std::move(id).error());
                }
            }
            return {};
        });
    }
    if (!committed) {
        return committed;
    }

    if (onBatch) {
        onBatch(batch);
    }
    return {};
}

void Scanner::workerLoop(SharedState& state,
                         const BaseFolderRecord& baseFolder,
                         ScanMode mode,
                         std::int64_t generation,
                         CancellationToken token,
                         const ProgressCallback& onProgress,
                         const BatchCallback& onBatch) {
    for (;;) {
        WorkItem item;
        {
            std::unique_lock<std::mutex> lock(state.mutex);
            if (state.queue.empty()) {
                // No work left and nobody else is producing any: the walk is done.
                if (state.activeWorkers == 0) {
                    return;
                }
                lock.unlock();
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
                continue;
            }
            item = std::move(state.queue.front());
            state.queue.pop_front();
            ++state.activeWorkers;
        }

        // Decrements activeWorkers however this iteration ends.
        struct ActiveGuard {
            SharedState& state;

            ~ActiveGuard() {
                std::lock_guard<std::mutex> lock(state.mutex);
                --state.activeWorkers;
            }
        } guard{state};

        if (token.isCancelled()) {
            return;
        }
        if (item.depth > baseFolder.maxDepth) {
            std::lock_guard<std::mutex> lock(state.mutex);
            ++state.skipped;
            continue;
        }
        if (item.depth > 0 && rules_.shouldSkip(item.path)) {
            std::lock_guard<std::mutex> lock(state.mutex);
            ++state.skipped;
            continue;
        }

        const std::string key = fsutil::canonicalKey(item.path);
        const auto mtime = fsutil::modifiedTimeNs(item.path);

        // --- incremental pruning ------------------------------------------
        if (mode == ScanMode::Incremental && mtime) {
            GitResult<std::optional<DirSignature>> stored = std::optional<DirSignature>{};
            {
                std::lock_guard<std::mutex> dbLock(dbMutex_);
                stored = db_.dirSignature(baseFolder.id, key);
            }
            if (stored && *stored && (*stored)->mtimeNs == *mtime && !(*stored)->hadRepo) {
                // Unchanged since the last scan. Skipping the whole subtree here is
                // what makes Refresh fast on a big tree.
                //
                // But the repositories inside it are now never visited, so their
                // last_seen_gen has to be advanced explicitly — otherwise the
                // mark-missing sweep at the end would decide they had all vanished
                // and empty the user's list.
                {
                    // The raw native path, not the canonical key: repo rows store
                    // native separators, so a forward-slashed key would never match
                    // the prefix on Windows.
                    std::lock_guard<std::mutex> dbLock(dbMutex_);
                    auto touched =
                        db_.touchReposUnder(baseFolder.id, item.path.string(), generation);
                    if (!touched) {
                        std::lock_guard<std::mutex> lock(state.mutex);
                        state.failed = true;
                        state.error = std::move(touched).error();
                        return;
                    }
                }
                std::lock_guard<std::mutex> lock(state.mutex);
                ++state.skipped;
                continue;
            }
        }

        // --- classify ------------------------------------------------------
        ClassifiedRepo classified = RepoClassifier::classify(item.path);
        bool hadRepo = false;

        if (classified.isRepo()) {
            hadRepo = true;
            RepoRecord record;
            record.baseFolderId = baseFolder.id;
            record.workDir = classified.paths.workDir().string();
            record.gitDir = classified.paths.gitDir().string();
            record.commonDir = classified.paths.commonDir().string();
            record.kind = classified.kind;
            record.name = classified.paths.displayName();
            record.depth = item.depth;
            record.discoveredAt = nowSeconds();
            record.lastSeenGeneration = generation;

            std::size_t pendingCount = 0;
            {
                std::lock_guard<std::mutex> lock(state.mutex);
                state.pending.push_back(std::move(record));
                ++state.found;
                pendingCount = state.pending.size();
            }
            if (pendingCount >= kBatchSize) {
                if (auto flushed = flushPending(state, onBatch); !flushed) {
                    std::lock_guard<std::mutex> lock(state.mutex);
                    state.failed = true;
                    state.error = std::move(flushed).error();
                    return;
                }
            }
        }

        // --- enumerate children -------------------------------------------
        std::int64_t childDirs = 0;
        std::vector<WorkItem> children;

        // A repository's own contents are not scanned for more repositories:
        // descending would surface every submodule working copy as a top-level
        // entry and multiply the work. Submodules and linked worktrees are
        // discovered from the parent's metadata instead.
        const bool descend = !classified.isRepo();

        std::error_code ec;
        std::filesystem::directory_iterator iterator(
            fsutil::longPathSafe(item.path),
            std::filesystem::directory_options::skip_permission_denied,
            ec);
        if (!ec) {
            const std::filesystem::directory_iterator end;
            for (; iterator != end; iterator.increment(ec)) {
                if (ec) {
                    break;  // Unreadable partway through; keep what we have.
                }
                const std::filesystem::directory_entry& entry = *iterator;

                std::error_code dirEc;
                if (!entry.is_directory(dirEc) || dirEc) {
                    continue;
                }
                ++childDirs;

                if (!descend) {
                    continue;
                }
                // Placeholder files are downloaded on access; scanning a synced
                // folder without this check can pull gigabytes over the network.
                if (fsutil::isCloudPlaceholder(entry)) {
                    std::lock_guard<std::mutex> lock(state.mutex);
                    ++state.skipped;
                    continue;
                }
                if (fsutil::isLinkLike(entry)) {
                    if (!baseFolder.followLinks) {
                        continue;
                    }
                    // Following links requires cycle detection by file identity;
                    // path comparison cannot see a junction loop.
                    if (auto id = fsutil::fileIdOf(entry.path())) {
                        std::lock_guard<std::mutex> lock(state.mutex);
                        if (!state.visited.insert(*id).second) {
                            continue;
                        }
                    }
                }
                children.push_back({entry.path(), item.depth + 1});
            }
        }

        {
            std::lock_guard<std::mutex> lock(state.mutex);
            ++state.scanned;
            for (auto& child : children) {
                state.queue.push_back(std::move(child));
            }
            if (mtime) {
                DirSignature signature;
                signature.baseFolderId = baseFolder.id;
                signature.dirPath = key;
                signature.mtimeNs = *mtime;
                signature.childDirs = childDirs;
                signature.hadRepo = hadRepo;
                state.signatures.push_back(std::move(signature));
            }
        }

        if (onProgress) {
            ScanProgress progress;
            {
                std::lock_guard<std::mutex> lock(state.mutex);
                progress.directoriesScanned = state.scanned;
                progress.directoriesSkipped = state.skipped;
                progress.reposFound = state.found;
            }
            progress.currentPath = item.path.string();
            onProgress(progress);
        }
    }
}

GitResult<ScanResult> Scanner::scan(const BaseFolderRecord& baseFolder,
                                    ScanMode mode,
                                    CancellationToken token,
                                    const ProgressCallback& onProgress,
                                    const BatchCallback& onBatch) {
    GBM_ASSERT_NOT_UI_THREAD();

    const auto started = std::chrono::steady_clock::now();
    ScanResult result;

    std::error_code ec;
    if (!std::filesystem::is_directory(fsutil::longPathSafe(baseFolder.path), ec) || ec) {
        return fail(GitError::Code::NotFound,
                    "The folder " + baseFolder.path + " could not be read");
    }

    auto generation = db_.beginScan(baseFolder.id);
    if (!generation) {
        return fail(std::move(generation).error());
    }

    if (mode == ScanMode::Full) {
        if (auto cleared = db_.clearDirSignatures(baseFolder.id); !cleared) {
            return fail(std::move(cleared).error());
        }
    }

    SharedState state;
    state.queue.push_back({std::filesystem::path(baseFolder.path), 0});

    const std::size_t workers = workerCountFor(baseFolder.path);
    std::vector<std::thread> threads;
    threads.reserve(workers);
    for (std::size_t i = 0; i < workers; ++i) {
        threads.emplace_back(
            [&] { workerLoop(state, baseFolder, mode, *generation, token, onProgress, onBatch); });
    }
    for (auto& thread : threads) {
        thread.join();
    }

    if (state.failed) {
        return fail(std::move(state.error));
    }

    if (auto flushed = flushPending(state, onBatch); !flushed) {
        return fail(std::move(flushed).error());
    }

    // Signatures are written last, in one transaction: writing them as we went
    // would mean a cancelled scan leaves signatures claiming subtrees were fully
    // examined when they were not, and the next incremental scan would skip them.
    if (!token.isCancelled() && !state.signatures.empty()) {
        auto saved = db_.database().transaction([this, &state]() -> GitResult<void> {
            for (const DirSignature& signature : state.signatures) {
                if (auto ok = db_.saveDirSignature(signature); !ok) {
                    return ok;
                }
            }
            return {};
        });
        if (!saved) {
            return fail(std::move(saved).error());
        }
    }

    result.cancelled = token.isCancelled();

    // The mark-missing sweep runs only for a scan that completed. After a
    // cancelled scan most of the tree was never visited, so this would mark
    // perfectly healthy repositories as gone.
    if (!result.cancelled) {
        auto marked = db_.markMissing(baseFolder.id, *generation);
        if (!marked) {
            return fail(std::move(marked).error());
        }
        result.reposMarkedMissing = *marked;
    }

    result.directoriesScanned = state.scanned;
    result.directoriesSkipped = state.skipped;
    result.reposFound = state.found;
    result.elapsedMs = std::chrono::duration_cast<std::chrono::milliseconds>(
                           std::chrono::steady_clock::now() - started)
                           .count();

    if (!result.cancelled) {
        if (auto finished =
                db_.finishScan(baseFolder.id, result.directoriesScanned, result.elapsedMs);
            !finished) {
            return fail(std::move(finished).error());
        }
    }

    logMessage(LogLevel::Info,
               "Scanned " + baseFolder.path + ": " + std::to_string(result.directoriesScanned) +
                   " directories, " + std::to_string(result.reposFound) + " repositories, " +
                   std::to_string(result.elapsedMs) + " ms" +
                   (result.cancelled ? " (cancelled)" : ""));
    return result;
}

}  // namespace gbm
