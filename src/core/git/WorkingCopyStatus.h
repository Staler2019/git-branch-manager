#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/RepoPaths.h"
#include "core/git/UnifiedDiffParser.h"

#include <cstdint>
#include <memory>
#include <string>
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
/// Deliberately uncached, like DiffService::workingTreeDiff: the work tree
/// changes under us on every keystroke and every build, and the only honest
/// cache key would have to include every file's mtime and size. git itself
/// still does most of the work cheaply -- `core.fsmonitor` (>= 2.37, see
/// GitCapabilities::fsMonitor) lets git skip the lstat() of every file in a
/// large work tree and answer from its daemon's change list, which this class
/// gets for free by not passing anything that would defeat it -- but the
/// per-refresh cost is now three processes and, in a tree with many untracked
/// files, one bounded read each. The byte cap is what stops an unbuilt output
/// directory from turning one refresh into hundreds of megabytes of reads.
class WorkingCopyStatusReader {
public:
    WorkingCopyStatusReader(IProcessRunner& runner, RepoPaths paths);

    GitResult<WorkingCopyStatusPtr> read(CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

}  // namespace gbm
