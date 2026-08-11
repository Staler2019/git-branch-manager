#include "core/git/ops/StageOps.h"

#include "core/git/DiffService.h"

#include <utility>

namespace gbm {

namespace {

/// Shared by ApplyPatchOperation and PartialStageOperation: `git apply
/// --cached [--reverse]` fed `patch` on stdin. `--whitespace=nowarn`: a
/// partial stage must not fail just because the hunk it was cut from
/// trails whitespace elsewhere in the file.
GitResult<ProcessResult> applyPatchToIndex(IProcessRunner& runner,
                                           const RepoPaths& paths,
                                           const std::string& patch,
                                           bool reverse,
                                           CancellationToken token) {
    std::vector<std::string> args{"apply", "--cached", "--whitespace=nowarn"};
    if (reverse) {
        args.emplace_back("--reverse");
    }
    args.emplace_back("-");

    GitCommand command(paths.commandDir(), std::move(args));
    command.stdinData = patch;
    command.timeout = std::chrono::seconds(60);
    return runner.run(command, token);
}

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

        auto result = applyPatchToIndex(runner, paths, request_.patch, request_.reverse, token);
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

class PartialStageOperation final : public Operation {
public:
    explicit PartialStageOperation(PartialStageRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        const char* verb = request_.staged ? "Unstage " : "Stage ";
        const char* what = request_.lineIndices.empty() ? "hunk in " : "selected lines in ";
        return verb + std::string(what) + request_.path;
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.path.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No file specified");
            return outcome;
        }

        DiffService diffs(runner, paths);
        const DiffOptions options;
        auto diffResult = diffs.workingTreeDiff(request_.staged, {request_.path}, options, token);
        if (!diffResult) {
            outcome.error = std::move(diffResult).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        const ParsedDiff& diff = *diffResult.value();
        if (diff.files.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "No pending changes found for \"" + request_.path + "\"");
            return outcome;
        }
        const DiffFile& file = diff.files.front();
        if (request_.hunkIndex >= file.hunks.size()) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "That change no longer exists -- the file may have changed");
            return outcome;
        }
        const DiffHunk& hunk = file.hunks[request_.hunkIndex];

        std::string patch;
        if (request_.lineIndices.empty()) {
            patch = UnifiedDiffParser::buildHunkPatch(
                file, hunk, /*reverse=*/false, /*unstaging=*/request_.staged);
        } else {
            std::vector<bool> selected(hunk.lines.size(), false);
            for (const std::size_t index : request_.lineIndices) {
                if (index < selected.size()) {
                    selected[index] = true;
                }
            }
            patch = UnifiedDiffParser::buildLineSelectionPatch(
                file, hunk, selected, /*unstaging=*/request_.staged);
        }
        if (patch.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "Nothing selected to apply");
            return outcome;
        }

        auto result = applyPatchToIndex(runner, paths, patch, /*reverse=*/request_.staged, token);
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
    PartialStageRequest request_;
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

std::unique_ptr<Operation> makePartialStageOperation(PartialStageRequest request) {
    return std::make_unique<PartialStageOperation>(std::move(request));
}

}  // namespace gbm
