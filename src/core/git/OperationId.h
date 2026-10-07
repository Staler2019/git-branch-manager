#pragma once

#include <cstdint>

namespace gbm {

/// The next `OperationRecord::id`, process-wide and never 0. Every producer of
/// operation records draws from this one sequence -- the process runner and
/// the `cat-file --batch` co-process -- so an id names one invocation however
/// many sessions and producers are live.
std::uint64_t nextOperationId();

}  // namespace gbm
