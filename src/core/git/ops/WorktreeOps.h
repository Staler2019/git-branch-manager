#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/OperationRunner.h"
#include "core/git/RepoPaths.h"

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace gbm {

struct WorktreeInfo {
    std::filesystem::path path;
    std::string headOid;  ///< Empty for an unborn HEAD.
    std::string branch;   ///< Short branch name; empty when detached.
    bool isMain = false;  ///< The worktree this RepoPaths itself refers to.
    bool isBare = false;
    bool isDetached = false;
    bool isLocked = false;
    std::string lockReason;
    bool isPrunable = false;
    std::string prunableReason;
};

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
