#include "support/GitCli.h"

#include "core/base/CancellationToken.h"
#include "core/git/GitCommand.h"
#include "core/git/GitExecutable.h"
#include "core/git/IProcessRunner.h"

#include <chrono>
#include <memory>

namespace gbm::testing {
namespace {

/// One detection and one runner per test binary. Detection spawns a
/// `git --version`, and the previous per-fixture arrangement paid for that
/// once per test rather than once per process.
struct Shared {
    std::filesystem::path executable;
    std::unique_ptr<IProcessRunner> runner;

    Shared() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            return;
        }
        executable = detected->executable;
        runner = makeProcessRunner(executable);
    }
};

Shared& shared() {
    // Function-local static: initialised once, thread-safely, on first use.
    static Shared instance;
    return instance;
}

}  // namespace

const std::filesystem::path& GitCli::executable() {
    return shared().executable;
}

GitCliResult GitCli::capture(const std::filesystem::path& repoDir, std::vector<std::string> args) {
    Shared& git = shared();
    if (git.runner == nullptr) {
        // No usable git. -1 is distinguishable from any real git exit code, so
        // a fixture that forgot to skip fails loudly instead of reading a
        // suspiciously empty result as success.
        return GitCliResult{-1, {}};
    }

    GitCommand command(repoDir, std::move(args));
    // Matches RealRepoTest's own budget. Fixture commands are local and fast;
    // this is only here so a wedged git cannot hang the whole suite.
    command.timeout = std::chrono::seconds(120);

    auto result = git.runner->run(command, CancellationToken{});
    if (result) {
        return GitCliResult{result->exitCode, std::move(result->out)};
    }
    // A non-zero exit arrives as a failed GitResult carrying git's exit code.
    // Fixtures assert on that code (`ASSERT_NE(..., 0)` for a ref that must not
    // exist, for instance), so it is passed through rather than flattened.
    const GitError& error = result.error();
    return GitCliResult{error.exitCode != 0 ? error.exitCode : -1, {}};
}

int GitCli::run(const std::filesystem::path& repoDir, std::vector<std::string> args) {
    return capture(repoDir, std::move(args)).exitCode;
}

}  // namespace gbm::testing
