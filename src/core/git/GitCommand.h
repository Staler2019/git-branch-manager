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
    ///
    /// It is not sufficient on its own. On a machine with `core.fsmonitor=true`
    /// a background work-tree-vs-index read still cost a concurrent user write
    /// its `.git/index.lock` -- reproducibly, with the creator never
    /// identified. `worktreeReadFlags()` below carries the measured fix and the
    /// evidence; every read of that shape must prepend it.
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

    /// Extra flags for a *background* read that compares the work tree against
    /// the index -- `git diff` with neither `--cached` nor a commit argument.
    /// Prepend these to `args`; git accepts `-c` anywhere before the
    /// subcommand, so `git <globalFlags> -C <dir> -c ... diff ...` is valid.
    ///
    /// This exists because of a regression measured, not reasoned about. Adding
    /// one such read to every working-copy status refresh (the unstaged
    /// `--numstat` pass that gives each file row its `+N -M` badge) made a user
    /// `git apply --cached` fail with GitError::Code::LockHeld -- git's own
    /// "Unable to create '.git/index.lock': File exists" -- on 9 of 12 runs of
    /// WorkingCopyApiTest.UnstageHunkReversesAFullyStagedSingleHunkFile. Three
    /// independent switches each take that to 0 of 12: dropping the pass,
    /// neutralising the machine's global git config, and this flag. The failure
    /// needs `core.fsmonitor=true`, which is a per-developer opt-in and is
    /// absent on CI -- so CI cannot see this, and neither could a reviewer
    /// reading the diff.
    ///
    /// **The process that creates the lock was never identified, and this
    /// comment does not pretend otherwise.** What was ruled out, each by direct
    /// observation rather than argument:
    ///   * git reads never create `.git/index.lock` at all. A tight poller that
    ///     positively catches `git add` taking it (8162 samples in one run) saw
    ///     zero for `status`, for both `--numstat` passes and for the `-U3`
    ///     work-tree diff -- warm fsmonitor daemon, cold daemon, stale stat
    ///     data and immediately after another process rewrote the index.
    ///   * So `--no-optional-locks` is doing its job, and the two candidate
    ///     mechanisms that would have explained everything are both dead: the
    ///     fsmonitor token is not a "required" index write, and `git diff`'s
    ///     end-of-run auto-refresh (`diff.autoRefreshIndex`) does not survive
    ///     `--no-optional-locks` either.
    ///   * At the instant of failure no git process except `fsmonitor--daemon`
    ///     was alive and the lock file was already gone.
    ///   * The app is not the creator: RepoState::read() only `stat()`s the
    ///     path, and working-copy writes really are serialised through
    ///     OperationRunner (one `apply` per operation; the run was checked).
    ///   * The race cannot be reproduced outside the app: 200 shell iterations
    ///     per reader, simultaneous and offset into the reader's tail, all
    ///     clean. Every observation technique -- GIT_TRACE2_EVENT, an exec
    ///     shim, even a shim doing one `write()` -- suppresses it completely,
    ///     which is why the holder was never caught in the act.
    ///
    /// Keep the flag off `globalFlags()` on purpose: applied globally it would
    /// also strip fsmonitor from `git status`, the command fsmonitor exists to
    /// accelerate, on precisely the machines whose owners opted into it. The
    /// cost here is that these two reads stat the work tree themselves instead
    /// of asking the daemon -- and the status read that just ran has already
    /// warmed that cache.
    ///
    /// If a later round identifies the holder, this becomes deletable. Until
    /// then, dropping it should reproduce the 9/12 above; see docs/ledger.md.
    static std::vector<std::string> worktreeReadFlags() { return {"-c", "core.fsmonitor=false"}; }
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
