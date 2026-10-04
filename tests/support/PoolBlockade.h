#pragma once

#include "core/workers/ThreadPool.h"

#include <atomic>
#include <chrono>
#include <cstddef>
#include <memory>
#include <thread>
#include <vector>

namespace gbm::testing {

/// Occupies `n` shared-read-pool workers, each independently releasable, so
/// a test can free exactly one worker at a time and get a fully
/// deterministic single-worker execution order. Freeing every worker at
/// once would let them race concurrently for whatever is queued, which is
/// exactly the ambiguity fix/refresh-ui-first-tiering C3's ordering claim
/// cannot tolerate.
class PoolBlockade {
public:
    explicit PoolBlockade(std::size_t n) : mayFinish_(n) {
        for (auto& flag : mayFinish_) flag = std::make_unique<std::atomic_bool>(false);
    }

    void fill(ThreadPool& pool) {
        for (auto& flag : mayFinish_) {
            std::atomic_bool* raw = flag.get();
            pool.post([this, raw] {
                started_.fetch_add(1);
                while (!raw->load()) {
                    std::this_thread::sleep_for(std::chrono::milliseconds(1));
                }
            });
        }
        while (started_.load() < mayFinish_.size()) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
        }
    }

    void releaseOne() { mayFinish_.front()->store(true); }

    void releaseRest() {
        for (std::size_t i = 1; i < mayFinish_.size(); ++i) {
            mayFinish_[i]->store(true);
        }
    }

private:
    std::atomic<std::size_t> started_{0};
    std::vector<std::unique_ptr<std::atomic_bool>> mayFinish_;
};

}  // namespace gbm::testing
