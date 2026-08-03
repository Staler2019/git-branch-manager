#include "core/git/ops/BranchOps.h"

#include "core/base/FsUtil.h"
#include "core/git/RefStore.h"

#include <utility>

namespace gbm {

namespace {

class CreateBranchOperation final : public Operation {
public:
    explicit CreateBranchOperation(CreateBranchRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Create branch " + request_.name; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (!RefStore::isValidBranchName(request_.name)) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "\"" + request_.name + "\" is not a valid branch name");
            return outcome;
        }

        std::vector<std::string> args{"branch", request_.name};
        if (!request_.startPoint.empty()) {
            args.push_back(request_.startPoint);
        }
        if (request_.setUpstream && !request_.upstream.empty()) {
            args.emplace_back("--track");
            args.push_back(request_.upstream);
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
        outcome.summary = "Created branch " + request_.name;
        return outcome;
    }

private:
    CreateBranchRequest request_;
};

class RenameBranchOperation final : public Operation {
public:
    explicit RenameBranchOperation(RenameBranchRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return "Rename branch " + request_.from + " to " + request_.to;
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (!RefStore::isValidBranchName(request_.to)) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "\"" + request_.to + "\" is not a valid branch name");
            return outcome;
        }

        // A case-only rename ("Feature" -> "feature") fails on Windows and macOS,
        // where the ref file path is the same name to the filesystem. Going via a
        // temporary name is the only way to make it work on those platforms.
        const bool caseOnlyRename =
            request_.from != request_.to && fsutil::pathsEquivalent(request_.from, request_.to);

        if (caseOnlyRename && fsutil::caseInsensitiveFilesystem()) {
            const std::string temporary = request_.from + ".gbm-rename-tmp";
            GitCommand first(paths.commandDir(), {"branch", "-m", request_.from, temporary});
            first.timeout = std::chrono::seconds(60);
            auto step = runner.run(first, token);
            if (!step) {
                outcome.error = std::move(step).error();
                outcome.summary = outcome.error->message;
                return outcome;
            }

            GitCommand second(paths.commandDir(), {"branch", "-m", temporary, request_.to});
            second.timeout = std::chrono::seconds(60);
            auto finish = runner.run(second, token);
            if (!finish) {
                outcome.error = std::move(finish).error();
                // Leaving the branch under a temporary name would be worse than the
                // original failure, so say exactly where it ended up.
                outcome.summary =
                    "The branch is currently named " + temporary + "; rename it manually to finish";
                return outcome;
            }
            outcome.succeeded = true;
            outcome.summary = "Renamed to " + request_.to;
            return outcome;
        }

        std::vector<std::string> args{
            "branch", request_.force ? "-M" : "-m", request_.from, request_.to};
        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(60);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Renamed to " + request_.to;
        return outcome;
    }

private:
    RenameBranchRequest request_;
};

class DeleteBranchOperation final : public Operation {
public:
    explicit DeleteBranchOperation(DeleteBranchRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return "Delete branch" + std::string(request_.names.size() > 1 ? "es " : " ") + joinNames();
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        std::vector<std::string> args;
        if (request_.isRemote) {
            // Deleting a remote branch is a network operation with a very
            // different blast radius from deleting a local ref.
            args = {"push", request_.remoteName, "--delete"};
        } else {
            args = {"branch", request_.force ? "-D" : "-d"};
        }
        args.insert(args.end(), request_.names.begin(), request_.names.end());

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout =
            request_.isRemote ? std::chrono::milliseconds(0) : std::chrono::milliseconds(60000);

        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary = "Deleted " + joinNames();
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        // `-d` refuses to delete unmerged work. Offering `-D` is legitimate, but
        // it has to be labelled honestly.
        const bool notMerged = error.detail.find("not fully merged") != std::string::npos;
        if (notMerged && !request_.force) {
            outcome.choices.push_back(
                {OperationChoice::Kind::ForceDiscard,
                 "Delete anyway",
                 "This branch has commits that are not merged anywhere else. After deleting, they "
                 "are only reachable through the reflog.",
                 true});
            outcome.choices.push_back(
                {OperationChoice::Kind::Abort, "Cancel", "Keep the branch.", false});
        }

        // A branch checked out in another worktree cannot be deleted; git names
        // the worktree in its message, which is the useful part to surface.
        if (error.detail.find("used by worktree") != std::string::npos) {
            outcome.summary = "This branch is checked out in another worktree";
        }

        outcome.error = std::move(error);
        return outcome;
    }

private:
    std::string joinNames() const {
        std::string joined;
        for (std::size_t i = 0; i < request_.names.size(); ++i) {
            if (i > 0) {
                joined += ", ";
            }
            joined += request_.names[i];
        }
        return joined;
    }

    DeleteBranchRequest request_;
};

}  // namespace

std::unique_ptr<Operation> makeCreateBranchOperation(CreateBranchRequest request) {
    return std::make_unique<CreateBranchOperation>(std::move(request));
}

std::unique_ptr<Operation> makeRenameBranchOperation(RenameBranchRequest request) {
    return std::make_unique<RenameBranchOperation>(std::move(request));
}

std::unique_ptr<Operation> makeDeleteBranchOperation(DeleteBranchRequest request) {
    return std::make_unique<DeleteBranchOperation>(std::move(request));
}

}  // namespace gbm
