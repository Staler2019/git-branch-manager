#pragma once

#include <filesystem>
#include <string>
#include <vector>

namespace gbm::testing {

/// Result of a fixture git command: git's own exit code plus its stdout.
struct GitCliResult {
    int exitCode = 0;
    /// Records joined by '\n' with no trailing separator, exactly as
    /// IProcessRunner::run() reassembles them.
    std::string out;
};

/// Runs a real git for test *fixtures* -- setting a repository up, and reading
/// it back to check what the code under test did to it.
///
/// This replaces the `std::system("git -C \"...\" ... >/dev/null 2>&1")` helper
/// that was copy-pasted into 26 capi test fixtures. Three reasons, in order of
/// how much they matter:
///
/// 1. **A shell is a second process.** `std::system()` runs `/bin/sh -c` on
///    POSIX and `cmd.exe /c` on Windows, so every fixture git command costs two
///    process creations rather than one. Windows pays roughly two orders of
///    magnitude more for process creation than Linux does, and the capi suite
///    issues ~900 fixture git commands -- see
///    docs/reports/windows-process-cost.md.
/// 2. **Quoting through a shell is a real, already-hit hazard.** Building a
///    command *string* means every argument has to survive a shell that differs
///    per platform. BranchApiTest carried a five-line comment about exactly
///    this: single quotes are POSIX syntax that `cmd.exe` passes through
///    literally, and unquoted `%(refname:short)` is a syntax error in dash
///    because of the parentheses. An argv vector has no such failure mode.
/// 3. **`std::system()` cannot capture stdout.** Fixtures that needed to read
///    git's output redirected it to a temp file and read that back. `capture()`
///    returns it directly.
///
/// The git binary is located once per test binary rather than once per fixture.
class GitCli {
public:
    /// Runs git in `repoDir` and returns its exit code, discarding output.
    /// Drop-in for the old `runGit()`: callers compare against 0.
    ///
    /// Note this is git's *actual* exit code. `std::system()` returned a POSIX
    /// wait status -- `exitCode << 8` -- so the old helper's non-zero values
    /// were never git's own. Every call site only ever compared against zero,
    /// so the change is compatible, and the value is now meaningful.
    static int run(const std::filesystem::path& repoDir, std::vector<std::string> args);

    /// As `run()`, but also returns stdout.
    static GitCliResult capture(const std::filesystem::path& repoDir,
                                std::vector<std::string> args);

    /// Absolute path of the git this class runs, or an empty path if none was
    /// found. Lets a fixture skip rather than fail when git is unavailable.
    static const std::filesystem::path& executable();
};

}  // namespace gbm::testing
