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

    /// Lets Dart's PendingOperationTracker attribute this outcome back to the
    /// fetchRemote() call that produced it. Roughly thirty controller methods
    /// share the working-copy completion channel and OperationRunner's queue
    /// can hold more than one operation, so pairing "the next completion
    /// event" with "the fetch I just submitted" is wrong the moment anything
    /// else is submitted in between. describe() is not usable for this: it is
    /// a display string ("Fetch origin"), which is exactly the distinction
    /// Operation::kind() exists to draw.
    std::string kind() const override { return "fetch"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (!request_.refs.empty() && request_.remoteName.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument,
                                     "Fetching specific refs requires a remote name");
            return outcome;
        }

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
            for (const std::string& ref : request_.refs) {
                args.push_back(ref);
            }
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
        command.idleTimeout = GitCommand::kHangCeiling;
        askpass::wire(command, request_.askpassDir);

        auto result = runner.run(command, token);
        if (result) {
            outcome.succeeded = true;
            outcome.summary = "Pulled";
            return outcome;
        }

        GitError error = std::move(result).error();
        outcome.summary = error.message;

        // A dirty-work-tree failure used to push StashAndRetry/Abort choices
        // here -- see MergeOps.cpp's identical comment. Pull is the one case
        // where the gap is spec-visible rather than purely internal: `DLGS`
        // has a "Pull blocked" entry (three buttons, danger second, the same
        // shape as "Checkout blocked") that these choices would have backed,
        // but no Dart dialog was ever built to read them -- see
        // docs/rules/drift-open.md's [DRIFT-no-pull-dialog].

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
        std::string what = "Push";
        if (request_.branches.size() > 1) {
            what += " " + std::to_string(request_.branches.size()) + " branches";
        }
        return what + (request_.remoteName.empty() ? std::string() : " to " + request_.remoteName);
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
            for (const auto& branch : request_.branches) {
                if (!branch.empty()) {
                    args.push_back(branch);
                }
            }
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
    PushRequest request_;
};

class PruneRemoteOperation final : public Operation {
public:
    explicit PruneRemoteOperation(PruneRemoteRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        return request_.remoteName.empty() ? "Prune remote-tracking branches"
                                           : "Prune " + request_.remoteName;
    }

    /// Stamped so Dart can pair this outcome with the pruneRemote() call
    /// that produced it -- see Operation::kind() in OperationRunner.h. The
    /// gone-marking clears the pruned refs from its pending set on success,
    /// and describe()'s user-facing English is not a protocol.
    std::string kind() const override { return "prune-remote"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.refs.empty()) {
            outcome.succeeded = true;
            outcome.summary = "Nothing to prune";
            return outcome;
        }

        std::vector<std::string> args{"branch", "--delete", "--remotes"};
        for (const std::string& ref : request_.refs) {
            args.push_back(ref);
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
        outcome.summary = "Pruned " + std::to_string(request_.refs.size()) +
                          (request_.refs.size() == 1 ? " ref" : " refs");
        return outcome;
    }

private:
    PruneRemoteRequest request_;
};

class AddRemoteOperation final : public Operation {
public:
    explicit AddRemoteOperation(AddRemoteRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Add remote " + request_.name; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.name.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "Remote name is required");
            return outcome;
        }
        if (request_.url.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "Remote URL is required");
            return outcome;
        }

        GitCommand command(paths.commandDir(), {"remote", "add", request_.name, request_.url});
        command.timeout = std::chrono::seconds(30);
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
    AddRemoteRequest request_;
};

class RemoveRemoteOperation final : public Operation {
public:
    explicit RemoveRemoteOperation(RemoveRemoteRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Remove remote " + request_.name; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.name.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "Remote name is required");
            return outcome;
        }

        GitCommand command(paths.commandDir(), {"remote", "remove", request_.name});
        command.timeout = std::chrono::seconds(30);
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
    RemoveRemoteRequest request_;
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

                auto it = std::find_if(remotes.begin(),
                                       remotes.end(),
                                       [&name](const RemoteInfo& r) { return r.name == name; });
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

GitResult<std::vector<RemotePrunePreviewEntry>> RemoteStore::prunePreview(std::string remoteName,
                                                                          CancellationToken token) {
    if (remoteName.empty()) {
        return fail(GitError::Code::InvalidArgument, "No remote selected");
    }

    GitCommand command(paths_.commandDir(), {"remote", "prune", remoteName, "--dry-run"});
    command.timeout = std::chrono::seconds(30);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    constexpr std::string_view kMarker = "[would prune] ";
    std::vector<RemotePrunePreviewEntry> entries;
    std::size_t start = 0;
    const std::string& out = result->out;
    while (start <= out.size()) {
        const std::size_t at = out.find('\n', start);
        const std::string_view line(out.data() + start,
                                    (at == std::string::npos ? out.size() : at) - start);
        const std::size_t markerPos = line.find(kMarker);
        if (markerPos != std::string_view::npos) {
            std::string_view ref = line.substr(markerPos + kMarker.size());
            while (!ref.empty() && (ref.back() == '\r' || ref.back() == ' ')) {
                ref.remove_suffix(1);
            }
            if (!ref.empty()) {
                entries.push_back({std::string(ref)});
            }
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return entries;
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

std::unique_ptr<Operation> makePruneRemoteOperation(PruneRemoteRequest request) {
    return std::make_unique<PruneRemoteOperation>(std::move(request));
}

std::unique_ptr<Operation> makeAddRemoteOperation(AddRemoteRequest request) {
    return std::make_unique<AddRemoteOperation>(std::move(request));
}

std::unique_ptr<Operation> makeRemoveRemoteOperation(RemoveRemoteRequest request) {
    return std::make_unique<RemoveRemoteOperation>(std::move(request));
}

}  // namespace gbm
