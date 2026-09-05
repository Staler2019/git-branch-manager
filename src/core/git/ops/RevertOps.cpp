#include "core/git/ops/RevertOps.h"

#include <utility>

namespace gbm {

namespace {

class RevertOperation final : public Operation {
public:
    explicit RevertOperation(RevertRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        if (request_.commits.size() == 1) {
            return "Revert " + request_.commits.front().shortHex();
        }
        return "Revert " + std::to_string(request_.commits.size()) + " commits";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        if (request_.commits.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "No commits selected to revert");
            return outcome;
        }

        if (request_.stashFirst) {
            GitCommand stash(paths.commandDir(),
                             {"stash",
                              "push",
                              "--include-untracked",
                              "-m",
                              "git-branch-manager: before revert"});
            stash.timeout = std::chrono::seconds(600);
            auto stashed = runner.run(stash, token);
            if (!stashed) {
                outcome.error = std::move(stashed).error();
                outcome.summary = "Could not stash your changes, so nothing was reverted";
                return outcome;
            }
        }

        std::vector<std::string> args{"revert"};
        if (request_.noCommit) {
            args.emplace_back("--no-commit");
        }
        for (const ObjectId& commit : request_.commits) {
            args.push_back(commit.hex());
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
        command.idleTimeout = GitCommand::kHangCeiling;

        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary = describe();
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        // A dirty-work-tree failure used to push StashAndRetry/Abort choices
        // here -- see MergeOps.cpp's identical comment; the same
        // [CULT-orphan-wiring] shape applies: no Dart reader for a
        // "revert"-kind outcome's choices.

        // As with a conflicting cherry-pick, this is git stopping exactly where
        // it should: the conflict is recorded in the index and REVERT_HEAD.
        if (error.code == GitError::Code::Conflict) {
            outcome.summary = "Revert stopped with conflicts to resolve";
        }

        outcome.error = std::move(error);
        return outcome;
    }

private:
    RevertRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeRevertOperation(RevertRequest request) {
    return std::make_unique<RevertOperation>(std::move(request));
}

}  // namespace gbm
