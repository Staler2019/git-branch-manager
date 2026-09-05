#include "core/git/ops/LfsOps.h"

#include "core/git/AskpassHelper.h"

#include <utility>

namespace gbm {

namespace {

class LfsInstallOperation final : public Operation {
public:
    std::string describe() const override { return "Set up Git LFS for this repository"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        GitCommand command(paths.commandDir(), {"lfs", "install", "--local"});
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
};

class LfsTrackOperation final : public Operation {
public:
    explicit LfsTrackOperation(LfsTrackRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Track " + request_.pattern + " with LFS"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.pattern.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "A pattern is required");
            return outcome;
        }
        GitCommand command(paths.commandDir(), {"lfs", "track", request_.pattern});
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
    LfsTrackRequest request_;
};

class LfsUntrackOperation final : public Operation {
public:
    explicit LfsUntrackOperation(LfsUntrackRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Untrack " + request_.pattern + " from LFS"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        if (request_.pattern.empty()) {
            outcome.error = GitError(GitError::Code::InvalidArgument, "A pattern is required");
            return outcome;
        }
        GitCommand command(paths.commandDir(), {"lfs", "untrack", request_.pattern});
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
    LfsUntrackRequest request_;
};

class LfsPullOperation final : public Operation {
public:
    explicit LfsPullOperation(LfsTransferRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Pull LFS objects"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"lfs", "pull"};
        if (!request_.remoteName.empty()) {
            args.push_back(request_.remoteName);
        }
        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);
        command.idleTimeout = GitCommand::kHangCeiling;  // downloads objects; can be slow.
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
    LfsTransferRequest request_;
};

class LfsFetchOperation final : public Operation {
public:
    explicit LfsFetchOperation(LfsTransferRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Fetch LFS objects"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"lfs", "fetch"};
        if (!request_.remoteName.empty()) {
            args.push_back(request_.remoteName);
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
    LfsTransferRequest request_;
};

class LfsPruneOperation final : public Operation {
public:
    explicit LfsPruneOperation(LfsPruneRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Prune old LFS objects"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"lfs", "prune"};
        if (request_.dryRun) {
            args.emplace_back("--dry-run");
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
        outcome.summary = result->out.empty() ? describe() : result->out;
        return outcome;
    }

private:
    LfsPruneRequest request_;
};

}  // namespace

GitResult<LfsInstallation> detectLfs(IProcessRunner& runner,
                                     const RepoPaths& paths,
                                     CancellationToken token) {
    GitCommand command(paths.commandDir(), {"lfs", "version"});
    command.timeout = std::chrono::seconds(10);

    auto result = runner.run(command, token);
    LfsInstallation installation;
    if (result) {
        installation.available = true;
        installation.version = result->out;
    }
    return installation;
}

LfsStore::LfsStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<std::vector<std::string>> LfsStore::trackedPatterns(CancellationToken token) {
    GitCommand command(paths_.commandDir(), {"lfs", "track"});
    command.timeout = std::chrono::seconds(30);
    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    // "Listing tracked patterns\n    *.psd (.gitattributes)\n    ...\nListing
    // excluded patterns\n...": each tracked line is indented, and the pattern
    // is everything before the trailing " (<source file>)".
    std::vector<std::string> patterns;
    bool inTrackedSection = false;
    std::size_t start = 0;
    while (start <= result->out.size()) {
        const std::size_t at = result->out.find('\n', start);
        const std::string_view line(result->out.data() + start,
                                    (at == std::string::npos ? result->out.size() : at) - start);
        if (line == "Listing tracked patterns") {
            inTrackedSection = true;
        } else if (line == "Listing excluded patterns") {
            inTrackedSection = false;
        } else if (inTrackedSection) {
            std::string_view trimmed = line;
            while (!trimmed.empty() && trimmed.front() == ' ') {
                trimmed.remove_prefix(1);
            }
            const std::size_t paren = trimmed.rfind(" (");
            if (!trimmed.empty() && paren != std::string_view::npos) {
                patterns.emplace_back(trimmed.substr(0, paren));
            }
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return patterns;
}

GitResult<std::vector<LfsFileInfo>> LfsStore::listFiles(CancellationToken token) {
    GitCommand command(paths_.commandDir(), {"lfs", "ls-files", "--long"});
    command.timeout = std::chrono::seconds(60);
    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    // Each line: "<sha256> <* or -> <path>". The marker is `*` when the real
    // content is present in local LFS storage, `-` when only the pointer is.
    std::vector<LfsFileInfo> files;
    std::size_t start = 0;
    while (start <= result->out.size()) {
        const std::size_t at = result->out.find('\n', start);
        const std::string_view line(result->out.data() + start,
                                    (at == std::string::npos ? result->out.size() : at) - start);
        const std::size_t firstSpace = line.find(' ');
        if (firstSpace != std::string_view::npos && firstSpace + 2 < line.size() &&
            line[firstSpace + 2] == ' ') {
            LfsFileInfo info;
            info.oid = std::string(line.substr(0, firstSpace));
            info.downloadedLocally = line[firstSpace + 1] == '*';
            info.path = std::string(line.substr(firstSpace + 3));
            files.push_back(std::move(info));
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return files;
}

std::unique_ptr<Operation> makeLfsInstallOperation() {
    return std::make_unique<LfsInstallOperation>();
}

std::unique_ptr<Operation> makeLfsTrackOperation(LfsTrackRequest request) {
    return std::make_unique<LfsTrackOperation>(std::move(request));
}

std::unique_ptr<Operation> makeLfsUntrackOperation(LfsUntrackRequest request) {
    return std::make_unique<LfsUntrackOperation>(std::move(request));
}

std::unique_ptr<Operation> makeLfsPullOperation(LfsTransferRequest request) {
    return std::make_unique<LfsPullOperation>(std::move(request));
}

std::unique_ptr<Operation> makeLfsFetchOperation(LfsTransferRequest request) {
    return std::make_unique<LfsFetchOperation>(std::move(request));
}

std::unique_ptr<Operation> makeLfsPruneOperation(LfsPruneRequest request) {
    return std::make_unique<LfsPruneOperation>(std::move(request));
}

}  // namespace gbm
