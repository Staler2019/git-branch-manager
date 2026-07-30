#pragma once

#include "core/git/IProcessRunner.h"

#include <functional>
#include <map>
#include <string>
#include <vector>

namespace gbm::testing {

/// Replays canned git output.
///
/// This is the reason `IProcessRunner` exists as an interface. With it, the whole
/// data layer is testable without a repository, and — more importantly — the
/// failure modes a real repository will not produce on demand become ordinary test
/// cases: output truncated mid-record, invalid UTF-8 in a path, a process killed
/// halfway through a stream, an exit code with empty stderr.
class FakeProcessRunner final : public IProcessRunner {
public:
    struct Response {
        int exitCode = 0;
        std::string out;
        std::string err;
        bool timedOut = false;
        /// Stops the stream after this many records, simulating a killed child.
        std::size_t truncateAfterRecords = 0;
    };

    /// Registers a response matched when every token in `argvContains` appears in
    /// the command's argv, in order.
    void whenArgsContain(std::vector<std::string> argvContains, Response response);

    /// Fallback used when nothing matches. Defaults to exit code 0 and no output.
    void setDefaultResponse(Response response);

    /// Every command that was run, in order. Assertions about *which* git command
    /// was issued matter as much as the parsed result: a plausible-looking value
    /// produced by the wrong command is a bug waiting to surface.
    const std::vector<GitCommand>& invocations() const { return invocations_; }

    std::vector<std::string> invokedArgs(std::size_t index) const;

    std::size_t invocationCount() const { return invocations_.size(); }

    void clear();

    GitResult<ProcessResult> run(const GitCommand& command, CancellationToken token) override;

    GitResult<ProcessResult> stream(const GitCommand& command,
                                    const LineSink& onLine,
                                    const ProgressSink& onProgress,
                                    CancellationToken token) override;

    GitResult<ProcessResult> streamSeparated(const GitCommand& command,
                                             Separator separator,
                                             const LineSink& onLine,
                                             const ProgressSink& onProgress,
                                             CancellationToken token) override;

private:
    struct Rule {
        std::vector<std::string> tokens;
        Response response;
    };

    const Response& responseFor(const GitCommand& command) const;

    std::vector<Rule> rules_;
    Response defaultResponse_;
    std::vector<GitCommand> invocations_;
};

}  // namespace gbm::testing
