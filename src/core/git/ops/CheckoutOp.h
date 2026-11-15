#pragma once

#include "core/git/OperationRunner.h"

#include <memory>
#include <string>

namespace gbm {

struct CheckoutRequest {
    std::string target;   ///< Branch name, tag, or commit-ish.
    bool detach = false;  ///< Check out a commit without moving a branch.
    /// Creates [newBranchName] at [target] tracking it (`--track`): the
    /// checkout-a-remote-branch-as-local path, so [target] is a
    /// remote-tracking ref. git refuses `--track` from a raw commit id, a
    /// tag, or a `refs/remotes/` ref no configured remote's fetch refspec
    /// maps (measured, git 2.56); a symbolic ref such as `HEAD` is accepted
    /// and tracks the local branch it names.
    bool createBranch = false;
    std::string newBranchName;  ///< Used when createBranch is set.

    /// Discards local modifications. Only ever set after the user explicitly
    /// chooses it in response to the dirty-work-tree failure.
    bool force = false;

    /// Stashes local changes first, then switches. The safe answer, and the one
    /// offered as the default.
    bool stashFirst = false;

    bool recurseSubmodules = false;
};

/// Switches branches with `git switch` / `git checkout`.
///
/// The CLI is used rather than any lower-level mechanism specifically so the
/// user's `post-checkout` hook runs, sparse-checkout patterns are honoured, and
/// submodule handling matches what they would get from a terminal. A GUI that
/// quietly skips hooks is a GUI people stop trusting.
std::unique_ptr<Operation> makeCheckoutOperation(CheckoutRequest request);

}  // namespace gbm
