#include "core/git/ops/ConflictOps.h"

#include <fstream>
#include <utility>

namespace gbm {

namespace {

class ResolveConflictOperation final : public Operation {
public:
    explicit ResolveConflictOperation(ResolveConflictRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Resolve " + request_.path; }

    /// A conflict resolution is itself a recovery step within a merge, pick or
    /// revert -- it must be allowed to run while the sequencer operation is
    /// still in progress, since that is the whole point of it.
    bool allowedDuringSequencerOperation() const override { return true; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        if (request_.path.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No path to resolve");
            return outcome;
        }

        switch (request_.resolution) {
            case ConflictResolution::TakeOurs:
                return takeSide(runner, paths, token, /*ours=*/true);
            case ConflictResolution::TakeTheirs:
                return takeSide(runner, paths, token, /*ours=*/false);
            case ConflictResolution::MarkResolved:
                return markResolved(runner, paths, token);
            case ConflictResolution::WriteResolved:
                return writeResolved(runner, paths, token);
        }
        outcome.error = GitError(GitError::Code::InvalidArgument, "Unknown resolution");
        return outcome;
    }

private:
    OperationOutcome takeSide(IProcessRunner& runner,
                              const RepoPaths& paths,
                              CancellationToken token,
                              bool ours) {
        OperationOutcome outcome;
        const bool missing = ours ? request_.oursBlobMissing : request_.theirsBlobMissing;

        if (missing) {
            // The side being taken deleted this path: the resolution is a
            // deletion, not a content pick.
            GitCommand remove(paths.commandDir(), {"rm", "-f", "--", request_.path});
            remove.timeout = std::chrono::seconds(60);
            auto result = runner.run(remove, token);
            if (!result) {
                outcome.error = std::move(result).error();
                outcome.summary = outcome.error->message;
                return outcome;
            }
            outcome.succeeded = true;
            outcome.summary = "Resolved " + request_.path + " as deleted";
            return outcome;
        }

        GitCommand checkout(paths.commandDir(),
                            {"checkout", ours ? "--ours" : "--theirs", "--", request_.path});
        checkout.timeout = std::chrono::seconds(60);
        auto checkedOut = runner.run(checkout, token);
        if (!checkedOut) {
            outcome.error = std::move(checkedOut).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }

        return stage(runner, paths, token);
    }

    OperationOutcome markResolved(IProcessRunner& runner,
                                  const RepoPaths& paths,
                                  CancellationToken token) {
        return stage(runner, paths, token);
    }

    /// Writes the caller-supplied content verbatim to `path` on disk, then
    /// stages it the same way MarkResolved does -- `git add -A` clears the
    /// conflict stages regardless of how the working-tree content got there.
    OperationOutcome writeResolved(IProcessRunner& runner,
                                   const RepoPaths& paths,
                                   CancellationToken token) {
        OperationOutcome outcome;

        if (request_.resolvedContent.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "No resolved content to write");
            return outcome;
        }
        if (paths.workDir().empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "No working tree to write into");
            return outcome;
        }

        const std::filesystem::path target = paths.workDir() / request_.path;
        std::ofstream out(target, std::ios::binary | std::ios::trunc);
        if (!out) {
            outcome.error = GitError(GitError::Code::Io, "Could not write " + request_.path);
            return outcome;
        }
        out.write(request_.resolvedContent.data(),
                  static_cast<std::streamsize>(request_.resolvedContent.size()));
        out.close();
        if (!out) {
            outcome.error = GitError(GitError::Code::Io, "Could not write " + request_.path);
            return outcome;
        }

        return stage(runner, paths, token);
    }

    /// `-A` rather than a bare `add`: the user may have resolved the conflict by
    /// deleting the file entirely, and a bare `add <path>` refuses to stage a
    /// path that no longer exists on disk.
    OperationOutcome stage(IProcessRunner& runner,
                           const RepoPaths& paths,
                           CancellationToken token) {
        OperationOutcome outcome;
        GitCommand add(paths.commandDir(), {"add", "-A", "--", request_.path});
        add.timeout = std::chrono::seconds(60);
        auto result = runner.run(add, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Resolved " + request_.path;
        return outcome;
    }

    ResolveConflictRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeResolveConflictOperation(ResolveConflictRequest request) {
    return std::make_unique<ResolveConflictOperation>(std::move(request));
}

}  // namespace gbm
