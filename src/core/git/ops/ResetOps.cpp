#include "core/git/ops/ResetOps.h"

#include <utility>

namespace gbm {

namespace {

class ResetOperation final : public Operation {
public:
    explicit ResetOperation(ResetRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        const char* label = request_.mode == ResetMode::Soft   ? "Soft reset to "
                            : request_.mode == ResetMode::Hard ? "Hard reset to "
                                                               : "Reset to ";
        return label + (request_.target.empty() ? "HEAD" : request_.target);
    }

    /// A hard reset rewrites the whole work tree; interrupting it part-way would
    /// leave files in an unknown mix of old and new, exactly like a checkout.
    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        std::vector<std::string> args{"reset"};
        switch (request_.mode) {
            case ResetMode::Soft:
                args.emplace_back("--soft");
                break;
            case ResetMode::Mixed:
                args.emplace_back("--mixed");
                break;
            case ResetMode::Hard:
                args.emplace_back("--hard");
                break;
        }
        if (!request_.target.empty()) {
            args.push_back(request_.target);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        // A hard reset over a very large tree can legitimately take a while;
        // Cancel is the right control, not a timeout.
        command.timeout = request_.mode == ResetMode::Hard ? std::chrono::milliseconds(0)
                                                           : std::chrono::seconds(60);

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
    ResetRequest request_;
};

class RestoreOperation final : public Operation {
public:
    explicit RestoreOperation(RestoreRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        const std::string count = std::to_string(request_.paths.size());
        return request_.staged ? "Unstage " + count + " path(s)"
                               : "Discard changes to " + count + " path(s)";
    }

    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        if (request_.paths.empty()) {
            outcome.error =
                GitError(GitError::Code::InvalidArgument, "No paths selected to restore");
            return outcome;
        }

        std::vector<std::string> args{"restore"};
        if (request_.staged) {
            args.emplace_back("--staged");
        }
        if (!request_.source.empty()) {
            args.emplace_back("--source");
            args.push_back(request_.source);
        }
        args.emplace_back("--");
        for (const auto& path : request_.paths) {
            args.push_back(path);
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
        outcome.summary = describe();
        return outcome;
    }

private:
    RestoreRequest request_;
};

class CleanOperation final : public Operation {
public:
    explicit CleanOperation(CleanRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Remove untracked files"; }

    bool killableMidFlight() const override { return false; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;

        std::vector<std::string> args{"clean", "-f", "-d"};
        if (request_.includeIgnored) {
            args.emplace_back("-x");
        }
        if (!request_.paths.empty()) {
            args.emplace_back("--");
            for (const auto& path : request_.paths) {
                args.push_back(path);
            }
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
        outcome.summary = "Removed untracked files";
        return outcome;
    }

private:
    CleanRequest request_;
};

}  // namespace

CleanPreviewer::CleanPreviewer(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<std::vector<CleanEntry>> CleanPreviewer::preview(bool includeIgnored,
                                                           CancellationToken token) {
    std::vector<std::string> args{"clean", "-n", "-d"};
    if (includeIgnored) {
        args.emplace_back("-x");
    }
    GitCommand command(paths_.commandDir(), std::move(args));
    command.timeout = std::chrono::seconds(60);

    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }

    // Every line git clean -n prints is "Would remove <path>"; a nested repo it
    // refuses to touch is reported as "Would skip repository <path>" instead,
    // and is deliberately not listed here since a plain `-fd` will not remove it
    // either.
    static constexpr std::string_view kPrefix = "Would remove ";
    std::vector<CleanEntry> entries;
    std::size_t start = 0;
    while (start <= result->out.size()) {
        const std::size_t at = result->out.find('\n', start);
        const std::string_view line(result->out.data() + start,
                                    (at == std::string::npos ? result->out.size() : at) - start);
        if (line.starts_with(kPrefix)) {
            std::string_view rest = line.substr(kPrefix.size());
            CleanEntry entry;
            entry.isDirectory = !rest.empty() && rest.back() == '/';
            if (entry.isDirectory) {
                rest.remove_suffix(1);
            }
            entry.path = std::string(rest);
            entries.push_back(std::move(entry));
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }
    return entries;
}

std::unique_ptr<Operation> makeResetOperation(ResetRequest request) {
    return std::make_unique<ResetOperation>(std::move(request));
}

std::unique_ptr<Operation> makeRestoreOperation(RestoreRequest request) {
    return std::make_unique<RestoreOperation>(std::move(request));
}

std::unique_ptr<Operation> makeCleanOperation(CleanRequest request) {
    return std::make_unique<CleanOperation>(std::move(request));
}

}  // namespace gbm
