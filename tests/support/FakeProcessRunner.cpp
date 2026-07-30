#include "support/FakeProcessRunner.h"

#include <algorithm>
#include <utility>

namespace gbm::testing {

namespace {

/// True when every token appears in argv, in order (not necessarily adjacent).
bool argvMatches(const std::vector<std::string>& argv, const std::vector<std::string>& tokens) {
    std::size_t cursor = 0;
    for (const std::string& token : tokens) {
        bool found = false;
        while (cursor < argv.size()) {
            if (argv[cursor].find(token) != std::string::npos) {
                found = true;
                ++cursor;
                break;
            }
            ++cursor;
        }
        if (!found) {
            return false;
        }
    }
    return true;
}

}  // namespace

void FakeProcessRunner::whenArgsContain(std::vector<std::string> argvContains, Response response) {
    rules_.push_back({std::move(argvContains), std::move(response)});
}

void FakeProcessRunner::setDefaultResponse(Response response) {
    defaultResponse_ = std::move(response);
}

std::vector<std::string> FakeProcessRunner::invokedArgs(std::size_t index) const {
    return index < invocations_.size() ? invocations_[index].args : std::vector<std::string>{};
}

void FakeProcessRunner::clear() {
    rules_.clear();
    invocations_.clear();
    defaultResponse_ = Response{};
}

const FakeProcessRunner::Response& FakeProcessRunner::responseFor(const GitCommand& command) const {
    for (const Rule& rule : rules_) {
        if (argvMatches(command.args, rule.tokens)) {
            return rule.response;
        }
    }
    return defaultResponse_;
}

GitResult<ProcessResult> FakeProcessRunner::run(const GitCommand& command,
                                                CancellationToken token) {
    invocations_.push_back(command);
    if (token.isCancelled()) {
        return cancelled();
    }

    const Response& response = responseFor(command);
    ProcessResult result;
    result.exitCode = response.exitCode;
    result.out = response.out;
    result.err = response.err;
    result.timedOut = response.timedOut;

    if (response.timedOut) {
        GitError error(GitError::Code::Timeout, "Git did not finish in time", response.err);
        error.argv = command.args;
        return fail(std::move(error));
    }
    if (response.exitCode != 0) {
        GitError error = classifyGitStderr(response.err, response.exitCode);
        error.argv = command.args;
        return fail(std::move(error));
    }
    return result;
}

GitResult<ProcessResult> FakeProcessRunner::stream(const GitCommand& command,
                                                   const LineSink& onLine,
                                                   const ProgressSink& onProgress,
                                                   CancellationToken token) {
    return streamSeparated(command, Separator::Newline, onLine, onProgress, token);
}

GitResult<ProcessResult> FakeProcessRunner::streamSeparated(const GitCommand& command,
                                                            Separator separator,
                                                            const LineSink& onLine,
                                                            const ProgressSink& onProgress,
                                                            CancellationToken token) {
    invocations_.push_back(command);
    if (token.isCancelled()) {
        return cancelled();
    }

    const Response& response = responseFor(command);
    if (response.timedOut) {
        GitError error(GitError::Code::Timeout, "Git did not finish in time", response.err);
        error.argv = command.args;
        return fail(std::move(error));
    }

    const char delimiter = separator == Separator::Nul ? '\0' : '\n';
    std::size_t emitted = 0;
    std::size_t start = 0;
    bool stoppedEarly = false;

    while (start <= response.out.size()) {
        const std::size_t at = response.out.find(delimiter, start);
        std::string_view record;
        if (at == std::string::npos) {
            if (start >= response.out.size()) {
                break;
            }
            record = std::string_view(response.out).substr(start);
            start = response.out.size() + 1;
        } else {
            record = std::string_view(response.out).substr(start, at - start);
            start = at + 1;
        }

        if (delimiter == '\n' && !record.empty() && record.back() == '\r') {
            record.remove_suffix(1);
        }
        if (onLine && !onLine(record)) {
            stoppedEarly = true;
            break;
        }
        ++emitted;
        if (response.truncateAfterRecords != 0 && emitted >= response.truncateAfterRecords) {
            // The child died mid-stream: records already delivered stay
            // delivered, and the caller sees a non-zero exit.
            stoppedEarly = true;
            break;
        }
    }

    if (onProgress && !response.err.empty()) {
        onProgress(response.err);
    }

    ProcessResult result;
    result.out = response.out;
    result.err = response.err;
    result.exitCode = response.truncateAfterRecords != 0 ? 143 : response.exitCode;

    if (result.exitCode != 0 && !stoppedEarly) {
        GitError error = classifyGitStderr(response.err, result.exitCode);
        error.argv = command.args;
        return fail(std::move(error));
    }
    return result;
}

}  // namespace gbm::testing
