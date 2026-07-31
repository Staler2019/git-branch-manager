#include "core/git/ops/BisectOps.h"

#include <filesystem>
#include <optional>
#include <string_view>
#include <system_error>
#include <utility>

namespace gbm {

namespace {

std::string trimTrailingWhitespace(std::string text) {
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r' || text.back() == ' ')) {
        text.pop_back();
    }
    return text;
}

/// `git bisect`'s subcommands are chatty on stdout (the next candidate, or the
/// concluding "is the first bad commit" message), and that text is the whole
/// point of the operation from the user's point of view, so it becomes the
/// summary whenever there is any -- unlike most other ops, where `describe()`
/// alone is enough.
std::string summaryOrDescribe(const std::string& stdOut, const std::string& fallback) {
    const std::string trimmed = trimTrailingWhitespace(stdOut);
    return trimmed.empty() ? fallback : trimmed;
}

class BisectStartOperation final : public Operation {
public:
    explicit BisectStartOperation(BisectStartRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Start bisect"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"bisect", "start"};
        if (request_.noCheckout) {
            args.emplace_back("--no-checkout");
        }
        if (!request_.badRef.empty()) {
            args.push_back(request_.badRef);
        }
        for (const auto& good : request_.goodRefs) {
            args.push_back(good);
        }
        if (!request_.paths.empty()) {
            args.emplace_back("--");
            for (const auto& path : request_.paths) {
                args.push_back(path);
            }
        }

        GitCommand command(paths.commandDir(), std::move(args));
        // May check out the first candidate immediately when bad/good are
        // both given up front, exactly like an ordinary checkout.
        command.timeout = std::chrono::milliseconds(0);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = summaryOrDescribe(result->out, describe());
        return outcome;
    }

private:
    BisectStartRequest request_;
};

class BisectMarkOperation final : public Operation {
public:
    explicit BisectMarkOperation(BisectMarkRequest request) : request_(std::move(request)) {}

    std::string describe() const override {
        std::string label = request_.good ? "Mark good" : "Mark bad";
        if (!request_.ref.empty()) {
            label += " " + request_.ref;
        }
        return label;
    }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"bisect", request_.good ? "good" : "bad"};
        if (!request_.ref.empty()) {
            args.push_back(request_.ref);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        // Checks out the next candidate (or concludes and checks out the
        // result), so this is exactly as unbounded as an ordinary checkout.
        command.timeout = std::chrono::milliseconds(0);

        auto result = runner.run(command, token);
        if (!result) {
            outcome.error = std::move(result).error();
            outcome.summary = outcome.error->message;
            return outcome;
        }
        outcome.succeeded = true;
        outcome.summary = summaryOrDescribe(result->out, describe());
        return outcome;
    }

private:
    BisectMarkRequest request_;
};

class BisectSkipOperation final : public Operation {
public:
    explicit BisectSkipOperation(BisectSkipRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "Skip commit"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"bisect", "skip"};
        for (const auto& ref : request_.refs) {
            args.push_back(ref);
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
        outcome.summary = summaryOrDescribe(result->out, describe());
        return outcome;
    }

private:
    BisectSkipRequest request_;
};

class BisectResetOperation final : public Operation {
public:
    explicit BisectResetOperation(BisectResetRequest request) : request_(std::move(request)) {}

    std::string describe() const override { return "End bisect"; }

    OperationOutcome run(IProcessRunner& runner,
                         const RepoPaths& paths,
                         CancellationToken token) override {
        OperationOutcome outcome;
        std::vector<std::string> args{"bisect", "reset"};
        if (!request_.target.empty()) {
            args.push_back(request_.target);
        }

        GitCommand command(paths.commandDir(), std::move(args));
        command.timeout = std::chrono::milliseconds(0);  // restores the work tree.

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
    BisectResetRequest request_;
};

}  // namespace

BisectStore::BisectStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<BisectStatus> BisectStore::status(CancellationToken token) {
    BisectStatus result;

    std::error_code ec;
    result.active = std::filesystem::exists(paths_.bisectLogFile(), ec);
    if (!result.active) {
        return result;
    }

    GitCommand logCmd(paths_.commandDir(), {"bisect", "log"});
    logCmd.timeout = std::chrono::seconds(30);
    auto logResult = runner_.run(logCmd, token);
    if (!logResult) {
        return fail(std::move(logResult).error());
    }
    result.logText = logResult->out;

    // Every mark -- whether given directly to `bisect start <bad> <good>` or
    // made afterward with a separate `bisect good`/`bad`/`skip` -- gets a
    // "# bad: [oid] subject" / "# good: [...]" / "# skip: [...]" comment line
    // in the log, unlike the "git bisect good <oid>" action line, which only
    // appears for marks made after start. The comment form is therefore the
    // one reliable source for both cases. `good` and `skip` accumulate one
    // entry per commit ever marked that way; `bad` is overwritten by each new
    // line, which is exactly the narrowest bad boundary known so far.
    auto extractBracketedOid = [](std::string_view line,
                                  std::string_view prefix) -> std::optional<std::string> {
        if (!line.starts_with(prefix)) {
            return std::nullopt;
        }
        const std::string_view rest = line.substr(prefix.size());
        const std::size_t close = rest.find(']');
        if (close == std::string_view::npos) {
            return std::nullopt;
        }
        return std::string(rest.substr(0, close));
    };

    std::size_t start = 0;
    while (start <= result.logText.size()) {
        const std::size_t at = result.logText.find('\n', start);
        const std::string_view line(result.logText.data() + start,
                                    (at == std::string::npos ? result.logText.size() : at) - start);
        if (auto badOid = extractBracketedOid(line, "# bad: [")) {
            result.badOid = *badOid;
        } else if (auto goodOid = extractBracketedOid(line, "# good: [")) {
            result.goodOids.push_back(*goodOid);
        } else if (auto skippedOid = extractBracketedOid(line, "# skip: [")) {
            result.skippedOids.push_back(*skippedOid);
        }
        if (at == std::string::npos) {
            break;
        }
        start = at + 1;
    }

    GitCommand headCmd(paths_.commandDir(), {"rev-parse", "HEAD"});
    headCmd.timeout = std::chrono::seconds(10);
    if (auto headResult = runner_.run(headCmd, token)) {
        result.currentOid = headResult->out;
    }

    return result;
}

std::unique_ptr<Operation> makeBisectStartOperation(BisectStartRequest request) {
    return std::make_unique<BisectStartOperation>(std::move(request));
}

std::unique_ptr<Operation> makeBisectMarkOperation(BisectMarkRequest request) {
    return std::make_unique<BisectMarkOperation>(std::move(request));
}

std::unique_ptr<Operation> makeBisectSkipOperation(BisectSkipRequest request) {
    return std::make_unique<BisectSkipOperation>(std::move(request));
}

std::unique_ptr<Operation> makeBisectResetOperation(BisectResetRequest request) {
    return std::make_unique<BisectResetOperation>(std::move(request));
}

}  // namespace gbm
