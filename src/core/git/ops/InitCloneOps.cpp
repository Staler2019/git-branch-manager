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
    command.args = {"init", "--quiet", fsutil::utf8FromPath(request.path)};
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
