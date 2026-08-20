#pragma once

#include "core/git/OperationRunner.h"

#include <filesystem>
#include <memory>
#include <string>
#include <vector>

namespace gbm {

struct CreateBranchRequest {
    std::string name;
    std::string startPoint;  ///< Empty means HEAD.
    bool checkoutAfter = false;
    bool setUpstream = false;
    std::string upstream;
};

struct RenameBranchRequest {
    std::string from;
    std::string to;
    bool force = false;
    /// Carries the rename through to `remoteName` after the local rename
    /// succeeds: pushes the branch under its new name (with `-u`, so the
    /// renamed branch tracks it), then deletes the old branch on the remote.
    /// git has no atomic remote rename, so this really is push-then-delete,
    /// and everyone else's remote-tracking ref for the old name goes `gone`.
    /// Push comes first deliberately -- reversing the two would leave the
    /// branch unpublished if the second step failed.
    ///
    /// When this is false and the branch had an upstream, the upstream is
    /// unset instead: `git branch -m` *keeps* the tracking config, which
    /// would otherwise leave the renamed branch still tracking the old
    /// remote branch. That is not configurable -- it is what "rename
    /// locally only" means.
    bool renameRemote = false;
    std::string remoteName;
    /// Set by the app layer to a directory made with askpass::makeRequestDir();
    /// only the `renameRemote` steps need it, since they are the only ones
    /// that talk to a remote.
    std::filesystem::path askpassDir;
};

struct DeleteBranchRequest {
    /// One or more branch names to delete in a single `git branch`/`git push
    /// --delete` invocation -- git accepts multiple names to either command,
    /// so a multi-select delete is one operation, not N.
    std::vector<std::string> names;
    /// Deletes even when the branch is not merged. Requires an explicit user
    /// decision, because the commits become reachable only through the reflog.
    bool force = false;
    bool isRemote = false;
    std::string remoteName;
};

std::unique_ptr<Operation> makeCreateBranchOperation(CreateBranchRequest request);
std::unique_ptr<Operation> makeRenameBranchOperation(RenameBranchRequest request);
std::unique_ptr<Operation> makeDeleteBranchOperation(DeleteBranchRequest request);

}  // namespace gbm
