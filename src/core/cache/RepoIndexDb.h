#pragma once

#include "core/base/Error.h"
#include "core/base/ObjectId.h"
#include "core/cache/Database.h"
#include "core/discovery/RepoClassifier.h"

#include <cstdint>
#include <filesystem>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <vector>

namespace gbm {

struct BaseFolderRecord {
    std::int64_t id = 0;
    std::string path;
    bool enabled = true;
    int maxDepth = 1;
    bool followLinks = false;
    std::int64_t generation = 0;
    std::int64_t lastScanStarted = 0;
    std::int64_t lastScanFinished = 0;
    std::int64_t lastScanDirs = 0;
    std::int64_t lastScanMs = 0;
    /// Directories the last scan did not descend into because they lay past
    /// `maxDepth`. Surfaced so the UI can report "N folders skipped (depth
    /// limit)" instead of silently under-counting what was scanned.
    std::int64_t lastScanSkipped = 0;
};

struct RepoRecord {
    std::int64_t id = 0;
    std::int64_t baseFolderId = 0;
    std::string workDir;
    std::string gitDir;
    std::string commonDir;
    RepoKind kind = RepoKind::Normal;
    std::string name;
    std::optional<std::int64_t> parentRepoId;
    int depth = 0;
    std::int64_t discoveredAt = 0;
    std::int64_t lastSeenGeneration = 0;
    std::optional<std::int64_t> missingSince;

    RepoPaths toPaths() const { return RepoPaths(workDir, gitDir, commonDir); }
};

/// The cheap summary shown in the repository list.
///
/// Every field is explicitly "as of" a point in time. The two mtime witnesses are
/// what make that honest: if `.git/HEAD` has not changed, the cached branch name
/// is still correct and no filesystem work is needed; if it has, the row is
/// re-probed. `dirtyFiles == -1` means unknown, and the UI renders it as such
/// rather than pretending the tree is clean.
struct RepoProbe {
    std::int64_t repoId = 0;
    int headKind = 2;  ///< Matches HeadInfo::Kind.
    std::string headRef;
    ObjectId headOid;
    std::string upstreamRef;
    int ahead = 0;
    int behind = 0;
    int dirtyFiles = -1;
    int stashCount = -1;
    std::uint32_t inProgressFlags = 0;
    std::int64_t probedAt = 0;
    std::int64_t gitDirMtimeNs = 0;
    std::int64_t indexMtimeNs = 0;
};

/// Signature of one directory, used to prune unchanged subtrees on an incremental
/// scan. If mtime and child count both match and the subtree held no repository
/// last time, the whole subtree is skipped.
struct DirSignature {
    std::int64_t baseFolderId = 0;
    std::string dirPath;
    std::int64_t mtimeNs = 0;
    std::int64_t childDirs = 0;
    bool hadRepo = false;
};

/// Persistent index of discovered repositories.
///
/// This is what makes startup fast: the window paints the repository list from
/// this database with *zero* filesystem access, and only then does it lazily
/// re-validate the rows the user can actually see. Scanning several base folders
/// containing hundreds of repositories takes seconds, and doing it before the
/// first paint would be exactly the slow startup the design set out to avoid.
class RepoIndexDb {
public:
    /// Bumped whenever the schema changes; `migrate()` upgrades in place.
    ///
    /// Schema 2 lowered the default `max_depth` from 6 to 1 (see `addBaseFolder`)
    /// and, on upgrade, clears every existing base folder rather than silently
    /// reinterpreting a folder the user already configured under the old default.
    ///
    /// Schema 3 added `base_folder.last_scan_skipped`. Unlike schema 2, existing
    /// base folders are preserved on upgrade -- a new column with a `DEFAULT 0`
    /// is safe to add onto rows that already exist, there is no stale-default
    /// reinterpretation risk the way there was for `max_depth`.
    static constexpr int kSchemaVersion = 3;

    GitResult<void> open(const std::filesystem::path& path);
    GitResult<void> openInMemory();
    void close();

    GitResult<void> migrate();

    // --- base folders ------------------------------------------------------
    GitResult<std::int64_t> addBaseFolder(const std::string& path,
                                          int maxDepth = 1,
                                          bool followLinks = false);
    GitResult<void> removeBaseFolder(std::int64_t id);
    GitResult<std::vector<BaseFolderRecord>> baseFolders() const;
    GitResult<void> setBaseFolderEnabled(std::int64_t id, bool enabled);

    /// Changes how many levels below the base folder are scanned. Also clears its
    /// stored directory signatures: a signature recorded "no repository below
    /// here" under the old depth would otherwise wrongly prune a subtree the new,
    /// deeper scan should actually visit.
    GitResult<void> setBaseFolderMaxDepth(std::int64_t id, int maxDepth);

    /// Bumps and returns the generation for a scan. Rows not seen with this
    /// generation are candidates for soft deletion at the end of a *completed*
    /// scan.
    GitResult<std::int64_t> beginScan(std::int64_t baseFolderId);
    GitResult<void> finishScan(std::int64_t baseFolderId,
                               std::int64_t dirsScanned,
                               std::int64_t elapsedMs,
                               std::int64_t dirsSkipped = 0);

    // --- repositories ------------------------------------------------------
    GitResult<std::int64_t> upsertRepo(const RepoRecord& record);
    GitResult<std::vector<RepoRecord>> repos(bool includeMissing = false) const;
    GitResult<std::vector<RepoRecord>> reposInBaseFolder(std::int64_t baseFolderId) const;
    GitResult<std::optional<RepoRecord>> findRepoByGitDir(const std::string& gitDir) const;

    /// Marks repositories not seen in `generation` as missing. Only ever called
    /// after a scan that ran to completion: doing this after a cancelled scan
    /// would mark every unvisited repository as gone.
    GitResult<int> markMissing(std::int64_t baseFolderId, std::int64_t generation);

    /// Bumps `last_seen_gen` for every repository under `pathPrefix` without
    /// visiting the filesystem.
    ///
    /// This is what makes incremental pruning safe. When a scan skips an
    /// unchanged subtree it never *sees* the repositories inside it, so without
    /// this they would fall behind the current generation and the mark-missing
    /// sweep would delete them — the user's whole repository list would empty out
    /// after a single Refresh.
    GitResult<int> touchReposUnder(std::int64_t baseFolderId,
                                   const std::string& pathPrefix,
                                   std::int64_t generation);

    GitResult<void> deleteRepo(std::int64_t id);

    // --- probes ------------------------------------------------------------
    GitResult<void> saveProbe(const RepoProbe& probe);
    GitResult<std::optional<RepoProbe>> probe(std::int64_t repoId) const;

    // --- incremental-scan signatures ---------------------------------------
    GitResult<std::optional<DirSignature>> dirSignature(std::int64_t baseFolderId,
                                                        const std::string& dirPath) const;
    GitResult<void> saveDirSignature(const DirSignature& signature);
    GitResult<void> clearDirSignatures(std::int64_t baseFolderId);

    // --- search ------------------------------------------------------------
    /// Substring match on name or path, answered entirely from SQLite so it stays
    /// instant with thousands of repositories.
    GitResult<std::vector<RepoRecord>> search(const std::string& query,
                                              std::size_t limit = 200) const;

    /// Runs `body` as one transaction with the connection lock held for its whole
    /// duration. Exists so callers with their own multi-statement writes — the
    /// scanner's batched inserts and directory-signature flush — serialise
    /// against every other use of this connection instead of only against
    /// themselves.
    ///
    /// This is why the raw `Database` is not exposed: an unguarded `BEGIN
    /// IMMEDIATE` from a second thread would land its writes inside this
    /// transaction and lose them to this transaction's `ROLLBACK`, which is
    /// exactly the bug that used to crash a scan of a large tree (concurrent,
    /// unsynchronised access to one `sqlite3*` from the scan pool, the probe
    /// pool, and the UI thread).
    GitResult<void> transaction(const std::function<GitResult<void>()>& body);

    /// Sets the schema version directly, bypassing `migrate()`. Only exists to let
    /// tests exercise the upgrade path; nothing in the running app should ever set
    /// an arbitrary version.
    GitResult<void> forceSchemaVersionForTest(int version);

private:
    GitResult<void> createSchema();
    GitResult<int> readSchemaVersion() const;

    mutable Database db_;

    /// Serialises every access to `db_`. `Database::prepare()` returns a
    /// `Statement` that the caller then binds and steps outside any lock inside
    /// `Database` itself, so the lock has to live here, one level up, where the
    /// whole statement lifetime — and whole transactions — are visible.
    /// Recursive because most of the methods above call each other (`migrate()`
    /// calls `createSchema()`, `transaction()`'s body calls back into this class)
    /// from the same thread.
    mutable std::recursive_mutex mutex_;
};

}  // namespace gbm
