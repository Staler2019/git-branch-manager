#pragma once

#include "core/base/CancellationToken.h"
#include "core/cache/RepoIndexDb.h"
#include "core/discovery/Scanner.h"
#include "core/git/GitExecutable.h"
#include "core/workers/ThreadPool.h"

#include <QObject>
#include <QString>

#include <memory>
#include <mutex>
#include <unordered_set>
#include <vector>

namespace gbm {

/// Owns the repository cache and drives scans.
///
/// The load order here is the whole point of the design: `loadFromCache()` is
/// synchronous, touches no filesystem, and is what the window paints first.
/// Scanning only ever happens afterwards, in the background, and only when the user
/// asks — Refresh is a button, not a startup step.
class DiscoveryController : public QObject {
    Q_OBJECT

public:
    DiscoveryController(GitInstallation installation, QObject* parent = nullptr);
    ~DiscoveryController() override;

    /// Opens the cache at the standard per-user location.
    GitResult<void> open(const QString& databasePath);

    /// Reads the cached repository list. No filesystem access at all, so this is
    /// safe to call before the first paint.
    std::vector<RepoRecord> loadFromCache();

    std::vector<BaseFolderRecord> baseFolders();

    /// `maxDepth` is how many levels below `path` are scanned; 1 means only
    /// `path` itself and its direct children.
    GitResult<void> addBaseFolder(const QString& path, int maxDepth = 1);
    GitResult<void> removeBaseFolder(std::int64_t id);

    /// Also clears the folder's stored directory signatures, so a subsequent
    /// scan actually re-walks to the new depth instead of trusting stale "no
    /// repository below here" signatures recorded under the old one.
    GitResult<void> setBaseFolderDepth(std::int64_t id, int maxDepth);

    /// Starts a scan of every enabled base folder. Incremental uses stored
    /// directory signatures to skip unchanged subtrees; Full re-stats everything.
    void startScan(ScanMode mode);

    void cancelScan();

    bool isScanning() const { return scanning_; }

    /// Re-probes a repository's cheap summary (branch, ahead/behind, dirty count)
    /// for rows the user can actually see. Rows never displayed are never probed.
    void probeRepo(const RepoRecord& repo);

signals:
    void scanStarted();
    void scanProgress(const QString& message);
    void reposDiscovered(const std::vector<RepoRecord>& repos);
    void scanFinished(bool cancelled, const QString& summary);
    void probeReady(std::int64_t repoId, const RepoProbe& probe);
    void errorOccurred(const GitError& error);

private:
    GitInstallation installation_;
    RepoIndexDb db_;
    /// A dedicated pool: a long directory walk must not starve the diff the user is
    /// waiting to see, so discovery never shares the read pool.
    ThreadPool scanPool_{"scanner", 2};
    ThreadPool probePool_{"probe", 2};
    std::unique_ptr<Scanner> scanner_;
    CancellationSource scanCancel_;
    bool scanning_ = false;

    /// Repository ids with a probe task currently queued or running. Scrolling,
    /// searching, and a completed scan can all ask to probe the same visible
    /// rows in quick succession; without this, each ask posts its own task and
    /// the pool backs up doing redundant work. `probeRepo` already checks the
    /// HEAD/index mtime witnesses before doing anything expensive, so an id is
    /// only ever held here for the duration of one in-flight task, never longer.
    std::mutex probeMutex_;
    std::unordered_set<std::int64_t> probesInFlight_;
};

}  // namespace gbm
