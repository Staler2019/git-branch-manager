#include "core/git/ops/MergeOps.h"

#include <chrono>
#include <utility>

namespace gbm {

namespace {

std::string modeLabel(MergeMode mode) {
    switch (mode) {
        case MergeMode::FastForwardOnly:
            return "Fast-forward";
        case MergeMode::NoFastForward:
            return "Merge";
        case MergeMode::Squash:
            return "Squash merge";
    }
    return "Merge";
}

class MergeOperation final : public Operation {
public:
    explicit MergeOperation(MergeRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return modeLabel(request_.mode) + " " + request_.target;
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        if (request_.target.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "No branch selected to merge");
            return outcome;
        }

        // As with checkout: stash first, as a separate step, so a failure in the
        // merge itself still leaves the user's work recoverable from the stash
        // rather than lost.
        if (request_.stashFirst) {
            GitCommand stash(paths.commandDir(),
                             {"stash",
                              "push",
                              "--include-untracked",
                              "-m",
                              "git-branch-manager: before merging " + request_.target});
            stash.timeout = GitCommand::kLocalCeiling;
            auto stashed = runner.run(stash, token);
            if (!stashed) {
                outcome.error = std::move(stashed).error();
                outcome.summary = "Could not stash your changes, so nothing was merged";
                return outcome;
            }
        }

        std::vector<std::string> args{"merge"};
        switch (request_.mode) {
            case MergeMode::FastForwardOnly:
                args.emplace_back("--ff-only");
                break;
            case MergeMode::NoFastForward:
                args.emplace_back("--no-ff");
                // Neither an editor nor a terminal is available to write a merge
                // commit message, so one is always supplied: the caller's, or
                // git's own default via --no-edit.
                if (request_.message.empty()) {
                    args.emplace_back("--no-edit");
                } else {
                    args.emplace_back("-m");
                    args.push_back(request_.message);
                }
                break;
            case MergeMode::Squash:
                // --squash never commits on its own; with a message, the commit
                // is a separate step after it -- see commitSquash() below.
                args.emplace_back("--squash");
                break;
        }
        args.push_back(request_.target);

        GitCommand command(paths.commandDir(), std::move(args));
        // A merge across a very large tree can legitimately take a while; it gets
        // a working Cancel ~~rather than a timeout~~ and, since 2026-10-07, the
        // local ceiling too (effectiveDeadlines()).

        auto result = runner.run(command, token);
        if (result) {
            if (request_.mode == MergeMode::Squash && !request_.message.empty()) {
                return commitSquash(runner, paths, token);
            }
            outcome.succeeded = true;
            outcome.summary = modeLabel(request_.mode) + "d " + request_.target;
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        // A dirty-work-tree failure used to push StashAndRetry/Abort choices
        // here, but nothing under app_flutter/lib ever reads
        // RepoSessionState for a "merge"-kind outcome's choices --
        // _handleOperationOutcome's switch has arms only for
        // checkout/deleteBranch (see [CULT-orphan-wiring] and
        // [DRIFT-no-pull-dialog] in .claude/rules/ for the same shape on other
        // operations). outcome.summary/error still carry the failure
        // message through the ordinary lastError path below, so nothing is
        // lost from what the user actually sees.

        // A conflicting merge is not this operation failing to do its job -- it is
        // git stopping exactly where it should, with the conflict recorded in the
        // index (and, outside Squash, in MERGE_HEAD) for the working-copy panel to
        // pick up. Nothing here recovers automatically; the choice belongs to
        // whichever UI shows the conflicted files.
        if (error.code == GitError::Code::Conflict) {
            outcome.summary = "Merge stopped with conflicts to resolve";
        }

        outcome.error = std::move(error);
        return outcome;
    }

private:
    /// The squash landed without conflict (使用者裁定 2026-10-08：「merge沒
    /// conflict才可以直接commit」), so commit it with the caller's message.
    /// Nothing staged -- the source was already in HEAD -- is not a commit
    /// to attempt: git would only refuse with "nothing to commit". A commit
    /// that fails (a hook, signing) leaves the squash staged and says so.
    OperationOutcome commitSquash(IProcessRunner& runner,
                                  const RepoPaths& paths,
                                  CancellationToken token) {
        OperationOutcome outcome;

        // Exit 1 is the answer "the index differs from HEAD", not a failure.
        GitCommand staged(paths.commandDir(), {"diff", "--cached", "--quiet"});
        staged.timeout = std::chrono::seconds(60);
        staged.benignExitCodes = {1};
        auto probe = runner.run(staged, token);
        if (probe) {
            outcome.succeeded = true;
            outcome.summary = request_.target + " is already up to date -- nothing to squash";
            return outcome;
        }
        if (probe.error().exitCode != 1) {
            outcome.error = std::move(probe).error();
            outcome.summary = "Squashed " + request_.target +
                              ", but could not check what was staged -- nothing was committed";
            return outcome;
        }

        // Via stdin rather than -m, like CommitOps: a SQUASH_MSG carries every
        // squashed commit's full body and can outgrow an argv entry.
        GitCommand commit(paths.commandDir(), {"commit", "--file", "-"});
        commit.stdinData = request_.message;
        commit.timeout = std::chrono::seconds(120);
        auto committed = runner.run(commit, token);
        if (!committed) {
            outcome.error = std::move(committed).error();
            outcome.summary =
                "Squashed " + request_.target + ", but the commit failed -- the changes are staged";
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Squash merged " + request_.target;
        return outcome;
    }

    MergeRequest request_;
};

class MergeAbortOperation final : public Operation {
public:
    std::string describe() const override { return "Abort merge"; }

    bool allowedDuringSequencerOperation() const override { return true; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(paths.commandDir(), {"merge", "--abort"});
        command.timeout = std::chrono::seconds(120);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Merge aborted";
        return outcome;
    }
};

}  // namespace

std::unique_ptr<Operation> makeMergeOperation(MergeRequest request) {
    return std::make_unique<MergeOperation>(std::move(request));
}

std::unique_ptr<Operation> makeMergeAbortOperation() {
    return std::make_unique<MergeAbortOperation>();
}

}  // namespace gbm
