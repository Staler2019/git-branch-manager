#pragma once

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>
#include <utility>
#include <vector>

namespace gbm {

/// A single git invocation.
///
/// `args` is always an argv vector — never a shell string. That removes an
/// entire class of quoting bugs (branch names with spaces, paths with quotes)
/// and means no shell is ever involved, so nothing can be injected through a
/// ref name.
struct GitCommand {
    std::filesystem::path repoDir;  ///< Passed as `-C <dir>`; may be empty.
    std::vector<std::string> args;  ///< argv after the executable itself.
    std::vector<std::pair<std::string, std::string>> envOverrides;
    std::optional<std::string> stdinData;

    /// 0 means no timeout. Network operations must use 0 and rely on
    /// cancellation instead: a fetch of a 500 MB repository on a slow link is
    /// slow, not broken, and killing it would be wrong.
    std::chrono::milliseconds timeout{0};

    bool mergeStderrIntoStdout = false;

    /// Windows: pass CREATE_NO_WINDOW. Without it a console window flashes on
    /// every single git call, which is unusable in a GUI.
    bool noWindow = true;

    GitCommand() = default;

    GitCommand(std::filesystem::path dir, std::vector<std::string> arguments)
        : repoDir(std::move(dir)), args(std::move(arguments)) {}

    /// Global flags applied to every invocation.
    ///
    /// `core.quotepath=false` stops git from octal-escaping non-ASCII paths, so
    /// UTF-8 filenames survive round-tripping. The pager and terminal prompt are
    /// disabled because there is no terminal to drive them, and a prompt would
    /// hang the child forever instead of returning an auth error we can report.
    ///
    /// `--no-optional-locks` is the fix for issue #77, and it is here rather
    /// than on individual read commands on purpose. Reads and writes run on
    /// *different* thread pools: writes are serialised by OperationRunner's
    /// single worker, but Session::refreshWorkingCopy() and every other
    /// background read post to sharedReadPool(), which is not serialised
    /// against it. A plain `git status` or `git diff` rewrites the index
    /// whenever its cached stat info has gone stale, and rewriting means
    /// taking `.git/index.lock` -- so a background refresh could take the
    /// lock out from under a real user operation, which then failed with
    /// GitError::Code::LockHeld ("Another Git process appears to be running
    /// in this repository"). This flag is git's own answer for GUI clients
    /// in exactly that position (git 2.15+, equivalent to
    /// GIT_OPTIONAL_LOCKS=0): it suppresses only *opportunistic* locking, so
    /// commands that genuinely must write the index -- add, apply --cached,
    /// commit, checkout -- still take their required lock and behave
    /// identically.
    ///
    /// Applying it to every invocation rather than tagging the ~28
    /// sharedReadPool() call sites individually is deliberate: a new read
    /// command added later cannot forget to opt in, which is the drift this
    /// repo's audits keep finding. The cost is that the index's stat cache is
    /// no longer refreshed as a side effect of a status read, so a later
    /// status may re-stat more files; that is the documented trade-off git
    /// itself names for this flag.
    static std::vector<std::string> globalFlags() {
        return {
            "-c",
            "core.quotepath=false",
            "-c",
            "color.ui=false",
            "-c",
            "advice.detachedHead=false",
            "--no-pager",
            "--no-optional-locks",
        };
    }
};

struct ProcessResult {
    int exitCode = 0;
    std::string out;
    std::string err;
    std::chrono::milliseconds duration{0};
    bool timedOut = false;
    bool cancelled = false;

    bool succeeded() const noexcept { return exitCode == 0 && !timedOut && !cancelled; }
};

}  // namespace gbm
