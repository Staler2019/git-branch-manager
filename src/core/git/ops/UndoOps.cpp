#include "core/git/ops/UndoOps.h"

#include "core/git/RefStore.h"

#include <utility>

namespace gbm {

namespace {

class UndoOperation final : public Operation {
public:
    explicit UndoOperation(UndoRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Undo"; }

    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        if (request_.headBefore.isNull()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "Nothing to undo");
            return outcome;
        }

        RefStore refs(runner, paths);
        auto head = refs.readHead(token);
        if (!head) {
            outcome.error = std::move(head).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        if (!request_.branchBefore.empty() && head->kind == HeadInfo::Kind::Branch &&
            head->branchName != request_.branchBefore) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument,
                         "Switch back to \"" + request_.branchBefore + "\" before undoing this");
            return outcome;
        }

        GitCommand command(paths.commandDir(), {"reset", "--hard", request_.headBefore.hex()});
        command.timeout = std::chrono::milliseconds(0);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Undid the last operation";
        return outcome;
    }

private:
    UndoRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeUndoOperation(UndoRequest request) {
    return std::make_unique<UndoOperation>(std::move(request));
}

}  // namespace gbm
