#pragma once

#include "core/base/ObjectId.h"
#include "core/git/OperationRunner.h"

#include <memory>
#include <string>
#include <vector>

namespace gbm {

/// One line of a rebase todo list.
///
/// `Reword` is deliberately not offered: with no terminal or editor available
/// (see MergeOps's `--no-edit` comment), a reword step would run to completion
/// silently keeping the original message rather than pausing for a new one --
/// indistinguishable from Pick. `Edit` is the verb that actually works: the
/// rebase stops with the commit checked out, and the existing amend flow
/// (CommitOps) changes its message or contents before Continue.
struct RebaseTodoEntry {
    enum class Action { Pick, Edit, Squash, Fixup, Drop };
    Action action = Action::Pick;
    ObjectId oid;
    std::string shortOid;
    std::string subject;
};

/// Builds the todo list a plain `git rebase -i <upstream>` would start from --
/// read-only, so the UI can show and let the user edit it before anything runs.
class RebasePlanner {
public:
    RebasePlanner(IProcessRunner& runner, RepoPaths paths);

    /// `upstream..HEAD`, oldest first: the order the todo list is applied in.
    GitResult<std::vector<RebaseTodoEntry>> plan(const std::string& upstream,
                                                 CancellationToken token);

private:
    IProcessRunner& runner_;
    RepoPaths paths_;
};

struct RebaseInteractiveRequest {
    std::string upstream;               ///< Exclusive lower bound: replays upstream..HEAD.
    std::string onto;                   ///< Optional `--onto`; empty means onto upstream itself.
    std::vector<RebaseTodoEntry> todo;  ///< The (possibly reordered/edited) plan.
    bool stashFirst = false;
};

struct RebaseRequest {
    std::string upstream;
    std::string onto;
    bool stashFirst = false;
};

/// `git rebase -i`, with the todo list supplied ourselves rather than through an
/// interactive editor -- see RebaseOps.cpp for how. Stops at the first conflict
/// or `edit` line exactly as git does; RepoState::RebaseMerge picks it up from
/// then on.
std::unique_ptr<Operation> makeRebaseInteractiveOperation(RebaseInteractiveRequest request);

/// Plain, non-interactive `git rebase`: replays every commit unchanged, with no
/// todo list to edit.
std::unique_ptr<Operation> makeRebaseOperation(RebaseRequest request);

/// `git rebase --continue`, once every conflict in the current step is resolved
/// and staged (or, for an `edit` stop, whenever the user is done amending).
std::unique_ptr<Operation> makeRebaseContinueOperation();

/// `git rebase --skip`: drops the commit that is currently conflicting.
std::unique_ptr<Operation> makeRebaseSkipOperation();

/// `git rebase --abort`: unwinds back to before the rebase started.
std::unique_ptr<Operation> makeRebaseAbortOperation();

}  // namespace gbm
