#include "core/git/ops/RemoteOps.h"

#include "core/git/AskpassHelper.h"

#include <algorithm>
#include <utility>

namespace gbm {

namespace {

class FetchOperation final : public Operation {
public:
    explicit FetchOperation(FetchRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return request_.remoteName.empty() ? "Fetch all remotes" : "Fetch " + request_.remoteName;
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"fetch"};
        if (request_.prune) {
            args.emplace_back("--prune");
        }
        if (request_.tags) {
            args.emplace_back("--tags");
        }
        if (request_.remoteName.empty()) {
            args.emplace_back("--all");
        } else {
            args.push_back(request_.remoteName);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
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
    FetchRequest request_;
};

class PullOperation final : public Operation {
public:
    explicit PullOperation(PullRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Pull"; }

    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        // Stashing first is a separate, recoverable step -- see CheckoutOp for
        // the same reasoning: if the pull then fails, the work is still safely
        // in a stash rather than lost.
        if (request_.stashFirst) {
            GitCommand stash(
                paths.commandDir(),
                {"stash", "push", "--include-untracked", "-m", "git-branch-manager: before pull"});
            stash.timeout = std::chrono::seconds(600);
            auto stashed = runner.run(stash, token);
            if (!stashed) {
                outcome.error = std::move(stashed).error();
                outcome.summary = "Could not stash your changes, so nothing was pulled";
                return outcome;
            }
        }

        std::vector<std::string> args{"pull"};
        if (request_.rebase) {
            args.emplace_back("--rebase");
        }
        if (!request_.remoteName.empty()) {
            args.push_back(request_.remoteName);
            if (!request_.branch.empty()) {
                args.push_back(request_.branch);
            }
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
        askpass::wire(command, request_.askpassDir);

        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary = "Pulled";
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        if (error.code == GitError::Code::DirtyWorkTree && !request_.stashFirst) {
            outcome.choices.push_back(
                {OperationChoice::Kind::StashAndRetry,
                 "Stash changes and pull",
                 "Your changes are saved to a stash first, and can be restored afterwards.",
                 false});
            outcome.choices.push_back(
                {OperationChoice::Kind::Abort, "Cancel", "Leave the working tree as it is.", false});
        }

        outcome.error = std::move(error);
        return outcome;
    }

private:
    PullRequest request_;
};

class PushOperation final : public Operation {
public:
    explicit PushOperation(PushRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return "Push" + (request_.remoteName.empty() ? std::string() : " to " + request_.remoteName);
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"push"};
        if (request_.force == PushForceMode::ForceWithLease) {
            args.emplace_back("--force-with-lease");
        }
        if (request_.setUpstream) {
            args.emplace_back("--set-upstream");
        }
        if (request_.pushTags) {
            args.emplace_back("--tags");
        }
        if (!request_.remoteName.empty()) {
            args.push_back(request_.remoteName);
            if (!request_.branch.empty()) {
                args.push_back(request_.branch);
            }
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
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
    PushRequest request_;
};

}  // namespace

RemoteStore::RemoteStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<std::vector<RemoteInfo>> RemoteStore::list(CancellationToken token) {
    GitCommand command(paths_.commandDir(), {"remote", "-v"});
    command.timeout = std::chrono::seconds(30);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    std::vector<RemoteInfo> remotes;
    std::size_t start = 0;
    while (start <= result->out.size()) {
        const std::size_t at = result->out.find('\n', start);
        const std::string_view line(result->out.data() + start,
                                    (at == std::string::npos ? result->out.size() : at) - start);
        if (!line.empty()) {
            // "<name>\t<url> (fetch|push)"
            const std::size_t tab = line.find('\t');
            const std::size_t space = line.rfind(" (");
            if (tab != std::string_view::npos && space != std::string_view::npos && space > tab) {
                const std::string name(line.substr(0, tab));
                const std::string url(line.substr(tab + 1, space - tab - 1));
                const bool isPush = line.substr(space).find("push") != std::string_view::npos;

                auto it = std::find_if(remotes.begin(), remotes.end(), [&name](const RemoteInfo& r) {
                    return r.name == name;
                });
                if (it == remotes.end()) {
                    remotes.push_back({name, {}, {}});
                    it = remotes.end() - 1;
                }
                (isPush ? it->pushUrl : it->fetchUrl) = url;
            }
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return remotes;
}

std::unique_ptr<Operation> makeFetchOperation(FetchRequest request) {
    return std::make_unique<FetchOperation>(std::move(request));
}

std::unique_ptr<Operation> makePullOperation(PullRequest request) {
    return std::make_unique<PullOperation>(std::move(request));
}

std::unique_ptr<Operation> makePushOperation(PushRequest request) {
    return std::make_unique<PushOperation>(std::move(request));
}

}  // namespace gbm
