#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"
#include "core/git/UnifiedDiffParser.h"

#include <cstdint>
#include <filesystem>
#include <memory>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace gbm {

/// Which side of a three-way conflict a file is stuck on, taken from the index's
/// stage bits (`git status`'s XY pair for an unmerged entry). Named for the
/// question the user actually has -- "did I delete this or did they?" -- rather
/// than for the stage numbers, which mean nothing without a lookup table.
enum class ConflictKind : std::uint8_t {
    None,
    BothAdded,      ///< AA: both sides added the same path.
    BothModified,   ///< UU: both sides modified it.
    BothDeleted,    ///< DD: both sides deleted it (present only via history).
    AddedByUs,      ///< AU: we added it, they didn't touch it.
    DeletedByUs,    ///< DU: we deleted it, they modified it.
    AddedByThem,    ///< UA: they added it, we didn't touch it.
    DeletedByThem,  ///< UD: they deleted it, we modified it.
};

/// One path's state in the working copy, as reported by `git status`.
///
/// `indexStatus` and `worktreeStatus` are independent: a file can be modified
/// relative to HEAD *and* have further unstaged edits on top, which is exactly
/// the case a stage-by-hunk UI has to show as two separate diffs.
struct WorkingCopyEntry {
    std::string path;
    std::string oldPath;  ///< Set for renames and copies; empty otherwise.

    bool untracked = false;

    /// True when the index differs from HEAD for this path (something to
    /// unstage / commit).
    bool staged = false;
    FileChangeKind indexStatus = FileChangeKind::Modified;  ///< Valid only when staged.

    /// True when the work tree differs from the index for this path (something
    /// to stage).
    bool hasUnstagedChange = false;
    FileChangeKind worktreeStatus =
        FileChangeKind::Modified;  ///< Valid only when hasUnstagedChange.

    /// Line counts for each of the two sides, from `git diff --numstat` and
    /// `git diff --cached --numstat`. Deliberately **not** named `addedLines`:
    /// `DiffFile` and `ChangedFile` already both serialize a field by that
    /// name, and a third would make any mutation test anchored on the field
    /// name match three serializers instead of one.
    ///
    /// Zero means "no measurement", never "measured zero". numstat prints `-`
    /// for a binary blob, a mode-only change touches no lines, and an
    /// untracked file over the byte cap is skipped -- all three land here as
    /// 0, and the UI draws no badge for 0 rather than claiming `+0`.
    ///
    /// For an untracked file `git diff` reports nothing at all (the path is in
    /// neither the index nor HEAD), so `unstagedAdded` is the file's own line
    /// count, read from disk, and `unstagedRemoved` is always 0.
    std::uint32_t unstagedAdded = 0;
    std::uint32_t unstagedRemoved = 0;
    std::uint32_t stagedAdded = 0;
    std::uint32_t stagedRemoved = 0;

    ConflictKind conflict = ConflictKind::None;

    /// Blob object ids for each side of a conflict, valid only when
    /// `isConflicted()`. Empty when that stage does not exist for this path --
    /// e.g. `theirsBlob` is empty for AddedByUs, `ancestorBlob` is empty for
    /// BothAdded. Populated from `git status`'s stage hashes directly, so
    /// viewing a conflicted file's three sides never needs a second `git`
    /// invocation to look them up.
    std::string ancestorBlob;  ///< Stage 1: the merge base.
    std::string oursBlob;      ///< Stage 2: HEAD's side.
    std::string theirsBlob;    ///< Stage 3: the incoming side.

    int similarity = 0;  ///< Rename/copy score, 0-100.
    bool isSubmodule = false;

    bool isConflicted() const noexcept { return conflict != ConflictKind::None; }
};

/// A snapshot of the working copy: everything a status panel and a staging UI
/// need, from one `git status` call.
struct WorkingCopyStatus {
    std::vector<WorkingCopyEntry> entries;

    bool isClean() const noexcept { return entries.empty(); }

    std::vector<const WorkingCopyEntry*> staged() const;
    std::vector<const WorkingCopyEntry*> unstaged() const;
    std::vector<const WorkingCopyEntry*> untracked() const;
    std::vector<const WorkingCopyEntry*> conflicted() const;
};

using WorkingCopyStatusPtr = std::shared_ptr<const WorkingCopyStatus>;

/// How many bytes of an untracked file are worth reading just to count its
/// lines. `git status --untracked-files=all` enumerates every file in an
/// unbuilt output directory, so an uncapped read turns one status refresh into
/// however much disk that directory happens to hold. Over the cap the file
/// gets no count at all rather than a partial one -- a partial count is a
/// wrong number, not a missing one, and the UI cannot tell the two apart.
inline constexpr std::uintmax_t kUntrackedLineCountByteCap = 1u << 20;  // 1 MiB

/// Remembers what each untracked file's line count was, so a refresh that
/// changes nothing about a file does not read that file again.
///
/// **Key: path + size + mtime**, and all three are load-bearing. `path` alone
/// cannot tell one refresh's `notes.txt` from the next one's; `size` alone
/// misses an edit that replaces a line with another of the same length; `mtime`
/// alone misses a same-tick rewrite, which is why both stat fields are compared
/// rather than either. The stat is not an extra syscall on the common path --
/// [countUntrackedLines] already had to ask for the size to enforce
/// [kUntrackedLineCountByteCap].
///
/// **Invalidated by**: nothing external. There is no event to subscribe to,
/// because the work tree changes without git's involvement -- an editor saving
/// a file emits no `GBM_EVENT_*`. The key *is* the invalidation: a changed file
/// has a different size or a newer mtime, so its next lookup misses. Entries
/// for files that stopped being untracked (staged, deleted, or gitignored) are
/// swept by [retainOnly] on every pass, which is what bounds the map to the
/// current untracked set rather than to every file ever seen.
///
/// **Symptom if invalidation were missed**: the unstaged column would keep
/// showing the line count a file had before it was edited -- a *wrong* number
/// rather than a missing one, the exact failure the byte cap and the binary
/// test both refuse elsewhere in this file. That is why [store] declines a file
/// whose mtime is not strictly older than the moment the pass began: within one
/// filesystem timestamp tick, an edit is indistinguishable from no edit, and
/// caching there would make the wrong number *stick* until the next edit rather
/// than clear on the next refresh. It is git's own "racily clean" rule, applied
/// to the one thing here that stats a file.
class UntrackedLineCountCache {
public:
    /// The pair a file is remembered under.
    struct Stat {
        std::uintmax_t size = 0;
        std::filesystem::file_time_type modified{};

        bool operator==(const Stat& other) const noexcept {
            return size == other.size && modified == other.modified;
        }
    };

    /// The remembered count for [path], or nothing when the file was never
    /// read or has changed since it was.
    std::optional<std::uint32_t> lookup(const std::string& path, const Stat& stat);

    /// Remembers that [path] had [lines] lines when it looked like [stat].
    ///
    /// [passStartedAt] is the moment the enclosing pass began; a file whose
    /// mtime is not strictly older is left uncached -- see the class comment.
    void store(const std::string& path,
               const Stat& stat,
               std::uint32_t lines,
               std::filesystem::file_time_type passStartedAt);

    /// Drops every entry whose path is not in [live].
    void retainOnly(const std::unordered_set<std::string>& live);

    /// How many lookups were served from the map, for tests. A cache with no
    /// way to observe a hit cannot be shown to be doing anything.
    std::size_t hits() const;

    /// How many lookups had to read the file.
    std::size_t misses() const;

    /// How many files are currently remembered.
    std::size_t size() const;

private:
    struct Entry {
        Stat stat;
        std::uint32_t lines = 0;
    };

    mutable std::mutex mutex_;
    std::unordered_map<std::string, Entry> entries_;
    std::size_t hits_ = 0;
    std::size_t misses_ = 0;
};

/// Reads working-copy status via `git status --porcelain=v2`, plus the two
/// `--numstat` passes that carry the per-file line counts spec page 03's
/// `+34 -12` badges need.
///
/// **Three git invocations, not one.** `git status` reports no line counts at
/// all, and git's diff output-format field is a single slot -- `--numstat`
/// cannot be combined with a status read, so the counts come from
/// `git diff --numstat` (work tree vs index) and `git diff --cached --numstat`
/// (index vs HEAD), joined onto the status entries by path. Untracked files
/// are in neither of those diffs, so their line count is read from the file
/// itself, capped by [kUntrackedLineCountByteCap].
///
/// **The three git invocations are deliberately uncached**, like
/// DiffService::workingTreeDiff: the work tree changes under us on every
/// keystroke and every build, and the only honest cache key would have to
/// include every file's mtime and size -- which is a bigger stat sweep than
/// the thing it would save. git itself still does most of the work cheaply --
/// `core.fsmonitor` (>= 2.37, see GitCapabilities::fsMonitor) lets git skip
/// the lstat() of every file in a large work tree and answer from its daemon's
/// change list, which this class gets for free by not passing anything that
/// would defeat it.
///
/// **The untracked file reads are cached**, by [UntrackedLineCountCache], and
/// that is not a contradiction: those reads already stat each file to enforce
/// [kUntrackedLineCountByteCap], so the honest key the git passes cannot
/// afford is one this pass has already paid for. What it buys is the
/// difference between reading up to 1 MiB per untracked file on every refresh
/// and reading it once -- and in a tree with an unbuilt output directory,
/// every refresh is when the user is typing.
class WorkingCopyStatusReader {
public:
    WorkingCopyStatusReader(IProcessRunner& runner, RepoPaths paths);

    GitResult<WorkingCopyStatusPtr> read(CancellationToken token);

    /// The untracked-line-count cache this reader reuses across reads.
    ///
    /// Exposed so a test can assert that an unchanged file is *not* read again
    /// and a changed one *is*. A cache whose only observable effect is speed
    /// cannot be told apart from no cache at all.
    const UntrackedLineCountCache& untrackedLineCounts() const noexcept {
        return untrackedLineCounts_;
    }

private:
    IProcessRunner& runner_;
    RepoPaths paths_;

    /// Mutable across `read()` calls, which run on sharedReadPool()'s 2-6
    /// threads and can therefore overlap; the cache locks internally.
    UntrackedLineCountCache untrackedLineCounts_;
};

}  // namespace gbm
