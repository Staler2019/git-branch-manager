#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/base/ObjectId.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"
#include "core/git/UnifiedDiffParser.h"

#include <cstdint>
#include <list>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

namespace gbm {

/// One entry in a commit's changed-file list, from `diff-tree --raw`. Cheap: no
/// content is read, so clicking through commits stays instant.
struct ChangedFile {
    std::string path;
    std::string oldPath;  ///< Set for renames and copies.
    FileChangeKind kind = FileChangeKind::Modified;
    std::string oldMode;
    std::string newMode;
    std::string oldBlob;
    std::string newBlob;
    int similarity = 0;
};

struct DiffOptions {
    std::uint32_t contextLines = 3;
    bool ignoreWhitespace = false;
    bool ignoreEolOnly = false;  ///< Hides CRLF-only noise, common on Windows.
    bool detectRenames = true;
    bool firstParentOnly = true;  ///< For merges: diff against the first parent.

    /// Rename detection is quadratic in changed paths; above this many it is
    /// switched off so a sweeping refactor commit still opens.
    std::uint32_t renameDetectionLimit = 2000;

    std::uint64_t hash() const;
};

/// Bounded-by-bytes LRU. Sizing by entry count is the wrong knob here: one
/// 2 MB diff and ten thousand three-line diffs are not interchangeable.
template <class Key, class Value, class Hasher = std::hash<Key>>
class LruByBytes {
public:
    explicit LruByBytes(std::size_t budgetBytes) : budget_(budgetBytes) {}

    std::shared_ptr<const Value> get(const Key& key) {
        std::lock_guard<std::mutex> lock(mutex_);
        const auto it = map_.find(key);
        if (it == map_.end()) {
            return nullptr;
        }
        order_.splice(order_.begin(), order_, it->second.position);
        return it->second.value;
    }

    void put(const Key& key, std::shared_ptr<const Value> value, std::size_t bytes) {
        std::lock_guard<std::mutex> lock(mutex_);
        if (const auto existing = map_.find(key); existing != map_.end()) {
            used_ -= existing->second.bytes;
            order_.erase(existing->second.position);
            map_.erase(existing);
        }
        order_.push_front(key);
        map_.emplace(key, Entry{std::move(value), bytes, order_.begin()});
        used_ += bytes;

        while (used_ > budget_ && !order_.empty()) {
            const Key& oldest = order_.back();
            if (const auto victim = map_.find(oldest); victim != map_.end()) {
                used_ -= victim->second.bytes;
                map_.erase(victim);
            }
            order_.pop_back();
        }
    }

    void clear() {
        std::lock_guard<std::mutex> lock(mutex_);
        map_.clear();
        order_.clear();
        used_ = 0;
    }

    std::size_t usedBytes() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return used_;
    }

    std::size_t size() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return map_.size();
    }

private:
    struct Entry {
        std::shared_ptr<const Value> value;
        std::size_t bytes = 0;
        typename std::list<Key>::iterator position;
    };

    mutable std::mutex mutex_;
    std::size_t budget_;
    std::size_t used_ = 0;
    std::list<Key> order_;
    std::unordered_map<Key, Entry, Hasher> map_;
};

/// Produces diffs by running `git diff`/`git diff-tree` and parsing the output.
///
/// Two caches make clicking through history feel instant: the changed-file list
/// per commit, and the parsed diff per blob pair. Neither is ever persisted to
/// disk — a stale on-disk cache of object data would produce *wrong* diffs, and
/// wrong is worse than slow.
class DiffService {
public:
    /// Byte budget for parsed diffs.
    static constexpr std::size_t kDiffCacheBytes = 48u * 1024u * 1024u;
    /// Changed-file lists are small; this many covers a long browsing session.
    static constexpr std::size_t kFileListCacheEntries = 512;

    DiffService(IProcessRunner& runner, RepoPaths paths);

    using ChangedFilesPtr = std::shared_ptr<const std::vector<ChangedFile>>;
    using ParsedDiffPtr = std::shared_ptr<const ParsedDiff>;

    /// Changed files for a commit. For a merge, defaults to the first-parent diff
    /// (what a reviewer usually wants) with the combined diff available on demand.
    GitResult<ChangedFilesPtr> changedFiles(const ObjectId& commit,
                                            const DiffOptions& options,
                                            CancellationToken token);

    /// Diff of one file within a commit.
    GitResult<ParsedDiffPtr> commitFileDiff(const ObjectId& commit,
                                            const std::string& path,
                                            const DiffOptions& options,
                                            CancellationToken token);

    /// Whole-commit diff. Subject to the parser's size cap.
    GitResult<ParsedDiffPtr> commitDiff(const ObjectId& commit,
                                        const DiffOptions& options,
                                        CancellationToken token);

    /// Unstaged (work tree vs index) or staged (index vs HEAD) changes.
    GitResult<ParsedDiffPtr> workingTreeDiff(bool staged,
                                             const std::vector<std::string>& paths,
                                             const DiffOptions& options,
                                             CancellationToken token);

    void clearCaches();

    std::size_t diffCacheBytes() const { return diffCache_.usedBytes(); }

private:
    std::vector<std::string> diffFlags(const DiffOptions& options) const;

    IProcessRunner& runner_;
    RepoPaths paths_;

    LruByBytes<std::string, ParsedDiff> diffCache_{kDiffCacheBytes};
    LruByBytes<std::string, std::vector<ChangedFile>> fileListCache_{kFileListCacheEntries * 4096};
};

}  // namespace gbm
