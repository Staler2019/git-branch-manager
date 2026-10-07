#include "core/git/GitCommand.h"

#include <algorithm>
#include <atomic>

namespace gbm {

namespace {

std::atomic<int>& multiplierStorage() {
    static std::atomic<int> multiplier{1};
    return multiplier;
}

}  // namespace

void setTimeoutMultiplier(int multiplier) {
    if (multiplier < 1) {
        return;
    }
    multiplierStorage().store(multiplier);
}

int timeoutMultiplier() {
    return multiplierStorage().load();
}

void resetTimeoutMultiplier() {
    multiplierStorage().store(1);
}

std::chrono::milliseconds scaledTimeout(std::chrono::milliseconds timeout) {
    return timeout * timeoutMultiplier();
}

namespace {

/// Whether this invocation moves data over the network. Decided here, from
/// argv, rather than by a flag at each call site: a call site that forgot the
/// flag would put a five-minute total on a fetch, and nothing would say so
/// until a large clone died at exactly 300 seconds.
bool isNetworkCommand(const GitCommand& command) {
    const auto& args = command.args;
    if (args.empty()) {
        return false;
    }
    const std::string& sub = args[0];
    if (sub == "fetch" || sub == "pull" || sub == "push" || sub == "clone" || sub == "ls-remote") {
        return true;
    }
    if (args.size() < 2) {
        return false;
    }
    if (sub == "submodule") {
        return args[1] == "update" || args[1] == "add";
    }
    if (sub == "lfs") {
        return args[1] == "fetch" || args[1] == "pull" || args[1] == "push";
    }
    return false;
}

}  // namespace

EffectiveDeadlines effectiveDeadlines(const GitCommand& command) {
    if (isNetworkCommand(command)) {
        return {std::chrono::milliseconds(0), GitCommand::kHangCeiling};
    }
    const std::chrono::milliseconds declared =
        command.timeout.count() == 0 ? GitCommand::kLocalCeiling
                                     : std::min(command.timeout, GitCommand::kLocalCeiling);
    return {scaledTimeout(declared), command.idleTimeout};
}

}  // namespace gbm
