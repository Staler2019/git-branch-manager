#include "core/git/ops/InitCloneOps.h"

#include "core/base/FsUtil.h"
#include "core/git/AskpassHelper.h"

#include <optional>
#include <string>
#include <string_view>
#include <utility>

namespace gbm {

GitResult<void> runInitRepo(IProcessRunner& runner,
                            const InitRepoRequest& request,
                            CancellationToken token) {
    if (request.path.empty()) {
        return fail(GitError::Code::InvalidArgument, "A repository path is required");
    }

    GitCommand command;
    command.args = {"init", "--quiet"};
    if (!request.initialBranch.empty()) {
        GitCommand check;
        check.args = {"check-ref-format", "--branch", request.initialBranch};
        check.timeout = std::chrono::seconds(30);
        auto checked = runner.run(check, token);
        if (!checked) {
            // Only git's own "no" -- an exit code -- means the name is invalid;
            // a check that never answered (timed out, cancelled, never
            // started) is reported as what it was.
            if (checked.error().exitCode == 0) {
                return fail(std::move(checked).error());
            }
            return fail(GitError::Code::InvalidArgument,
                        "'" + request.initialBranch + "' is not a valid branch name");
        }
        // `--branch` expands `@{-N}` against the cwd's repository and prints
        // what it accepted; anything but the name itself was a shorthand.
        if (checked.value().out != request.initialBranch) {
            return fail(GitError::Code::InvalidArgument,
                        "'" + request.initialBranch + "' is not a valid branch name");
        }
        command.args.push_back("-b");
        command.args.push_back(request.initialBranch);
    }
    command.args.push_back(fsutil::utf8FromPath(request.path));
    command.timeout = std::chrono::seconds(30);

    auto result = runner.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }
    return {};
}

GitResult<void> runCloneRepo(IProcessRunner& runner,
                             const CloneRepoRequest& request,
                             CancellationToken token) {
    if (request.url.empty()) {
        return fail(GitError::Code::InvalidArgument, "A repository URL is required");
    }
    if (request.destPath.empty()) {
        return fail(GitError::Code::InvalidArgument, "A destination path is required");
    }

    if (request.url.front() == '-') {
        return fail(GitError::Code::InvalidArgument, "A repository URL cannot start with '-'");
    }
    if (request.depth < 0) {
        return fail(GitError::Code::InvalidArgument, "A clone depth cannot be negative");
    }

    // `--quiet` drops git's chatter but not its meter: withTransferProgress()
    // adds `--progress`, which wins over it (measured, git 2.56.0).
    GitCommand command;
    command.args = {"clone", "--quiet"};
    if (request.recurseSubmodules) {
        command.args.emplace_back("--recurse-submodules");
    }
    if (request.depth > 0) {
        command.args.emplace_back("--depth");
        command.args.push_back(std::to_string(request.depth));
    }
    command.args.emplace_back("--");
    command.args.push_back(request.url);
    command.args.push_back(fsutil::utf8FromPath(request.destPath));
    askpass::wire(command, request.askpassDir);

    const ProgressSink onChunk = [&request](std::string_view chunk) {
        if (!request.onProgress) {
            return;
        }
        if (const std::optional<TransferProgress> progress = parseTransferProgress(chunk)) {
            request.onProgress(*progress);
        }
    };
    auto result = runner.stream(command, [](std::string_view) { return true; }, onChunk, token);
    if (!result) {
        return fail(std::move(result).error());
    }
    return {};
}

}  // namespace gbm
