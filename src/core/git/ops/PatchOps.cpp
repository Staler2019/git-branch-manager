#include "core/git/ops/PatchOps.h"

#include <utility>

namespace gbm {

namespace {

class ExportPatchesOperation final : public Operation {
public:
    explicit ExportPatchesOperation(ExportPatchesRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return "Export " + std::to_string(request_.commits.size()) + " patch(es)";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.commits.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No commits selected");
            return outcome;
        }
        if (request_.outputDir.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No output folder chosen");
            return outcome;
        }

        for (std::size_t i = 0; i < request_.commits.size(); ++i) {
            if (token.isCancelled()) {
                outcome.error = cancelled().error();
                return outcome;
            }
            GitCommand command(paths.commandDir(),
                               {"format-patch",
                                "-1",
                                request_.commits[i].hex(),
                                "--start-number",
                                std::to_string(i + 1),
                                "-o",
                                request_.outputDir.string()});
            command.timeout = std::chrono::seconds(60);

            auto result = runner.run(command, token);
            if (!result) {
                outcome.error = std::move(result).error();
                outcome.summary = outcome.error->message;
                return outcome;
            }
        }
        outcome.succeeded = true;
        outcome.summary = std::to_string(request_.commits.size()) + " patch(es) written to " +
                          request_.outputDir.string();
        return outcome;
    }

private:
    ExportPatchesRequest request_;
};

class ApplyPatchFilesOperation final : public Operation {
public:
    explicit ApplyPatchFilesOperation(ApplyPatchFilesRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Apply patch"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.patchFiles.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No patch file chosen");
            return outcome;
        }

        std::vector<std::string> args{"apply"};
        if (request_.threeWay) {
            args.emplace_back("--3way");
        }
        if (request_.updateIndex) {
            args.emplace_back("--index");
        }
        for (const auto& file : request_.patchFiles) {
            args.push_back(file.string());
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
        outcome.summary = describe();
        return outcome;
    }

private:
    ApplyPatchFilesRequest request_;
};

class ImportPatchesOperation final : public Operation {
public:
    explicit ImportPatchesOperation(ImportPatchesRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return "Import " + std::to_string(request_.patchFiles.size()) + " patch(es)";
    }

    /// A conflicted patch leaves `git am` mid-sequence, exactly like a
    /// conflicted rebase or cherry-pick; killing the process would leave that
    /// state half-written.
    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.patchFiles.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No patch file chosen");
            return outcome;
        }

        std::vector<std::string> args{"am"};
        if (request_.threeWay) {
            args.emplace_back("--3way");
        }
        for (const auto& file : request_.patchFiles) {
            args.push_back(file.string());
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
    ImportPatchesRequest request_;
};

class AmContinueOperation final : public Operation {
public:
    std::string describe() const override { return "Continue applying patches"; }

    bool killableMidFlight() const override { return false; }
    bool allowedDuringSequencerOperation() const override { return true; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(paths.commandDir(), {"am", "--continue"});
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
};

class AmSkipOperation final : public Operation {
public:
    std::string describe() const override { return "Skip patch"; }

    bool killableMidFlight() const override { return false; }
    bool allowedDuringSequencerOperation() const override { return true; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(paths.commandDir(), {"am", "--skip"});
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
};

class AmAbortOperation final : public Operation {
public:
    std::string describe() const override { return "Abort patch import"; }

    bool killableMidFlight() const override { return false; }
    bool allowedDuringSequencerOperation() const override { return true; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(paths.commandDir(), {"am", "--abort"});
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
};

}  // namespace

std::unique_ptr<Operation> makeExportPatchesOperation(ExportPatchesRequest request) {
    return std::make_unique<ExportPatchesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeApplyPatchFilesOperation(ApplyPatchFilesRequest request) {
    return std::make_unique<ApplyPatchFilesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeImportPatchesOperation(ImportPatchesRequest request) {
    return std::make_unique<ImportPatchesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeAmContinueOperation() {
    return std::make_unique<AmContinueOperation>();
}

std::unique_ptr<Operation> makeAmSkipOperation() {
    return std::make_unique<AmSkipOperation>();
}

std::unique_ptr<Operation> makeAmAbortOperation() {
    return std::make_unique<AmAbortOperation>();
}

}  // namespace gbm
