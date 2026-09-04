#include "core/git/ops/CheckoutOp.h"

#include "core/git/RefStore.h"

#include <utility>

namespace gbm {

namespace {

class CheckoutOperation final : public Operation {
public:
    explicit CheckoutOperation(CheckoutRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        if (request_.createBranch) {
            return "Create branch " + request_.newBranchName + " at " + request_.target;
        }
        if (request_.detach) {
            return "Check out " + request_.target + " (detached)";
        }
        return "Switch to " + request_.target;
    }

    std::string kind() const override { return "checkout"; }

    /// Never killed mid-flight: interrupting a checkout on a 500 MB work tree can
    /// leave a half-updated tree and a stale index.
    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        if (request_.target.empty() && !request_.createBranch) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No branch selected");
            return outcome;
        }
        if (request_.createBranch && !RefStore::isValidBranchName(request_.newBranchName)) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument,
                         "\"" + request_.newBranchName + "\" is not a valid branch name");
            return outcome;
        }

        // Stashing is a separate, recoverable step. Doing it first means that if
        // the switch then fails, the user's work is still safely in a stash rather
        // than lost.
        if (request_.stashFirst) {
            GitCommand stash(paths.commandDir(),
                             {"stash",
                              "push",
                              "--include-untracked",
                              "-m",
                              "git-branch-manager: before switching to " + request_.target});
            stash.timeout = std::chrono::seconds(600);
            auto stashed = runner.run(stash, token);
            if (!stashed) {
                outcome.error = std::move(stashed).error();
                outcome.summary = "Could not stash your changes, so nothing was switched";
                return outcome;
            }
        }

        std::vector<std::string> args;
        if (request_.createBranch) {
            args = {"switch", "--create", request_.newBranchName};
            if (!request_.target.empty()) {
                args.push_back(request_.target);
            }
        } else if (request_.detach) {
            args = {"switch", "--detach", request_.target};
        } else {
            args = {"switch", request_.target};
        }

        if (request_.force) {
            args.emplace_back("--discard-changes");
        }
        if (request_.recurseSubmodules) {
            args.emplace_back("--recurse-submodules");
        }

        GitCommand command(paths.commandDir(), std::move(args));
        // A checkout of a very large tree can legitimately take minutes; the user
        // gets a progress indication and a working Cancel instead of a timeout.
        command.timeout = std::chrono::milliseconds(0);

        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary = request_.createBranch
                                  ? "Created and switched to " + request_.newBranchName
                                  : "Switched to " + request_.target;
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        // The common, entirely expected failure: switching would overwrite local
        // modifications. Offer the two real answers rather than just reporting
        // git's text. No Abort entry: CheckoutRecoveryDialogContent
        // (app_flutter) filters `abort` out of both its action-button row and
        // its body list, and its retryCheckoutWithChoice dispatch is a no-op
        // for it -- an Abort choice here would never be visible or acted on,
        // and StashAndRetry/ForceDiscard alone already keep `choices`
        // non-empty, which is what makes the dialog open at all.
        if (error.code == GitError::Code::DirtyWorkTree && !request_.force &&
            !request_.stashFirst) {
            outcome.choices.push_back({OperationChoice::Kind::StashAndRetry, false});
            outcome.choices.push_back({OperationChoice::Kind::ForceDiscard, true});
        }

        outcome.error = std::move(error);
        return outcome;
    }

private:
    CheckoutRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeCheckoutOperation(CheckoutRequest request) {
    return std::make_unique<CheckoutOperation>(std::move(request));
}

}  // namespace gbm
