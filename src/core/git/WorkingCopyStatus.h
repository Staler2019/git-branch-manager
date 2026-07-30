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
    FileChangeKind worktreeStatus = FileChangeKind::Modified;  ///< Valid only when hasUnstagedChange.

    ConflictKind conflict = ConflictKind::None;

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

/// Reads working-copy status via `git status --porcelain=v2`.
///
/// Deliberately uncached, like DiffService::workingTreeDiff: the work tree
/// changes under us on every keystroke and every build, and the only honest
/// cache key would have to include every file's mtime and size. Speed instead
/// comes from git itself -- `core.fsmonitor` (>= 2.37, see
/// GitCapabilities::fsMonitor) lets git skip the lstat() of every file in a
/// large work tree and answer from its daemon's change list, which this class
/// gets for free by not passing anything that would defeat it.
class WorkingCopyStatusReader {
public:
    WorkingCopyStatusReader(IProcessRunner& runner, RepoPaths paths);

    GitResult<WorkingCopyStatusPtr> read(CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

}  // namespace gbm
