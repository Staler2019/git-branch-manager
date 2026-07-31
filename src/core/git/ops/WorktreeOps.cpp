#include "core/git/ops/WorktreeOps.h"

#include "core/base/FsUtil.h"
#include "core/git/RefStore.h"

#include <utility>

namespace gbm {

namespace {

/// Splits `git worktree list --porcelain` into per-worktree line groups. Each
/// entry starts with a `worktree <path>` line and ends at the next one (or
/// EOF); blank lines are separators, not part of any entry.
std::vector<std::vector<std::string_view>> splitEntries(std::string_view text) {
    std::vector<std::vector<std::string_view>> entries;
    std::size_t start = 0;
    while (start <= text.size()) {
        const std::size_t at = text.find('\n', start);
        const std::string_view line =
            text.substr(start, (at == std::string_view::npos ? text.size() : at) - start);
        if (line.rfind("worktree ", 0) == 0) {
            entries.emplace_back();
        }
        if (!line.empty() && !entries.empty()) {
            entries.back().push_back(line);
        }
        if (at == std::string_view::npos) {
            break;
        }
        start = at + 1;
    }
    return entries;
}

WorktreeInfo parseEntry(const std::vector<std::string_view>& lines,
                        const std::filesystem::path& mainWorkDir) {
    WorktreeInfo info;
    for (std::string_view line : lines) {
        if (line.rfind("worktree ", 0) == 0) {
            info.path = std::filesystem::path(std::string(line.substr(9)));
        } else if (line.rfind("HEAD ", 0) == 0) {
            info.headOid = std::string(line.substr(5));
        } else if (line.rfind("branch ", 0) == 0) {
            std::string ref(line.substr(7));
            const std::string_view prefix = "refs/heads/";
            if (ref.rfind(prefix, 0) == 0) {
                ref = ref.substr(prefix.size());
            }
            info.branch = ref;
        } else if (line == "bare") {
            info.isBare = true;
        } else if (line == "detached") {
            info.isDetached = true;
        } else if (line.rfind("locked", 0) == 0) {
            info.isLocked = true;
            if (line.size() > 7 && line[6] == ' ') {
                info.lockReason = std::string(line.substr(7));
            }
        } else if (line.rfind("prunable", 0) == 0) {
            info.isPrunable = true;
            if (line.size() > 9 && line[8] == ' ') {
                info.prunableReason = std::string(line.substr(9));
            }
        }
    }
    if (!mainWorkDir.empty() && !info.path.empty()) {
        info.isMain = fsutil::pathsEquivalent(info.path.lexically_normal().generic_string(),
                                              mainWorkDir.lexically_normal().generic_string());
    }
    return info;
}

class AddWorktreeOperation final : public Operation {
public:
    explicit AddWorktreeOperation(AddWorktreeRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Add worktree at " + request_.path.string(); }

    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.path.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "No worktree path given");
            return outcome;
        }
        if (request_.createBranch && !RefStore::isValidBranchName(request_.newBranchName)) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument,
                         "\"" + request_.newBranchName + "\" is not a valid branch name");
            return outcome;
        }

        std::vector<std::string> args{"worktree", "add"};
        if (request_.force) {
            args.emplace_back("--force");
        }
        if (request_.createBranch) {
            args.emplace_back("-b");
            args.push_back(request_.newBranchName);
        } else if (request_.detach) {
            args.emplace_back("--detach");
        }
        args.push_back(request_.path.string());
        if (!request_.branch.empty()) {
            args.push_back(request_.branch);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Added worktree at " + request_.path.string();
        return outcome;
    }

private:
    AddWorktreeRequest request_;
};

class RemoveWorktreeOperation final : public Operation {
public:
    explicit RemoveWorktreeOperation(RemoveWorktreeRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Remove worktree " + request_.path.string(); }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"worktree", "remove"};
        if (request_.force) {
            args.emplace_back("--force");
        }
        args.push_back(request_.path.string());

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(120);
        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary = "Removed worktree " + request_.path.string();
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        const bool dirtyOrLocked = error.detail.find("is dirty") != std::string::npos ||
                                   error.detail.find("locked working tree") != std::string::npos ||
                                   error.detail.find("contains modified") != std::string::npos;
        if (dirtyOrLocked && !request_.force) {
            outcome.choices.push_back(
                {OperationChoice::Kind::ForceDiscard,
                 "Remove anyway",
                 "Any uncommitted changes in this worktree are permanently lost.",
                 true});
            outcome.choices.push_back(
                {OperationChoice::Kind::Abort, "Cancel", "Leave the worktree in place.", false});
        }
        outcome.error = std::move(error);
        return outcome;
    }

private:
    RemoveWorktreeRequest request_;
};

class PruneWorktreesOperation final : public Operation {
public:
    explicit PruneWorktreesOperation(PruneWorktreesRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Prune worktrees"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"worktree", "prune", "--verbose"};
        if (request_.dryRun) {
            args.emplace_back("--dry-run");
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
        outcome.summary = result->out.empty() ? "Nothing to prune" : result->out;
        return outcome;
    }

private:
    PruneWorktreesRequest request_;
};

class LockWorktreeOperation final : public Operation {
public:
    explicit LockWorktreeOperation(LockWorktreeRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Lock worktree " + request_.path.string(); }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"worktree", "lock"};
        if (!request_.reason.empty()) {
            args.emplace_back("--reason");
            args.push_back(request_.reason);
        }
        args.push_back(request_.path.string());

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(30);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Locked " + request_.path.string();
        return outcome;
    }

private:
    LockWorktreeRequest request_;
};

class UnlockWorktreeOperation final : public Operation {
public:
    explicit UnlockWorktreeOperation(UnlockWorktreeRequest request)
        : request_(std::move(request)) {}

    std::string describe() const override { return "Unlock worktree " + request_.path.string(); }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(paths.commandDir(), {"worktree", "unlock", request_.path.string()});
        command.timeout = std::chrono::seconds(30);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Unlocked " + request_.path.string();
        return outcome;
    }

private:
    UnlockWorktreeRequest request_;
};

class MoveWorktreeOperation final : public Operation {
public:
    explicit MoveWorktreeOperation(MoveWorktreeRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Move worktree to " + request_.to.string(); }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(paths.commandDir(),
                           {"worktree", "move", request_.from.string(), request_.to.string()});
        command.timeout = std::chrono::seconds(120);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Moved worktree to " + request_.to.string();
        return outcome;
    }

private:
    MoveWorktreeRequest request_;
};

}  // namespace

WorktreeStore::WorktreeStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<std::vector<WorktreeInfo>> WorktreeStore::list(CancellationToken token) {
    GitCommand command(paths_.commandDir(), {"worktree", "list", "--porcelain"});
    command.timeout = std::chrono::seconds(30);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    std::vector<WorktreeInfo> infos;
    for (const auto& entry : splitEntries(result->out)) {
        if (!entry.empty()) {
            infos.push_back(parseEntry(entry, paths_.workDir()));
        }
    }
    return infos;
}

std::unique_ptr<Operation> makeAddWorktreeOperation(AddWorktreeRequest request) {
    return std::make_unique<AddWorktreeOperation>(std::move(request));
}

std::unique_ptr<Operation> makeRemoveWorktreeOperation(RemoveWorktreeRequest request) {
    return std::make_unique<RemoveWorktreeOperation>(std::move(request));
}

std::unique_ptr<Operation> makePruneWorktreesOperation(PruneWorktreesRequest request) {
    return std::make_unique<PruneWorktreesOperation>(std::move(request));
}

std::unique_ptr<Operation> makeLockWorktreeOperation(LockWorktreeRequest request) {
    return std::make_unique<LockWorktreeOperation>(std::move(request));
}

std::unique_ptr<Operation> makeUnlockWorktreeOperation(UnlockWorktreeRequest request) {
    return std::make_unique<UnlockWorktreeOperation>(std::move(request));
}

std::unique_ptr<Operation> makeMoveWorktreeOperation(MoveWorktreeRequest request) {
    return std::make_unique<MoveWorktreeOperation>(std::move(request));
}

}  // namespace gbm
