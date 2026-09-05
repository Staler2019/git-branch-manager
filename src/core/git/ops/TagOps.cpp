#include "core/git/ops/TagOps.h"

#include "core/git/AskpassHelper.h"
#include "core/git/RefStore.h"

#include <utility>

namespace gbm {

namespace {

class CreateTagOperation final : public Operation {
public:
    explicit CreateTagOperation(CreateTagRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Create tag " + request_.name; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (!RefStore::isValidBranchName(request_.name)) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "\"" + request_.name + "\" is not a valid tag name");
            return outcome;
        }

        std::vector<std::string> args{"tag"};
        if (!request_.message.empty()) {
            args.emplace_back("-a");
        }
        if (request_.force) {
            args.emplace_back("-f");
        }
        args.push_back(request_.name);
        if (!request_.message.empty()) {
            args.emplace_back("-m");
            args.push_back(request_.message);
        }
        if (!request_.target.empty()) {
            args.push_back(request_.target);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(60);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Created tag " + request_.name;
        return outcome;
    }

private:
    CreateTagRequest request_;
};

class DeleteTagOperation final : public Operation {
public:
    explicit DeleteTagOperation(DeleteTagRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Delete tag " + request_.name; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand local(paths.commandDir(), {"tag", "-d", request_.name});
        local.timeout = std::chrono::seconds(60);
        auto result = runner.run(local, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }

        if (!request_.alsoRemote) {
            outcome.succeeded = true;
            outcome.summary = "Deleted tag " + request_.name;
            return outcome;
        }

        GitCommand remote(paths.commandDir(),
                          {"push", request_.remoteName, "--delete", "refs/tags/" + request_.name});
        remote.timeout = std::chrono::milliseconds(0);
        remote.idleTimeout = GitCommand::kHangCeiling;
        askpass::wire(remote, request_.askpassDir);
        auto remoteResult = runner.run(remote, token);
        if (!remoteResult) {
            outcome.error = std::move(remoteResult).error();
            outcome.summary = "Deleted locally, but could not delete on " + request_.remoteName +
                              ": " + outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Deleted tag " + request_.name + " locally and on " + request_.remoteName;
        return outcome;
    }

private:
    DeleteTagRequest request_;
};

class PushTagOperation final : public Operation {
public:
    explicit PushTagOperation(PushTagRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return request_.name.empty() ? "Push all tags to " + request_.remoteName
                                     : "Push tag " + request_.name + " to " + request_.remoteName;
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"push", request_.remoteName};
        if (request_.name.empty()) {
            args.emplace_back("--tags");
        } else {
            args.push_back("refs/tags/" + request_.name);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
        command.idleTimeout = GitCommand::kHangCeiling;
        askpass::wire(command, request_.askpassDir);

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
    PushTagRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeCreateTagOperation(CreateTagRequest request) {
    return std::make_unique<CreateTagOperation>(std::move(request));
}

std::unique_ptr<Operation> makeDeleteTagOperation(DeleteTagRequest request) {
    return std::make_unique<DeleteTagOperation>(std::move(request));
}

std::unique_ptr<Operation> makePushTagOperation(PushTagRequest request) {
    return std::make_unique<PushTagOperation>(std::move(request));
}

}  // namespace gbm
