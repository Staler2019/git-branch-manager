#include "app/bridge/DiscoveryController.h"

#include "core/base/FsUtil.h"
#include "core/git/RefStore.h"
#include "core/git/RepoState.h"

#include <QMetaObject>

#include <chrono>
#include <utility>

namespace gbm {

DiscoveryController::DiscoveryController(GitInstallation installation, QObject* parent)
    : QObject(parent), installation_(std::move(installation)) {}

DiscoveryController::~DiscoveryController() {
    scanCancel_.cancel();
    scanPool_.shutdown();
    probePool_.shutdown();
}

GitResult<void> DiscoveryController::open(const QString& databasePath) {
    if (auto opened = db_.open(std::filesystem::path(databasePath.toStdString())); !opened) {
        return opened;
    }
    scanner_ = std::make_unique<Scanner>(db_);
    return {};
}

std::vector<RepoRecord> DiscoveryController::loadFromCache() {
    auto repos = db_.repos();
    return repos ? *repos : std::vector<RepoRecord>{};
}

std::vector<BaseFolderRecord> DiscoveryController::baseFolders() {
    auto folders = db_.baseFolders();
    return folders ? *folders : std::vector<BaseFolderRecord>{};
}

GitResult<void> DiscoveryController::addBaseFolder(const QString& path) {
    const std::string canonical =
        std::filesystem::path(path.toStdString()).lexically_normal().string();
    auto added = db_.addBaseFolder(canonical);
    if (!added) {
        return fail(std::move(added).error());
    }
    return {};
}

GitResult<void> DiscoveryController::removeBaseFolder(std::int64_t id) {
    return db_.removeBaseFolder(id);
}

void DiscoveryController::cancelScan() {
    scanCancel_.cancel();
}

void DiscoveryController::startScan(ScanMode mode) {
    if (scanning_ || !scanner_) {
        return;
    }
    auto folders = db_.baseFolders();
    if (!folders || folders->empty()) {
        emit scanFinished(false, QStringLiteral("No base folders configured"));
        return;
    }

    scanning_ = true;
    scanCancel_ = CancellationSource();
    const CancellationToken token = scanCancel_.token();
    emit scanStarted();

    scanPool_.post([this, folders = *folders, mode, token] {
        std::int64_t totalDirs = 0;
        std::int64_t totalRepos = 0;
        bool cancelled = false;

        for (const BaseFolderRecord& folder : folders) {
            if (!folder.enabled || token.isCancelled()) {
                continue;
            }

            auto result = scanner_->scan(
                folder,
                mode,
                token,
                [this](const ScanProgress& progress) {
                    // Throttled by the scanner's own batching; a status-bar update
                    // per directory would flood the event loop.
                    const QString message =
                        QStringLiteral("Scanning… %1 directories, %2 repositories")
                            .arg(progress.directoriesScanned)
                            .arg(progress.reposFound);
                    QMetaObject::invokeMethod(
                        this,
                        [this, message] { emit scanProgress(message); },
                        Qt::QueuedConnection);
                },
                [this](const std::vector<RepoRecord>& batch) {
                    QMetaObject::invokeMethod(
                        this, [this, batch] { emit reposDiscovered(batch); }, Qt::QueuedConnection);
                });

            if (!result) {
                GitError error = std::move(result).error();
                QMetaObject::invokeMethod(
                    this, [this, error] { emit errorOccurred(error); }, Qt::QueuedConnection);
                continue;
            }
            totalDirs += result->directoriesScanned;
            totalRepos += result->reposFound;
            cancelled = cancelled || result->cancelled;
        }

        const QString summary =
            cancelled ? QStringLiteral("Scan cancelled after %1 directories").arg(totalDirs)
                      : QStringLiteral("Found %1 repositories in %2 directories")
                            .arg(totalRepos)
                            .arg(totalDirs);

        QMetaObject::invokeMethod(
            this,
            [this, cancelled, summary] {
                scanning_ = false;
                emit scanFinished(cancelled, summary);
            },
            Qt::QueuedConnection);
    });
}

void DiscoveryController::probeRepo(const RepoRecord& repo) {
    probePool_.post([this, repo] {
        const RepoPaths paths = repo.toPaths();

        // The witnesses: if neither HEAD nor the index has changed since the last
        // probe, the cached values are still correct and nothing needs re-reading.
        const auto headMtime = fsutil::modifiedTimeNs(paths.headFile()).value_or(0);
        const auto indexMtime = fsutil::modifiedTimeNs(paths.indexFile()).value_or(0);

        auto cached = db_.probe(repo.id);
        if (cached && *cached && (*cached)->gitDirMtimeNs == headMtime &&
            (*cached)->indexMtimeNs == indexMtime && (*cached)->probedAt > 0) {
            const RepoProbe probe = **cached;
            QMetaObject::invokeMethod(
                this,
                [this, id = repo.id, probe] { emit probeReady(id, probe); },
                Qt::QueuedConnection);
            return;
        }

        auto runner = makeProcessRunner(installation_.executable);
        RefStore refStore(*runner, paths);
        auto head = refStore.readHead(CancellationToken{});

        RepoProbe probe;
        probe.repoId = repo.id;
        probe.gitDirMtimeNs = headMtime;
        probe.indexMtimeNs = indexMtime;
        probe.probedAt = std::chrono::duration_cast<std::chrono::seconds>(
                             std::chrono::system_clock::now().time_since_epoch())
                             .count();

        if (head) {
            probe.headKind = static_cast<int>(head->kind);
            probe.headRef = head->branchName.empty() ? head->fullRef : head->branchName;
            probe.headOid = head->target;
        }

        // Ahead/behind for the current branch only: enough for the list, and it
        // comes free from the ref read rather than costing a walk per branch.
        auto refs = refStore.load(CancellationToken{});
        if (refs) {
            for (const RefInfo& ref : (*refs)->refs) {
                if (ref.isHead) {
                    probe.ahead = ref.ahead;
                    probe.behind = ref.behind;
                    probe.upstreamRef = ref.upstream;
                    break;
                }
            }
        }

        probe.inProgressFlags = RepoState::read(paths).flags;
        // dirtyFiles stays -1 here: `git status` on a 500 MB tree is far too
        // expensive to run for every row in a list. It is filled in when the
        // repository is actually opened.

        (void)db_.saveProbe(probe);
        QMetaObject::invokeMethod(
            this,
            [this, id = repo.id, probe] { emit probeReady(id, probe); },
            Qt::QueuedConnection);
    });
}

}  // namespace gbm
