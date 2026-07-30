#include "core/cache/Database.h"

#include "core/base/Logging.h"
#include "core/base/ThreadCheck.h"

#include <sqlite3.h>
#include <utility>

namespace gbm {

namespace {

GitError sqliteError(sqlite3* db, std::string message) {
    GitError error(GitError::Code::Database, std::move(message));
    if (db != nullptr) {
        error.detail = sqlite3_errmsg(db);
        error.exitCode = sqlite3_extended_errcode(db);
    }
    return error;
}

}  // namespace

Statement::~Statement() {
    if (statement_ != nullptr) {
        sqlite3_finalize(statement_);
    }
}

Statement::Statement(Statement&& other) noexcept : statement_(other.statement_), db_(other.db_) {
    other.statement_ = nullptr;
    other.db_ = nullptr;
}

Statement& Statement::operator=(Statement&& other) noexcept {
    if (this != &other) {
        if (statement_ != nullptr) {
            sqlite3_finalize(statement_);
        }
        statement_ = other.statement_;
        db_ = other.db_;
        other.statement_ = nullptr;
        other.db_ = nullptr;
    }
    return *this;
}

void Statement::bind(int index, std::int64_t value) {
    sqlite3_bind_int64(statement_, index, value);
}

void Statement::bind(int index, std::string_view value) {
    // SQLITE_TRANSIENT: SQLite copies the text, so a temporary string_view is safe.
    sqlite3_bind_text(
        statement_, index, value.data(), static_cast<int>(value.size()), SQLITE_TRANSIENT);
}

void Statement::bind(int index, const void* data, std::size_t size) {
    sqlite3_bind_blob(statement_, index, data, static_cast<int>(size), SQLITE_TRANSIENT);
}

void Statement::bindNull(int index) {
    sqlite3_bind_null(statement_, index);
}

GitResult<bool> Statement::step() {
    const int rc = sqlite3_step(statement_);
    if (rc == SQLITE_ROW) {
        return true;
    }
    if (rc == SQLITE_DONE) {
        return false;
    }
    return fail(sqliteError(db_, "Database query failed"));
}

std::int64_t Statement::columnInt(int index) const {
    return sqlite3_column_int64(statement_, index);
}

std::string Statement::columnText(int index) const {
    const auto* text = reinterpret_cast<const char*>(sqlite3_column_text(statement_, index));
    if (text == nullptr) {
        return {};
    }
    return std::string(text, static_cast<std::size_t>(sqlite3_column_bytes(statement_, index)));
}

std::vector<std::uint8_t> Statement::columnBlob(int index) const {
    const auto* data = static_cast<const std::uint8_t*>(sqlite3_column_blob(statement_, index));
    const int size = sqlite3_column_bytes(statement_, index);
    if (data == nullptr || size <= 0) {
        return {};
    }
    return std::vector<std::uint8_t>(data, data + size);
}

bool Statement::columnIsNull(int index) const {
    return sqlite3_column_type(statement_, index) == SQLITE_NULL;
}

void Statement::reset() {
    sqlite3_reset(statement_);
    sqlite3_clear_bindings(statement_);
}

Database::~Database() {
    close();
}

GitResult<void> Database::open(const std::filesystem::path& path, bool readOnly) {
    // Deliberately *not* guarded by GBM_ASSERT_NOT_UI_THREAD().
    //
    // Reading the local cache on the UI thread is the design, not a violation: the
    // window paints the repository list straight from SQLite before any scanning
    // begins, which is what makes startup fast. A few local reads costing well under
    // 100 ms for hundreds of repositories is precisely the trade the cache exists to
    // make. The assertion belongs on process spawning and directory walks, which are
    // orders of magnitude more expensive and genuinely unbounded.
    close();

    std::error_code ec;
    if (!readOnly && path.has_parent_path()) {
        std::filesystem::create_directories(path.parent_path(), ec);
    }

    const int flags =
        readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE);
    // The path is converted through u8string so non-ASCII directories work on
    // Windows, where the narrow API would otherwise mangle them.
    const std::string utf8Path =
        path.u8string().empty()
            ? path.string()
            : std::string(reinterpret_cast<const char*>(path.u8string().c_str()));

    if (sqlite3_open_v2(utf8Path.c_str(), &db_, flags, nullptr) != SQLITE_OK) {
        GitError error = sqliteError(db_, "Could not open the repository cache");
        close();
        return fail(std::move(error));
    }
    return applyPragmas(readOnly);
}

GitResult<void> Database::openInMemory() {
    close();
    if (sqlite3_open(":memory:", &db_) != SQLITE_OK) {
        GitError error = sqliteError(db_, "Could not open an in-memory database");
        close();
        return fail(std::move(error));
    }
    return applyPragmas(false);
}

GitResult<void> Database::applyPragmas(bool readOnly) {
    // busy_timeout matters even with WAL: schema changes and checkpoints still
    // take the write lock briefly, and a scan writing while the UI reads should
    // wait rather than fail.
    if (auto result = execute("PRAGMA busy_timeout=5000;"); !result) {
        return result;
    }
    if (auto result = execute("PRAGMA foreign_keys=ON;"); !result) {
        return result;
    }
    if (!readOnly) {
        // WAL: readers never block the writer and vice versa. NORMAL sync is the
        // right trade here — this is a rebuildable cache, not user data, so a
        // power-loss torn write costs one rescan, not information.
        if (auto result = execute("PRAGMA journal_mode=WAL;"); !result) {
            return result;
        }
        if (auto result = execute("PRAGMA synchronous=NORMAL;"); !result) {
            return result;
        }
    }
    return {};
}

void Database::close() {
    if (db_ != nullptr) {
        sqlite3_close(db_);
        db_ = nullptr;
    }
}

GitResult<void> Database::execute(std::string_view sql) {
    if (db_ == nullptr) {
        return fail(GitError::Code::Database, "The database is not open");
    }
    char* errorText = nullptr;
    const std::string statement(sql);
    if (sqlite3_exec(db_, statement.c_str(), nullptr, nullptr, &errorText) != SQLITE_OK) {
        GitError error(GitError::Code::Database, "Database statement failed");
        if (errorText != nullptr) {
            error.detail = errorText;
            sqlite3_free(errorText);
        }
        return fail(std::move(error));
    }
    return {};
}

GitResult<Statement> Database::prepare(std::string_view sql) {
    if (db_ == nullptr) {
        return fail(GitError::Code::Database, "The database is not open");
    }
    sqlite3_stmt* prepared = nullptr;
    if (sqlite3_prepare_v2(db_, sql.data(), static_cast<int>(sql.size()), &prepared, nullptr) !=
        SQLITE_OK) {
        return fail(sqliteError(db_, "Could not prepare a database statement"));
    }
    return Statement(prepared, db_);
}

GitResult<void> Database::transaction(const std::function<GitResult<void>()>& body) {
    if (auto begin = execute("BEGIN IMMEDIATE;"); !begin) {
        return begin;
    }

    GitResult<void> result;
    try {
        result = body();
    } catch (...) {
        // Never leave a transaction open: the next writer would block for the
        // busy timeout and then fail, turning one bug into a broken cache.
        (void)execute("ROLLBACK;");
        throw;
    }

    if (!result) {
        (void)execute("ROLLBACK;");
        return result;
    }
    return execute("COMMIT;");
}

std::int64_t Database::lastInsertRowId() const {
    return db_ == nullptr ? 0 : sqlite3_last_insert_rowid(db_);
}

std::string Database::lastError() const {
    return db_ == nullptr ? std::string() : std::string(sqlite3_errmsg(db_));
}

}  // namespace gbm
