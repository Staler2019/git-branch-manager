#pragma once

#include "core/base/ObjectId.h"
#include "core/git/OperationRunner.h"

#include <memory>
#include <vector>

namespace gbm {

struct RevertRequest {
    /// Oldest first, same convention as CherryPickRequest::commits -- a single
    /// commit is a one-element list, a range is this same list after the
    /// caller has expanded it with RefStore::resolveRange.
    std::vector<ObjectId> commits;

    /// `--no-commit`: stages every revert's changes without creating a commit
    /// for any of them, mirroring CherryPickRequest::noCommit.
    bool noCommit = false;

    /// Set after the user picks "Stash and revert" in response to a
    /// DirtyWorkTree failure -- see CheckoutRequest::stashFirst, same idea.
    bool stashFirst = false;
};

/// `git revert <commits...>`. Like cherry-pick, stops at the first conflict
/// with the remainder still queued in the sequencer -- see RepoState::Revert.
/// Continue/skip/abort for an in-progress revert have no UI entry point yet
/// (MainWindow::updateSequencerControls deliberately does not offer them for
/// Revert, since nothing runs `git revert --continue` on the user's behalf
/// today), so only the one-shot operation exists here.
std::unique_ptr<Operation> makeRevertOperation(RevertRequest request);

}  // namespace gbm
