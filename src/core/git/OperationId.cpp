#include "core/git/OperationId.h"

#include <atomic>

namespace gbm {

std::uint64_t nextOperationId() {
    static std::atomic<std::uint64_t> next{1};
    return next.fetch_add(1);
}

}  // namespace gbm
