#include "core/git/ops/CommitOps.h"

#include <cctype>
#include <utility>

namespace gbm {

namespace {

bool isBlank(std::string_view text) {
    for (char c : text) {
        if (std::isspace(static_cast<unsigned char>(c)) == 0) {
            return false;
        }
    }
    return true;
}

class CommitOperation final : public Operation {
public:
    explicit CommitOperation(CommitRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return request_.amend ? "Amend commit" : "Commit"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        const bool keepExistingMessage = request_.amend && request_.message.empty();
        if (!keepExistingMessage && isBlank(request_.message)) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "The commit message is empty");
            return outcome;
        }

        std::vector<std::string> args{"commit"};
        if (request_.amend) {
            args.emplace_back("--amend");
        }
        if (request_.signOff) {
            args.emplace_back("--signoff");
        }

        GitCommand command(paths.commandDir(), std::move(args));
        if (keepExistingMessage) {
            command.args.emplace_back("--no-edit");
        } else {
            // Via stdin rather than -m: an argv entry has a platform-dependent
            // length limit, and a multi-line body would need shell-style
            // escaping that argv otherwise avoids entirely.
            command.args.emplace_back("--file");
            command.args.emplace_back("-");
            command.stdinData = request_.message;
        }
        command.timeout = std::chrono::seconds(120);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = describe();
        return outcome;
    }

private:
    CommitRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeCommitOperation(CommitRequest request) {
    return std::make_unique<CommitOperation>(std::move(request));
}

}  // namespace gbm
