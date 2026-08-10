#include "core/workers/ThreadPool.h"

#include "core/base/Logging.h"

#include <algorithm>
#include <utility>

namespace gbm {

std::size_t ThreadPool::defaultThreadCount() {
    const unsigned hardware = std::thread::hardware_concurrency();
    if (hardware <= 1) {
        return 2;
    }
    return std::clamp<std::size_t>(static_cast<std::size_t>(hardware) - 1, 2, 6);
}

ThreadPool::ThreadPool(std::string name, std::size_t threads) : name_(std::move(name)) {
    const std::size_t count = threads == 0 ? defaultThreadCount() : threads;
    workers_.reserve(count);
    for (std::size_t i = 0; i < count; ++i) {
        workers_.emplace_back([this] { workerLoop(); });
    }
}

ThreadPool::~ThreadPool() {
    shutdown();
}

void ThreadPool::post(std::function<void()> task) {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (stopping_) {
            return;
        }
        tasks_.push_back(std::move(task));
    }
    taskAvailable_.notify_one();
}

void ThreadPool::postFront(std::function<void()> task) {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (stopping_) {
            return;
        }
        tasks_.push_front(std::move(task));
    }
    taskAvailable_.notify_one();
}

std::size_t ThreadPool::queueDepth() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return tasks_.size();
}

void ThreadPool::drain() {
    std::unique_lock<std::mutex> lock(mutex_);
    idle_.wait(lock, [this] { return tasks_.empty() && activeTasks_ == 0; });
}

void ThreadPool::cancelQueuedAndDrain() {
    std::unique_lock<std::mutex> lock(mutex_);
    const std::size_t discarded = tasks_.size();
    const std::size_t stillRunning = activeTasks_;
    tasks_.clear();
    logMessage(LogLevel::Debug, name_ + " pool cancelQueuedAndDrain: discarded " +
                                     std::to_string(discarded) + " queued task(s), " +
                                     std::to_string(stillRunning) + " still running");
    idle_.wait(lock, [this] { return activeTasks_ == 0; });
}

void ThreadPool::shutdown() {
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (stopping_) {
            return;
        }
        stopping_ = true;
    }
    taskAvailable_.notify_all();
    for (auto& worker : workers_) {
        if (worker.joinable()) {
            worker.join();
        }
    }
    workers_.clear();
}

void ThreadPool::workerLoop() {
    for (;;) {
        std::function<void()> task;
        {
            std::unique_lock<std::mutex> lock(mutex_);
            taskAvailable_.wait(lock, [this] { return stopping_ || !tasks_.empty(); });
            if (stopping_ && tasks_.empty()) {
                return;
            }
            task = std::move(tasks_.front());
            tasks_.pop_front();
            ++activeTasks_;
        }

        // A task must never take down the process: a worker that throws would
        // otherwise terminate the app while the user is only browsing history.
        try {
            task();
        } catch (const std::exception& ex) {
            logMessage(LogLevel::Error,
                       "Unhandled exception in " + name_ + " worker: " + ex.what());
        } catch (...) {
            logMessage(LogLevel::Error, "Unhandled non-standard exception in " + name_ + " worker");
        }

        {
            std::lock_guard<std::mutex> lock(mutex_);
            --activeTasks_;
            if (tasks_.empty() && activeTasks_ == 0) {
                idle_.notify_all();
            }
        }
    }
}

}  // namespace gbm
