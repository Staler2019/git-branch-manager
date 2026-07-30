#pragma once

#include "core/base/CancellationToken.h"
#include "core/base/Error.h"
#include "core/git/GitCommand.h"

#include <functional>
#include <memory>
#include <string_view>

namespace gbm {

/// Called for each output line as it arrives, on the worker thread. Returning
/// false asks the runner to stop reading and terminate the child, which is how a
/// history walk stops early once enough rows are in hand.
using LineSink = std::function<bool(std::string_view line)>;

/// Called with raw stderr chunks, for progress reporting ("Receiving objects…").
using ProgressSink = std::function<void(std::string_view chunk)>;

/// The single seam through which all git access flows.
///
/// Everything above this interface is testable without a real repository: the
/// fake implementation replays recorded output, including the failure modes a
/// live repo cannot reproduce on demand — truncated output, invalid UTF-8, and a
/// process killed mid-stream.
class IProcessRunner {
public:
    virtual ~IProcessRunner() = default;

    /// Runs to completion, buffering stdout and stderr.
    virtual GitResult<ProcessResult> run(const GitCommand& command, CancellationToken token) = 0;

    /// Streams stdout line by line so the caller can start work before the
    /// child exits. This is what makes time-to-first-paint independent of
    /// history size.
    virtual GitResult<ProcessResult> stream(const GitCommand& command,
                                            const LineSink& onLine,
                                            const ProgressSink& onProgress,
                                            CancellationToken token) = 0;

    /// Line separator used when splitting streamed output. NUL for commands
    /// invoked with `-z`.
    enum class Separator { Newline, Nul };

    virtual GitResult<ProcessResult> streamSeparated(const GitCommand& command,
                                                     Separator separator,
                                                     const LineSink& onLine,
                                                     const ProgressSink& onProgress,
                                                     CancellationToken token) = 0;
};

/// Constructs the real runner. `gitExecutable` must be an absolute path resolved
/// by GitExecutable::detect().
std::unique_ptr<IProcessRunner> makeProcessRunner(std::filesystem::path gitExecutable);

}  // namespace gbm
