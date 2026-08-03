#pragma once

#include "core/git/OperationRunner.h"

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
