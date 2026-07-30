#include "core/cache/RepoIndexDb.h"

#include "core/base/Logging.h"

#include <chrono>
#include <sqlite3.h>
#include <utility>

namespace gbm {

namespace {

std::int64_t nowSeconds() {
    return std::chrono::duration_cast<std::chrono::seconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

constexpr std::string_view kSchema = R"sql(
CREATE TABLE IF NOT EXISTS schema_info(version INTEGER NOT NULL);

CREATE TABLE IF NOT EXISTS base_folder(
  id                 INTEGER PRIMARY KEY,
  path               TEXT NOT NULL UNIQUE,
  enabled            INTEGER NOT NULL DEFAULT 1,
  max_depth          INTEGER NOT NULL DEFAULT 6,
  follow_links       INTEGER NOT NULL DEFAULT 0,
  generation         INTEGER NOT NULL DEFAULT 0,
  last_scan_started  INTEGER NOT NULL DEFAULT 0,
  last_scan_finished INTEGER NOT NULL DEFAULT 0,
  last_scan_dirs     INTEGER NOT NULL DEFAULT 0,
  last_scan_ms       INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS repo(
  id              INTEGER PRIMARY KEY,
  base_folder_id  INTEGER NOT NULL REFERENCES base_folder(id) ON DELETE CASCADE,
  work_dir        TEXT,
  git_dir         TEXT NOT NULL,
  common_dir      TEXT NOT NULL,
  kind            INTEGER NOT NULL,
  name            TEXT NOT NULL,
  parent_repo_id  INTEGER REFERENCES repo(id) ON DELETE CASCADE,
  depth           INTEGER NOT NULL DEFAULT 0,
  discovered_at   INTEGER NOT NULL,
  last_seen_gen   INTEGER NOT NULL,
  missing_since   INTEGER,
  UNIQUE(git_dir, work_dir)
);

CREATE INDEX IF NOT EXISTS repo_by_base ON repo(base_folder_id, name COLLATE NOCASE);
CREATE INDEX IF NOT EXISTS repo_by_common ON repo(common_dir);

CREATE TABLE IF NOT EXISTS repo_probe(
  repo_id          INTEGER PRIMARY KEY REFERENCES repo(id) ON DELETE CASCADE,
  head_kind        INTEGER NOT NULL DEFAULT 2,
  head_ref         TEXT,
  head_oid         BLOB,
  upstream_ref     TEXT,
  ahead            INTEGER NOT NULL DEFAULT 0,
  behind           INTEGER NOT NULL DEFAULT 0,
  dirty_files      INTEGER NOT NULL DEFAULT -1,
  stash_count      INTEGER NOT NULL DEFAULT -1,
  in_progress      INTEGER NOT NULL DEFAULT 0,
  probed_at        INTEGER NOT NULL DEFAULT 0,
  git_dir_mtime_ns INTEGER NOT NULL DEFAULT 0,
  index_mtime_ns   INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS dir_sig(
  base_folder_id INTEGER NOT NULL REFERENCES base_folder(id) ON DELETE CASCADE,
  dir_path       TEXT NOT NULL,
  mtime_ns       INTEGER NOT NULL,
  child_dirs     INTEGER NOT NULL,
  had_repo       INTEGER NOT NULL,
  PRIMARY KEY(base_folder_id, dir_path)
) WITHOUT ROWID;

CREATE TABLE IF NOT EXISTS skip_rule(
  id         INTEGER PRIMARY KEY,
  pattern    TEXT NOT NULL,
  is_builtin INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS user_meta(
  repo_id        INTEGER PRIMARY KEY REFERENCES repo(id) ON DELETE CASCADE,
  pinned         INTEGER NOT NULL DEFAULT 0,
  color          INTEGER NOT NULL DEFAULT 0,
  alias          TEXT,
  last_opened_at INTEGER NOT NULL DEFAULT 0,
  group_name     TEXT
);
)sql";

RepoRecord readRepoRow(const Statement& statement) {
    RepoRecord record;
    record.id = statement.columnInt(0);
    record.baseFolderId = statement.columnInt(1);
    record.workDir = statement.columnText(2);
    record.gitDir = statement.columnText(3);
    record.commonDir = statement.columnText(4);
    record.kind = static_cast<RepoKind>(statement.columnInt(5));
    record.name = statement.columnText(6);
    if (!statement.columnIsNull(7)) {
        record.parentRepoId = statement.columnInt(7);
    }
    record.depth = static_cast<int>(statement.columnInt(8));
    record.discoveredAt = statement.columnInt(9);
    record.lastSeenGeneration = statement.columnInt(10);
    if (!statement.columnIsNull(11)) {
        record.missingSince = statement.columnInt(11);
    }
    return record;
}

constexpr std::string_view kRepoColumns =
    "id, base_folder_id, work_dir, git_dir, common_dir, kind, name, parent_repo_id, depth, "
    "discovered_at, last_seen_gen, missing_since";

}  // namespace

GitResult<void> RepoIndexDb::open(const std::filesystem::path& path) {
    if (auto opened = db_.open(path, false); !opened) {
        return opened;
    }
    return migrate();
}

GitResult<void> RepoIndexDb::openInMemory() {
    if (auto opened = db_.openInMemory(); !opened) {
        return opened;
    }
    return migrate();
}

void RepoIndexDb::close() {
    db_.close();
}

GitResult<int> RepoIndexDb::readSchemaVersion() const {
    auto statement = db_.prepare("SELECT version FROM schema_info LIMIT 1;");
    if (!statement) {
        return 0;  // Table absent: a fresh database.
    }
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return *stepped ? static_cast<int>(statement->columnInt(0)) : 0;
}

GitResult<void> RepoIndexDb::createSchema() {
    if (auto created = db_.execute(kSchema); !created) {
        return created;
    }
    auto statement = db_.prepare("INSERT INTO schema_info(version) VALUES(?1);");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, static_cast<std::int64_t>(kSchemaVersion));
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return {};
}

GitResult<void> RepoIndexDb::migrate() {
    auto version = readSchemaVersion();
    if (!version) {
        return fail(std::move(version).error());
    }

    if (*version == 0) {
        return db_.transaction([this] { return createSchema(); });
    }
    if (*version == kSchemaVersion) {
        return {};
    }
    if (*version > kSchemaVersion) {
        // A newer build wrote this cache. Refusing beats corrupting it; the cache
        // is rebuildable, so the user loses nothing by starting fresh.
        return fail(GitError::Code::Unsupported,
                    "The repository cache was created by a newer version of this application",
                    "cache schema " + std::to_string(*version) + ", supported " +
                        std::to_string(kSchemaVersion));
    }

    // Future upgrades land here, one step per version.
    logMessage(LogLevel::Info,
               "Upgrading repository cache from schema " + std::to_string(*version) + " to " +
                   std::to_string(kSchemaVersion));
    return db_.transaction([this] {
        if (auto created = db_.execute(kSchema); !created) {
            return created;
        }
        return db_.execute("UPDATE schema_info SET version = " + std::to_string(kSchemaVersion) +
                           ";");
    });
}

GitResult<std::int64_t> RepoIndexDb::addBaseFolder(const std::string& path,
                                                   int maxDepth,
                                                   bool followLinks) {
    auto statement = db_.prepare(
        "INSERT INTO base_folder(path, enabled, max_depth, follow_links) "
        "VALUES(?1, 1, ?2, ?3) "
        "ON CONFLICT(path) DO UPDATE SET enabled=1, max_depth=?2, follow_links=?3;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, path);
    statement->bind(2, static_cast<std::int64_t>(maxDepth));
    statement->bind(3, static_cast<std::int64_t>(followLinks ? 1 : 0));
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }

    auto lookup = db_.prepare("SELECT id FROM base_folder WHERE path = ?1;");
    if (!lookup) {
        return fail(std::move(lookup).error());
    }
    lookup->bind(1, path);
    auto found = lookup->step();
    if (!found) {
        return fail(std::move(found).error());
    }
    if (!*found) {
        return fail(GitError::Code::Database, "Could not record the base folder");
    }
    return lookup->columnInt(0);
}

GitResult<void> RepoIndexDb::removeBaseFolder(std::int64_t id) {
    auto statement = db_.prepare("DELETE FROM base_folder WHERE id = ?1;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, id);
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return {};
}

GitResult<void> RepoIndexDb::setBaseFolderEnabled(std::int64_t id, bool enabled) {
    auto statement = db_.prepare("UPDATE base_folder SET enabled = ?2 WHERE id = ?1;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, id);
    statement->bind(2, static_cast<std::int64_t>(enabled ? 1 : 0));
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return {};
}

GitResult<std::vector<BaseFolderRecord>> RepoIndexDb::baseFolders() const {
    auto statement = db_.prepare(
        "SELECT id, path, enabled, max_depth, follow_links, generation, last_scan_started, "
        "last_scan_finished, last_scan_dirs, last_scan_ms FROM base_folder ORDER BY path;");
    if (!statement) {
        return fail(std::move(statement).error());
    }

    std::vector<BaseFolderRecord> folders;
    for (;;) {
        auto stepped = statement->step();
        if (!stepped) {
            return fail(std::move(stepped).error());
        }
        if (!*stepped) {
            break;
        }
        BaseFolderRecord record;
        record.id = statement->columnInt(0);
        record.path = statement->columnText(1);
        record.enabled = statement->columnInt(2) != 0;
        record.maxDepth = static_cast<int>(statement->columnInt(3));
        record.followLinks = statement->columnInt(4) != 0;
        record.generation = statement->columnInt(5);
        record.lastScanStarted = statement->columnInt(6);
        record.lastScanFinished = statement->columnInt(7);
        record.lastScanDirs = statement->columnInt(8);
        record.lastScanMs = statement->columnInt(9);
        folders.push_back(std::move(record));
    }
    return folders;
}

GitResult<std::int64_t> RepoIndexDb::beginScan(std::int64_t baseFolderId) {
    auto statement = db_.prepare(
        "UPDATE base_folder SET generation = generation + 1, last_scan_started = ?2 "
        "WHERE id = ?1;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, baseFolderId);
    statement->bind(2, nowSeconds());
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }

    auto lookup = db_.prepare("SELECT generation FROM base_folder WHERE id = ?1;");
    if (!lookup) {
        return fail(std::move(lookup).error());
    }
    lookup->bind(1, baseFolderId);
    auto found = lookup->step();
    if (!found) {
        return fail(std::move(found).error());
    }
    if (!*found) {
        return fail(GitError::Code::NotFound, "No such base folder");
    }
    return lookup->columnInt(0);
}

GitResult<void> RepoIndexDb::finishScan(std::int64_t baseFolderId,
                                        std::int64_t dirsScanned,
                                        std::int64_t elapsedMs) {
    auto statement = db_.prepare(
        "UPDATE base_folder SET last_scan_finished = ?2, last_scan_dirs = ?3, last_scan_ms = ?4 "
        "WHERE id = ?1;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, baseFolderId);
    statement->bind(2, nowSeconds());
    statement->bind(3, dirsScanned);
    statement->bind(4, elapsedMs);
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return {};
}

GitResult<std::int64_t> RepoIndexDb::upsertRepo(const RepoRecord& record) {
    // A repository that reappears after being marked missing must come back
    // rather than being duplicated, so missing_since is cleared here.
    auto statement = db_.prepare(
        "INSERT INTO repo(base_folder_id, work_dir, git_dir, common_dir, kind, name, "
        "                 parent_repo_id, depth, discovered_at, last_seen_gen, missing_since) "
        "VALUES(?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, NULL) "
        "ON CONFLICT(git_dir, work_dir) DO UPDATE SET "
        "  base_folder_id = ?1, common_dir = ?4, kind = ?5, name = ?6, parent_repo_id = ?7, "
        "  depth = ?8, last_seen_gen = ?10, missing_since = NULL;");
    if (!statement) {
        return fail(std::move(statement).error());
    }

    statement->bind(1, record.baseFolderId);
    statement->bind(2, record.workDir);
    statement->bind(3, record.gitDir);
    statement->bind(4, record.commonDir);
    statement->bind(5, static_cast<std::int64_t>(record.kind));
    statement->bind(6, record.name);
    if (record.parentRepoId) {
        statement->bind(7, *record.parentRepoId);
    } else {
        statement->bindNull(7);
    }
    statement->bind(8, static_cast<std::int64_t>(record.depth));
    statement->bind(9, record.discoveredAt != 0 ? record.discoveredAt : nowSeconds());
    statement->bind(10, record.lastSeenGeneration);

    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }

    auto lookup = db_.prepare("SELECT id FROM repo WHERE git_dir = ?1 AND work_dir IS ?2;");
    if (!lookup) {
        return fail(std::move(lookup).error());
    }
    lookup->bind(1, record.gitDir);
    lookup->bind(2, record.workDir);
    auto found = lookup->step();
    if (!found) {
        return fail(std::move(found).error());
    }
    return *found ? lookup->columnInt(0) : db_.lastInsertRowId();
}

GitResult<std::vector<RepoRecord>> RepoIndexDb::repos(bool includeMissing) const {
    const std::string sql = "SELECT " + std::string(kRepoColumns) + " FROM repo" +
                            (includeMissing ? "" : " WHERE missing_since IS NULL") +
                            " ORDER BY name COLLATE NOCASE;";
    auto statement = db_.prepare(sql);
    if (!statement) {
        return fail(std::move(statement).error());
    }

    std::vector<RepoRecord> records;
    for (;;) {
        auto stepped = statement->step();
        if (!stepped) {
            return fail(std::move(stepped).error());
        }
        if (!*stepped) {
            break;
        }
        records.push_back(readRepoRow(*statement));
    }
    return records;
}

GitResult<std::vector<RepoRecord>> RepoIndexDb::reposInBaseFolder(std::int64_t baseFolderId) const {
    const std::string sql = "SELECT " + std::string(kRepoColumns) +
                            " FROM repo WHERE base_folder_id = ?1 AND missing_since IS NULL "
                            "ORDER BY name COLLATE NOCASE;";
    auto statement = db_.prepare(sql);
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, baseFolderId);

    std::vector<RepoRecord> records;
    for (;;) {
        auto stepped = statement->step();
        if (!stepped) {
            return fail(std::move(stepped).error());
        }
        if (!*stepped) {
            break;
        }
        records.push_back(readRepoRow(*statement));
    }
    return records;
}

GitResult<std::optional<RepoRecord>> RepoIndexDb::findRepoByGitDir(
    const std::string& gitDir) const {
    const std::string sql =
        "SELECT " + std::string(kRepoColumns) + " FROM repo WHERE git_dir = ?1 LIMIT 1;";
    auto statement = db_.prepare(sql);
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, gitDir);
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    if (!*stepped) {
        return std::optional<RepoRecord>{};
    }
    return std::optional<RepoRecord>(readRepoRow(*statement));
}

GitResult<int> RepoIndexDb::markMissing(std::int64_t baseFolderId, std::int64_t generation) {
    // Soft delete only: user metadata (pins, colours, aliases) survives a
    // temporarily unmounted drive, and the row comes back on the next scan.
    auto statement = db_.prepare(
        "UPDATE repo SET missing_since = ?3 "
        "WHERE base_folder_id = ?1 AND last_seen_gen < ?2 AND missing_since IS NULL;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, baseFolderId);
    statement->bind(2, generation);
    statement->bind(3, nowSeconds());
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return sqlite3_changes(db_.raw());
}

GitResult<int> RepoIndexDb::touchReposUnder(std::int64_t baseFolderId,
                                            const std::string& pathPrefix,
                                            std::int64_t generation) {
    auto statement = db_.prepare(
        "UPDATE repo SET last_seen_gen = ?3 "
        "WHERE base_folder_id = ?1 AND (work_dir LIKE ?2 ESCAPE '\\' OR "
        "                               git_dir LIKE ?2 ESCAPE '\\');");
    if (!statement) {
        return fail(std::move(statement).error());
    }

    std::string escaped;
    escaped.reserve(pathPrefix.size() + 4);
    for (char c : pathPrefix) {
        if (c == '%' || c == '_' || c == '\\') {
            escaped.push_back('\\');
        }
        escaped.push_back(c);
    }
    // Prefix match on the directory, including the directory itself.
    const std::string pattern = escaped + "%";

    statement->bind(1, baseFolderId);
    statement->bind(2, pattern);
    statement->bind(3, generation);
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return sqlite3_changes(db_.raw());
}

GitResult<void> RepoIndexDb::deleteRepo(std::int64_t id) {
    auto statement = db_.prepare("DELETE FROM repo WHERE id = ?1;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, id);
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return {};
}

GitResult<void> RepoIndexDb::saveProbe(const RepoProbe& probe) {
    auto statement = db_.prepare(
        "INSERT INTO repo_probe(repo_id, head_kind, head_ref, head_oid, upstream_ref, ahead, "
        "                       behind, dirty_files, stash_count, in_progress, probed_at, "
        "                       git_dir_mtime_ns, index_mtime_ns) "
        "VALUES(?1,?2,?3,?4,?5,?6,?7,?8,?9,?10,?11,?12,?13) "
        "ON CONFLICT(repo_id) DO UPDATE SET head_kind=?2, head_ref=?3, head_oid=?4, "
        "  upstream_ref=?5, ahead=?6, behind=?7, dirty_files=?8, stash_count=?9, "
        "  in_progress=?10, probed_at=?11, git_dir_mtime_ns=?12, index_mtime_ns=?13;");
    if (!statement) {
        return fail(std::move(statement).error());
    }

    statement->bind(1, probe.repoId);
    statement->bind(2, static_cast<std::int64_t>(probe.headKind));
    statement->bind(3, probe.headRef);
    if (probe.headOid.isNull()) {
        statement->bindNull(4);
    } else {
        statement->bind(4, probe.headOid.bytes(), probe.headOid.byteLength());
    }
    statement->bind(5, probe.upstreamRef);
    statement->bind(6, static_cast<std::int64_t>(probe.ahead));
    statement->bind(7, static_cast<std::int64_t>(probe.behind));
    statement->bind(8, static_cast<std::int64_t>(probe.dirtyFiles));
    statement->bind(9, static_cast<std::int64_t>(probe.stashCount));
    statement->bind(10, static_cast<std::int64_t>(probe.inProgressFlags));
    statement->bind(11, probe.probedAt != 0 ? probe.probedAt : nowSeconds());
    statement->bind(12, probe.gitDirMtimeNs);
    statement->bind(13, probe.indexMtimeNs);

    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return {};
}

GitResult<std::optional<RepoProbe>> RepoIndexDb::probe(std::int64_t repoId) const {
    auto statement = db_.prepare(
        "SELECT repo_id, head_kind, head_ref, head_oid, upstream_ref, ahead, behind, "
        "       dirty_files, stash_count, in_progress, probed_at, git_dir_mtime_ns, "
        "       index_mtime_ns FROM repo_probe WHERE repo_id = ?1;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, repoId);
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    if (!*stepped) {
        return std::optional<RepoProbe>{};
    }

    RepoProbe result;
    result.repoId = statement->columnInt(0);
    result.headKind = static_cast<int>(statement->columnInt(1));
    result.headRef = statement->columnText(2);
    const auto oidBytes = statement->columnBlob(3);
    if (oidBytes.size() == 20 || oidBytes.size() == 32) {
        std::string hex;
        static constexpr char kDigits[] = "0123456789abcdef";
        for (std::uint8_t byte : oidBytes) {
            hex.push_back(kDigits[byte >> 4]);
            hex.push_back(kDigits[byte & 0x0F]);
        }
        result.headOid = ObjectId::fromHex(hex);
    }
    result.upstreamRef = statement->columnText(4);
    result.ahead = static_cast<int>(statement->columnInt(5));
    result.behind = static_cast<int>(statement->columnInt(6));
    result.dirtyFiles = static_cast<int>(statement->columnInt(7));
    result.stashCount = static_cast<int>(statement->columnInt(8));
    result.inProgressFlags = static_cast<std::uint32_t>(statement->columnInt(9));
    result.probedAt = statement->columnInt(10);
    result.gitDirMtimeNs = statement->columnInt(11);
    result.indexMtimeNs = statement->columnInt(12);
    return std::optional<RepoProbe>(std::move(result));
}

GitResult<std::optional<DirSignature>> RepoIndexDb::dirSignature(std::int64_t baseFolderId,
                                                                 const std::string& dirPath) const {
    auto statement = db_.prepare(
        "SELECT base_folder_id, dir_path, mtime_ns, child_dirs, had_repo "
        "FROM dir_sig WHERE base_folder_id = ?1 AND dir_path = ?2;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, baseFolderId);
    statement->bind(2, dirPath);
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    if (!*stepped) {
        return std::optional<DirSignature>{};
    }

    DirSignature signature;
    signature.baseFolderId = statement->columnInt(0);
    signature.dirPath = statement->columnText(1);
    signature.mtimeNs = statement->columnInt(2);
    signature.childDirs = statement->columnInt(3);
    signature.hadRepo = statement->columnInt(4) != 0;
    return std::optional<DirSignature>(std::move(signature));
}

GitResult<void> RepoIndexDb::saveDirSignature(const DirSignature& signature) {
    auto statement = db_.prepare(
        "INSERT INTO dir_sig(base_folder_id, dir_path, mtime_ns, child_dirs, had_repo) "
        "VALUES(?1,?2,?3,?4,?5) "
        "ON CONFLICT(base_folder_id, dir_path) DO UPDATE SET "
        "  mtime_ns=?3, child_dirs=?4, had_repo=?5;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, signature.baseFolderId);
    statement->bind(2, signature.dirPath);
    statement->bind(3, signature.mtimeNs);
    statement->bind(4, signature.childDirs);
    statement->bind(5, static_cast<std::int64_t>(signature.hadRepo ? 1 : 0));
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return {};
}

GitResult<void> RepoIndexDb::clearDirSignatures(std::int64_t baseFolderId) {
    auto statement = db_.prepare("DELETE FROM dir_sig WHERE base_folder_id = ?1;");
    if (!statement) {
        return fail(std::move(statement).error());
    }
    statement->bind(1, baseFolderId);
    auto stepped = statement->step();
    if (!stepped) {
        return fail(std::move(stepped).error());
    }
    return {};
}

GitResult<std::vector<RepoRecord>> RepoIndexDb::search(const std::string& query,
                                                       std::size_t limit) const {
    const std::string sql = "SELECT " + std::string(kRepoColumns) +
                            " FROM repo WHERE missing_since IS NULL AND ("
                            "name LIKE ?1 ESCAPE '\\' COLLATE NOCASE OR "
                            "work_dir LIKE ?1 ESCAPE '\\' COLLATE NOCASE OR "
                            "git_dir LIKE ?1 ESCAPE '\\' COLLATE NOCASE) "
                            "ORDER BY name COLLATE NOCASE LIMIT ?2;";
    auto statement = db_.prepare(sql);
    if (!statement) {
        return fail(std::move(statement).error());
    }

    // Escape LIKE metacharacters so a query containing '%' or '_' searches for
    // those literal characters instead of matching everything.
    std::string escaped;
    escaped.reserve(query.size() + 2);
    for (char c : query) {
        if (c == '%' || c == '_' || c == '\\') {
            escaped.push_back('\\');
        }
        escaped.push_back(c);
    }
    const std::string pattern = "%" + escaped + "%";

    statement->bind(1, pattern);
    statement->bind(2, static_cast<std::int64_t>(limit));

    std::vector<RepoRecord> records;
    for (;;) {
        auto stepped = statement->step();
        if (!stepped) {
            return fail(std::move(stepped).error());
        }
        if (!*stepped) {
            break;
        }
        records.push_back(readRepoRow(*statement));
    }
    return records;
}

}  // namespace gbm
