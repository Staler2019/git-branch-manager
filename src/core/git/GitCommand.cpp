#include "core/git/GitCommand.h"

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

}  // namespace gbm
