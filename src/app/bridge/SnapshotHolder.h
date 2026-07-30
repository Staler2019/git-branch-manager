#pragma once

#include <memory>
#include <mutex>

namespace gbm {

/// Holds the current immutable snapshot of something expensive.
///
/// This is the mechanism behind the architecture's second invariant: workers build
/// an immutable object and *publish* it here; the UI thread only ever reads the
/// current pointer. Nothing is mutated in place, so painting never takes a lock on
/// data a worker might be writing, and a superseded snapshot stays alive until the
/// last frame referencing it finishes.
///
/// `std::atomic<std::shared_ptr<T>>` would be ideal, but it is C++20 library
/// support that is uneven in practice, so a tiny mutex around a pointer copy is
/// used instead. The critical section is a refcount increment.
template <class T>
class SnapshotHolder {
public:
    using Ptr = std::shared_ptr<const T>;

    void publish(Ptr snapshot) {
        std::lock_guard<std::mutex> lock(mutex_);
        current_ = std::move(snapshot);
    }

    /// Returns the current snapshot. Callers hold their own reference, so it stays
    /// valid for as long as they need it even if a newer one is published.
    Ptr current() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return current_;
    }

    void clear() {
        std::lock_guard<std::mutex> lock(mutex_);
        current_.reset();
    }

    bool empty() const {
        std::lock_guard<std::mutex> lock(mutex_);
        return current_ == nullptr;
    }

private:
    mutable std::mutex mutex_;
    Ptr current_;
};

}  // namespace gbm
