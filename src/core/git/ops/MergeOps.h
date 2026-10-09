#pragma once

#include "core/git/OperationRunner.h"

#include <memory>
#include <string>

namespace gbm {

enum class MergeMode : std::uint8_t {
    /// `--ff-only`: refuses rather than creating a merge commit. The safest
    /// default when the user has not said which kind of history they want.
    FastForwardOnly,
    /// `--no-ff`: always creates a merge commit, even when a fast-forward is
    /// possible. What most teams mean by "merge" in the Fork sense.
    NoFastForward,
    /// `--squash`: stages the combined diff with no merge commit and no
    /// parent link. With a MergeRequest::message and no conflict, it is then
    /// committed as one ordinary commit -- unless the index already differed
    /// from HEAD before it, which stays staged rather than be swept into that
    /// commit; without one, it stays staged for the caller. Never leaves a
    /// MERGE_HEAD behind, so RepoState::Merge never applies to a squash.
    Squash,
};

struct MergeRequest {
    std::string target;  ///< Branch, tag or commit to merge into HEAD.
    MergeMode mode = MergeMode::NoFastForward;
    /// Overrides the default merge commit message. For Squash it is the
    /// commit message of the follow-up commit -- empty leaves the squash
    /// staged and uncommitted, as before.
    std::string message;
    /// Set after the user picks "Stash and merge" in response to a
    /// DirtyWorkTree failure -- see CheckoutRequest::stashFirst, same idea.
    bool stashFirst = false;
};

/// `git merge`, in one of three modes. A conflicting merge is not a failure of
/// this operation in the ordinary sense: it succeeds at exactly what git itself
/// does, which is stop with the conflict recorded in the index and MERGE_HEAD
/// on disk, so it is still reported as OperationOutcome::succeeded == false
/// with GitError::Code::Conflict, and the working-copy panel picks up the
/// unmerged entries from the next status read.
std::unique_ptr<Operation> makeMergeOperation(MergeRequest request);

/// `git merge --abort`. Only valid while RepoState::Merge is set; git itself
/// enforces that and the error is passed through rather than pre-checked here.
std::unique_ptr<Operation> makeMergeAbortOperation();

}  // namespace gbm
