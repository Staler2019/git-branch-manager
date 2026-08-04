#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/IProcessRunner.h"
#include "core/git/OperationRunner.h"
#include "core/git/RepoPaths.h"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace gbm {

struct StashEntry {
    int index = 0;  ///< Position in `stash@{N}`; 0 is the most recent.
    std::string message;
    std::string oid;
    std::int64_t timestamp = 0;
};

/// Reads `git stash list`. Read-only, so it runs on the read pool like RefStore
/// rather than queuing behind the mutating operations below.
class StashStore {
public:
    StashStore(IProcessRunner& runner, RepoPaths paths);

    GitResult<std::vector<StashEntry>> list(CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

struct StashSaveRequest {
    std::string message;
    bool includeUntracked = false;
    bool keepIndex = false;
    /// Restricts the stash to these paths (`git stash push -- <paths>`).
    /// Empty means every changed path, exactly like plain `git stash push`.
    std::vector<std::string> paths;
};

struct StashApplyRequest {
    int index = 0;
    /// Pop also drops the entry on success; apply leaves it in the list. Either
    /// way, a conflict leaves the entry exactly where `git stash` itself would:
    /// pop does not drop on conflict, matching plain `git stash pop`.
    bool pop = false;
};

struct StashDropRequest {
    int index = 0;
};

struct StashBranchRequest {
    int index = 0;
    std::string branchName;
};

/// `git stash push`. Refuses (InvalidArgument) rather than running git when
/// there is nothing to stash, exactly as `git stash` itself does, but with a
/// message the user does not have to interpret.
std::unique_ptr<Operation> makeStashSaveOperation(StashSaveRequest request);

/// `git stash apply` / `git stash pop`. A conflict is reported like any other
/// -- GitError::Code::Conflict -- and the working-copy panel picks up the
/// unmerged entries from the next status read, same as a conflicting merge.
std::unique_ptr<Operation> makeStashApplyOperation(StashApplyRequest request);

std::unique_ptr<Operation> makeStashDropOperation(StashDropRequest request);

/// `git stash branch`: creates `branchName` at the commit the stash was taken
/// from, checks it out, applies the stash, and drops it on success. The one
/// stash command that is also a checkout, so it goes through the ordinary
/// DirtyWorkTree/Conflict reporting rather than anything bespoke.
std::unique_ptr<Operation> makeStashBranchOperation(StashBranchRequest request);

}  // namespace gbm
