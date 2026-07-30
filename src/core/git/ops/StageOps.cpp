#include "core/git/ops/StageOps.h"

#include <utility>

namespace gbm {

namespace {

class StageFilesOperation final : public Operation {
public:
    explicit StageFilesOperation(StageFilesRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return request_.paths.size() == 1
                   ? "Stage " + request_.paths.front()
                   : "Stage " + std::to_string(request_.paths.size()) + " files";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.paths.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No files selected to stage");
            return outcome;
        }

        std::vector<std::string> args{"add", "--"};
        for (const std::string& path : request_.paths) {
            args.push_back(path);
        }

        GitCommand command(paths.commandDir(), std::move(args));
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
    StageFilesRequest request_;
};

class UnstageFilesOperation final : public Operation {
public:
    explicit UnstageFilesOperation(UnstageFilesRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return request_.paths.size() == 1
                   ? "Unstage " + request_.paths.front()
                   : "Unstage " + std::to_string(request_.paths.size()) + " files";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.paths.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "No files selected to unstage");
            return outcome;
        }

        std::vector<std::string> args{"restore", "--staged", "--"};
        for (const std::string& path : request_.paths) {
            args.push_back(path);
        }

        GitCommand command(paths.commandDir(), std::move(args));
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
    UnstageFilesRequest request_;
};

class ApplyPatchOperation final : public Operation {
public:
    explicit ApplyPatchOperation(ApplyPatchRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return request_.reverse ? "Unstage selected changes" : "Stage selected changes";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.patch.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "Nothing to apply");
            return outcome;
        }

        // --whitespace=nowarn: a partial stage must not fail just because the
        // hunk it was cut from trails whitespace elsewhere in the file.
        std::vector<std::string> args{"apply", "--cached", "--whitespace=nowarn"};
        if (request_.reverse) {
            args.emplace_back("--reverse");
        }
        args.emplace_back("-");

        GitCommand command(paths.commandDir(), std::move(args));
        command.stdinData = request_.patch;
        command.timeout = std::chrono::seconds(60);

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
    ApplyPatchRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeStageFilesOperation(StageFilesRequest request) {
    return std::make_unique<StageFilesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeUnstageFilesOperation(UnstageFilesRequest request) {
    return std::make_unique<UnstageFilesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeApplyPatchOperation(ApplyPatchRequest request) {
    return std::make_unique<ApplyPatchOperation>(std::move(request));
}

}  // namespace gbm
