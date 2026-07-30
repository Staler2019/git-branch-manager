#pragma once

#include "core/base/Result.h"

#include <string>
#include <string_view>
#include <vector>

namespace gbm {

/// Every failure that crosses a core API boundary. `detail` keeps git's stderr
/// verbatim and `argv` the exact command: the operation log renders both, which
/// is the difference between an actionable bug report and guesswork. We never
/// swallow stderr and never surface a bare error code as the primary message.
struct GitError {
    enum class Code {
        Unknown,
        NotFound,
        InvalidArgument,
        Conflict,
        LockHeld,
        Auth,
        HostKey,
        NonFastForward,
        DirtyWorkTree,
        HookRejected,
        Cancelled,
        ProcessFailed,
        SpawnFailed,
        ParseError,
        Corrupt,
        Unsupported,
        Timeout,
        TooLarge,
        Database,
        Io,
    };

    Code code = Code::Unknown;
    std::string message;            ///< Human-readable, safe to show in a toast.
    std::string detail;             ///< Raw stderr / underlying message, verbatim.
    std::vector<std::string> argv;  ///< Exact command line, for the operation log.
    int exitCode = 0;

    GitError() = default;

    GitError(Code c, std::string msg) : code(c), message(std::move(msg)) {}

    GitError(Code c, std::string msg, std::string det)
        : code(c), message(std::move(msg)), detail(std::move(det)) {}
};

std::string_view toString(GitError::Code code);

/// Maps a git stderr blob onto a specific code plus a human summary. Callers
/// that shell out route every non-zero exit through this so the UI can react to
/// "dirty work tree" or "lock held" instead of parsing text itself.
GitError classifyGitStderr(std::string_view stderrText, int exitCode);

template <class T>
using GitResult = Result<T, GitError>;

inline Unexpected<GitError> fail(GitError::Code code, std::string message) {
    return Unexpected<GitError>(GitError(code, std::move(message)));
}

inline Unexpected<GitError> fail(GitError::Code code, std::string message, std::string detail) {
    return Unexpected<GitError>(GitError(code, std::move(message), std::move(detail)));
}

inline Unexpected<GitError> fail(GitError error) {
    return Unexpected<GitError>(std::move(error));
}

inline Unexpected<GitError> cancelled() {
    return fail(GitError::Code::Cancelled, "Operation cancelled");
}

}  // namespace gbm
