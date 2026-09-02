#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/OperationRunner.h"
#include "core/git/RepoPaths.h"

#include <cstdint>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace gbm {

/// Whether `pendingChanges` holds an answer, and if not, why not.
///
/// A separate field rather than a sentinel value inside the count, because
/// **0 has to mean "measured, and genuinely clean"** -- that is the answer
/// the user sees most often and most needs to be able to trust.
///
/// This is deliberately the inverse of `WorkingCopyEntry`'s four line-count
/// fields, where 0 means "not measured". There, a path with no matching
/// numstat record and a path with a genuine zero are indistinguishable by
/// construction, so 0 had to absorb both meanings. Here the status command
/// either ran or it did not, and "did not" has somewhere else to live. Both
/// obey the same principle: absent is not zero.
enum class WorktreePendingCountState {
    /// No count has been requested for this worktree yet. This is what a
    /// plain `WorktreeStore::list()` produces -- the per-worktree status
    /// pass is a separate, panel-driven request.
    Unmeasured,
    /// `pendingChanges` is a real count. Including when it is 0.
    Measured,
    /// The command could not be run at all: a bare worktree has no work tree
    /// to compare against, and a prunable one's directory is gone. Not a
    /// guess about what git *would* have said -- knowing the command cannot
    /// run, which is the same carve-out `Session::refreshLfs()` uses when
    /// git-lfs is not on PATH.
    NotApplicable,
    /// The command ran and failed. A cached answer like any other, so the
    /// caller does not spin re-asking.
    Failed,
};

struct WorktreeInfo {
    std::filesystem::path path;
    std::string headOid;  ///< Empty for an unborn HEAD.
    std::string branch;   ///< Short branch name; empty when detached.
    /// **The worktree this RepoPaths itself refers to** -- i.e. the one the
    /// session is open on, which is "current", *not* "primary". A session
    /// opened on a linked worktree sets this on that linked worktree and not
    /// on the repository's main one.
    bool isMain = false;
    bool isBare = false;
    bool isDetached = false;
    bool isLocked = false;
    std::string lockReason;
    bool isPrunable = false;
    std::string prunableReason;

    /// Uncommitted changes in this worktree. Meaningful only when
    /// `pendingCountState == Measured`; see that enum for why the two are
    /// separate fields.
    std::uint32_t pendingChanges = 0;
    WorktreePendingCountState pendingCountState = WorktreePendingCountState::Unmeasured;

    /// Unix time of the first entry in this worktree's own
    /// `<commonDir>/worktrees/<name>/logs/HEAD`, which git writes at
    /// `git worktree add`. **0 means git recorded nothing**, not the epoch.
    ///
    /// Four cases where it is legitimately 0, all of them absent rather than
    /// wrong: the main/current worktree has no `worktrees/<name>/` directory
    /// at all; `core.logAllRefUpdates` can be off; the admin directory can
    /// predate the reflog being enabled; and see `readCreatedAtUnix()` for
    /// the one case that is genuinely lossy (reflog expiry).
    std::int64_t createdAtUnix = 0;
};

/// Fills in `pendingChanges` / `pendingCountState` for every worktree in
/// `worktrees`, one `git status` per eligible worktree.
///
/// **Deliberately not part of `WorktreeStore::list()`.** That is what a plain
/// refresh calls, and every zero-argument `refresh*` on the session is a
/// member of the focus-regain/F5 refresh set -- folding N git processes into
/// it would make everyone pay for a panel they may not have open. This runs
/// only when something asks for it.
///
/// Skips bare and prunable worktrees **without running anything**: a bare
/// worktree has no work tree (`fatal: this operation must be run in a work
/// tree`) and a prunable one's directory is gone, so in both cases the
/// command cannot start. That is knowing the command cannot run, not guessing
/// what it would have answered -- the same carve-out `Session::refreshLfs()`
/// makes when git-lfs is absent from PATH.
///
/// Serial rather than fanned out: N is small, and N concurrent git processes
/// on the shared read pool is a cost nobody asked for.
void attachPendingCounts(IProcessRunner& runner,
                         std::vector<WorktreeInfo>& worktrees,
                         CancellationToken token);

/// Fills in `createdAtUnix` for every worktree that has an administrative
/// directory under `<commonDir>/worktrees/`, from the first entry of that
/// directory's own `logs/HEAD` -- the reflog line `git worktree add` writes as
/// it creates the worktree. Measured against git 2.55.0: with the tip commit
/// made 5s before the add, the line carried the *add* time.
///
/// Cheap enough to live in `WorktreeStore::list()` rather than behind a
/// request: one directory scan plus one small read per worktree, no process
/// spawned and the work tree never touched. That is the whole difference from
/// `attachPendingCounts` above.
///
/// The administrative directory is found by **indexing every
/// `worktrees/*/gitdir` file**, not by assuming the directory is named after
/// the worktree's last path component. `git worktree move` rewrites `gitdir`
/// and leaves the directory's original name in place, so a worktree living at
/// `.../moved` is still administered from `worktrees/linked/`. The index is
/// also what lets a *prunable* worktree be answered for: its path is gone and
/// its `.git` pointer with it, and the administrative directory is precisely
/// what survives -- that is what prune means.
///
/// **Four things this cannot know. None of them is faked; all report absent.**
///   1. The main/current worktree has no `worktrees/<name>/` directory at all.
///      Its own `logs/HEAD` starts at this *repository's* first checkout,
///      which is a different fact wearing the same label.
///   2. `core.logAllRefUpdates` can be off (bare repositories default to off),
///      so there may be no `logs/HEAD` to read.
///   3. The administrative directory can predate the reflog being enabled.
///   4. **`git gc` expires per-worktree HEAD reflogs (~90 days by default),
///      and after that the first *surviving* entry impersonates the creation
///      time.** It looks reasonable, it is wrong, and nothing inside the file
///      can detect it. This is the one caveat that becomes a silent lie if it
///      goes unwritten.
///
/// Deliberately **no mtime fallback.** `gitdir`'s `last_write_time` would be a
/// second source for the same fact that can silently disagree with the first,
/// which is [CULT-single-source-of-truth]'s named failure shape. Absent beats
/// approximately right, and the UI draws the absence rather than a number.
void attachCreatedAt(const RepoPaths& paths, std::vector<WorktreeInfo>& worktrees);

/// Reads `git worktree list --porcelain`. Read-only, like RefStore.
class WorktreeStore {
public:
    WorktreeStore(IProcessRunner& runner, RepoPaths paths);

    GitResult<std::vector<WorktreeInfo>> list(CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

struct AddWorktreeRequest {
    std::filesystem::path path;
    std::string branch;  ///< Existing branch or commit-ish to check out.
    bool createBranch = false;
    std::string newBranchName;
    bool detach = false;
    /// `--force`: lets a branch already checked out elsewhere be checked out
    /// again. Only ever set after the user is told exactly what that means.
    bool force = false;
};

struct RemoveWorktreeRequest {
    std::filesystem::path path;
    bool force = false;  ///< Overrides a dirty working tree or a lock.
};

struct PruneWorktreesRequest {
    bool dryRun = false;
};

struct LockWorktreeRequest {
    std::filesystem::path path;
    std::string reason;
};

struct UnlockWorktreeRequest {
    std::filesystem::path path;
};

struct MoveWorktreeRequest {
    std::filesystem::path from;
    std::filesystem::path to;
};

/// `git worktree add`. Never killed mid-flight, for the same reason a checkout
/// of a large tree is not: an interrupted checkout leaves an inconsistent
/// index behind.
std::unique_ptr<Operation> makeAddWorktreeOperation(AddWorktreeRequest request);

std::unique_ptr<Operation> makeRemoveWorktreeOperation(RemoveWorktreeRequest request);

/// `git worktree prune`. Only ever removes administrative metadata for
/// worktrees whose directory is already gone -- it never touches a directory
/// that still exists.
std::unique_ptr<Operation> makePruneWorktreesOperation(PruneWorktreesRequest request);

std::unique_ptr<Operation> makeLockWorktreeOperation(LockWorktreeRequest request);
std::unique_ptr<Operation> makeUnlockWorktreeOperation(UnlockWorktreeRequest request);
std::unique_ptr<Operation> makeMoveWorktreeOperation(MoveWorktreeRequest request);

}  // namespace gbm
