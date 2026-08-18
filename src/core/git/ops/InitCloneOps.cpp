#include "core/git/ops/InitCloneOps.h"

#include "core/git/AskpassHelper.h"

#include <utility>

namespace gbm {

GitResult<void> runInitRepo(IProcessRunner& runner,
                            const InitRepoRequest& request,
                            CancellationToken token) {
    if (request.path.empty()) {
        return fail(GitError::Code::InvalidArgument, "A repository path is required");
    }

    GitCommand command;
    command.args = {"init", "--quiet", request.path.string()};
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

    GitCommand command;
    command.args = {"clone", "--quiet", request.url, request.destPath.string()};
    command.timeout = std::chrono::milliseconds(0);
    askpass::wire(command, request.askpassDir);

    auto result = runner.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }
    return {};
}

}  // namespace gbm
