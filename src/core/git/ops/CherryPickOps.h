#pragma once

#include "core/base/ObjectId.h"
#include "core/git/OperationRunner.h"

#include <memory>
#include <vector>

namespace gbm {

struct CherryPickRequest {
    /// Oldest first: the order they are applied in, and the order a preview
    /// should list them in. A single-commit pick is just a one-element list; a
    /// range is this same list after the caller has expanded it with
    /// RefStore::resolveRange.
    std::vector<ObjectId> commits;

    /// For cherry-picking a merge commit: which parent (1-based) is "mainline".
    /// 0 means the commit is not a merge and no `-m` is passed.
    int mainline = 0;

    /// `--no-commit`: stages every pick's changes without creating a commit for
    /// any of them, so a run of several picks can be squashed into one commit
    /// afterwards via CommitOps.
    bool noCommit = false;

    /// Set after the user picks "Stash and pick" in response to a
    /// DirtyWorkTree failure -- see CheckoutRequest::stashFirst, same idea.
    bool stashFirst = false;
};

/// `git cherry-pick <commits...>`. Stops at the first conflict, exactly as git
/// does; the remaining commits stay queued in the sequencer for `--continue` or
/// `--skip` to work through. See RepoState::CherryPick / Sequencer.
std::unique_ptr<Operation> makeCherryPickOperation(CherryPickRequest request);

/// `git cherry-pick --continue`, once every conflict in the current pick is
/// resolved and staged.
std::unique_ptr<Operation> makeCherryPickContinueOperation();

/// `git cherry-pick --skip`: drops the current pick entirely and moves on to
/// the next one queued, if any.
std::unique_ptr<Operation> makeCherryPickSkipOperation();

/// `git cherry-pick --abort`: unwinds back to before the pick sequence started.
std::unique_ptr<Operation> makeCherryPickAbortOperation();

}  // namespace gbm
