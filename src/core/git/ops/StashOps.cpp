#include "core/git/ops/StashOps.h"

#include <charconv>
#include <utility>

namespace gbm {

namespace {

/// Parses `stash@{N}` into N. Anything else (there is nothing else `%gd`
/// produces for the stash reflog) is reported as index 0 rather than crashing
/// a malformed row.
int parseStashIndex(std::string_view gd) {
    const auto open = gd.find('{');
    const auto close = gd.find('}', open);
    if (open == std::string_view::npos || close == std::string_view::npos) {
        return 0;
    }
    int value = 0;
    const std::string_view digits = gd.substr(open + 1, close - open - 1);
    std::from_chars(digits.data(), digits.data() + digits.size(), value);
    return value;
}

class StashSaveOperation final : public Operation {
public:
    explicit StashSaveOperation(StashSaveRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Stash changes"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"stash", "push"};
        if (!request_.message.empty()) {
            args.emplace_back("-m");
            args.push_back(request_.message);
        }
        if (request_.includeUntracked) {
            args.emplace_back("--include-untracked");
        }
        if (request_.keepIndex) {
            args.emplace_back("--keep-index");
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(600);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        // `git stash push` exits 0 and merely prints "No local changes to save"
        // when there is nothing to stash, so a zero exit code alone is not
        // success from this app's point of view.
        if (result->out.find("No local changes to save") != std::string::npos) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "There are no local changes to stash");
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Stashed changes";
        return outcome;
    }

private:
    StashSaveRequest request_;
};

class StashApplyOperation final : public Operation {
public:
    explicit StashApplyOperation(StashApplyRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return (request_.pop ? "Pop stash@{" : "Apply stash@{") + std::to_string(request_.index) +
               "}";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{
            "stash",
            request_.pop ? "pop" : "apply",
            "stash@{" + std::to_string(request_.index) + "}"};

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::seconds(120);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = request_.pop ? "Popped stash" : "Applied stash";
        return outcome;
    }

private:
    StashApplyRequest request_;
};

class StashDropOperation final : public Operation {
public:
    explicit StashDropOperation(StashDropRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return "Drop stash@{" + std::to_string(request_.index) + "}";
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(paths.commandDir(),
                           {"stash", "drop", "stash@{" + std::to_string(request_.index) + "}"});
        command.timeout = std::chrono::seconds(60);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Dropped stash";
        return outcome;
    }

private:
    StashDropRequest request_;
};

class StashBranchOperation final : public Operation {
public:
    explicit StashBranchOperation(StashBranchRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Create branch " + request_.branchName + " from stash"; }

    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(
            paths.commandDir(),
            {"stash", "branch", request_.branchName, "stash@{" + std::to_string(request_.index) + "}"});
        command.timeout = std::chrono::seconds(120);
        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = "Created " + request_.branchName + " from stash";
        return outcome;
    }

private:
    StashBranchRequest request_;
};

}  // namespace

StashStore::StashStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<std::vector<StashEntry>> StashStore::list(CancellationToken token) {
    GitCommand command(paths_.commandDir(), {"stash", "list", "--format=%gd%x09%H%x09%at%x09%gs"});
    command.timeout = std::chrono::seconds(30);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    std::vector<StashEntry> entries;
    std::size_t start = 0;
    while (start <= result->out.size()) {
        const std::size_t at = result->out.find('\n', start);
        const std::string_view line(result->out.data() + start,
                                    (at == std::string::npos ? result->out.size() : at) - start);
        if (!line.empty()) {
            StashEntry entry;
            std::size_t pos = 0;
            for (int col = 0; col < 4; ++col) {
                const std::size_t tab = line.find('\t', pos);
                const std::string_view value =
                    line.substr(pos, (tab == std::string_view::npos ? line.size() : tab) - pos);
                switch (col) {
                    case 0:
                        entry.index = parseStashIndex(value);
                        break;
                    case 1:
                        entry.oid = std::string(value);
                        break;
                    case 2: {
                        std::int64_t ts = 0;
                        std::from_chars(value.data(), value.data() + value.size(), ts);
                        entry.timestamp = ts;
                        break;
                    }
                    case 3:
                        entry.message = std::string(value);
                        break;
                }
                if (tab == std::string_view::npos) {
                    break;
                }
                pos = tab + 1;
            }
            entries.push_back(std::move(entry));
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return entries;
}

std::unique_ptr<Operation> makeStashSaveOperation(StashSaveRequest request) {
    return std::make_unique<StashSaveOperation>(std::move(request));
}

std::unique_ptr<Operation> makeStashApplyOperation(StashApplyRequest request) {
    return std::make_unique<StashApplyOperation>(std::move(request));
}

std::unique_ptr<Operation> makeStashDropOperation(StashDropRequest request) {
    return std::make_unique<StashDropOperation>(std::move(request));
}

std::unique_ptr<Operation> makeStashBranchOperation(StashBranchRequest request) {
    return std::make_unique<StashBranchOperation>(std::move(request));
}

}  // namespace gbm
