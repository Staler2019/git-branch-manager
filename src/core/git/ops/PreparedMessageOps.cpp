#include "core/git/ops/PreparedMessageOps.h"

#include "core/git/PreparedCommitMessage.h"

#include <chrono>
#include <utility>

namespace gbm {

PreparedMessageStore::PreparedMessageStore(IProcessRunner& runner, RepoPaths paths)
    : runner_(runner), paths_(std::move(paths)) {}

GitResult<std::string> PreparedMessageStore::read(CancellationToken token) {
    std::string prepared = readPreparedCommitMessage(paths_);
    if (prepared.empty()) {
        return std::string();
    }
    // On stdin rather than argv, for the same reason CommitOps sends the
    // message that way: an argv entry has a platform-dependent length limit,
    // and a squash of many commits is long.
    GitCommand command(paths_.commandDir(), {"stripspace", "--strip-comments"});
    command.stdinData = std::move(prepared);
    command.timeout = std::chrono::seconds(30);
    auto result = runner_.run(command, token);
    if (!result) {
        return fail(std::move(result).error());
    }
    return std::move(result->out);
}

}  // namespace gbm
