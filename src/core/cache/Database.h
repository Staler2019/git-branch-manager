#pragma once

#include "core/base/Error.h"

#include <cstdint>
#include <filesystem>
#include <functional>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

struct sqlite3;
struct sqlite3_stmt;

namespace gbm {

/// Thin RAII wrapper over a prepared statement.
class Statement {
public:
    Statement() = default;
    ~Statement();

    Statement(Statement&& other) noexcept;
    Statement& operator=(Statement&& other) noexcept;

    Statement(const Statement&) = delete;
    Statement& operator=(const Statement&) = delete;

    // 1-based binding, matching SQLite's own convention.
    void bind(int index, std::int64_t value);
    void bind(int index, std::string_view value);
    void bind(int index, const void* data, std::size_t size);
    void bindNull(int index);

    /// True when a row was produced; false at the end of the result set.
    GitResult<bool> step();

    std::int64_t columnInt(int index) const;
    std::string columnText(int index) const;
    std::vector<std::uint8_t> columnBlob(int index) const;
    bool columnIsNull(int index) const;

    void reset();

    sqlite3_stmt* raw() const { return statement_; }

private:
    friend class Database;

    explicit Statement(sqlite3_stmt* statement, sqlite3* db) : statement_(statement), db_(db) {}

    sqlite3_stmt* statement_ = nullptr;
    sqlite3* db_ = nullptr;
};

/// A SQLite connection.
///
/// The cache is opened in WAL mode with exactly one writer thread and per-thread
/// readers. That combination is what lets a background scan keep inserting while
/// the UI reads the repository list without ever blocking on a lock.
class Database {
public:
    Database() = default;
    ~Database();

    Database(const Database&) = delete;
    Database& operator=(const Database&) = delete;

    /// `readOnly` connections are used by the UI-facing query paths.
    GitResult<void> open(const std::filesystem::path& path, bool readOnly = false);

    /// An in-memory database, for tests.
    GitResult<void> openInMemory();

    void close();

    bool isOpen() const { return db_ != nullptr; }

    GitResult<void> execute(std::string_view sql);

    GitResult<Statement> prepare(std::string_view sql);

    /// Runs `body` inside a transaction, rolling back if it fails or throws. The
    /// scanner commits one transaction per batch rather than per row, which is the
    /// difference between a few seconds and a few minutes for 100k inserts.
    GitResult<void> transaction(const std::function<GitResult<void>()>& body);

    std::int64_t lastInsertRowId() const;

    std::string lastError() const;

    sqlite3* raw() const { return db_; }

private:
    GitResult<void> applyPragmas(bool readOnly);

    sqlite3* db_ = nullptr;
};

}  // namespace gbm
