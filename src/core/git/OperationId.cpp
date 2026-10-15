#include "core/git/OperationId.h"

#include <atomic>

namespace gbm {

std::uint64_t nextOperationId() {
    static std::atomic<std::uint64_t> next{1};
    return next.fetch_add(1);
}

namespace {
thread_local std::uint64_t tCurrentQueuedOperationId = 0;
}  // namespace

std::uint64_t nextQueuedOperationId() {
    static std::atomic<std::uint64_t> next{1};
    return next.fetch_add(1);
}

std::uint64_t currentQueuedOperationId() {
    return tCurrentQueuedOperationId;
}

QueuedOperationScope::QueuedOperationScope(std::uint64_t id) {
    tCurrentQueuedOperationId = id;
}

QueuedOperationScope::~QueuedOperationScope() {
    tCurrentQueuedOperationId = 0;
}

}  // namespace gbm
