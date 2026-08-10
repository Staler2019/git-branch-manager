#pragma once

#include <functional>
#include <utility>

namespace gbm {

/// RAII guard for one unit of a reference-counted busy/spinner indicator.
/// Constructed with the callback that undoes whatever `setBusy(true)` (or
/// equivalent) the caller already did; that callback fires exactly once --
/// on an explicit reset(), on destruction, or (if neither happens first)
/// never, but never twice and never zero times for a token that was ever
/// non-empty. Move-only: a token cannot be duplicated into two places that
/// would each try to release it, so "this one busy unit" always has exactly
/// one owner.
///
/// The point is to make the early-return bugs that manual setBusy(true)/
/// setBusy(false) pairing invites structurally impossible: a function that
/// takes a BusyToken by value (or captures one into a lambda) releases it
/// automatically on every return path, including ones added later by
/// someone who never thinks about the busy indicator at all.
class BusyToken {
public:
    BusyToken() = default;

    explicit BusyToken(std::function<void()> release) : release_(std::move(release)) {}

    BusyToken(const BusyToken&) = delete;
    BusyToken& operator=(const BusyToken&) = delete;

    BusyToken(BusyToken&& other) noexcept : release_(std::move(other.release_)) {
        other.release_ = nullptr;
    }

    BusyToken& operator=(BusyToken&& other) noexcept {
        if (this != &other) {
            fire();
            release_ = std::move(other.release_);
            other.release_ = nullptr;
        }
        return *this;
    }

    ~BusyToken() { fire(); }

    /// True if this token still owns a release callback (i.e. destroying it
    /// now would actually do something).
    explicit operator bool() const noexcept { return static_cast<bool>(release_); }

    /// Releases early, without waiting for destruction. Safe to call at most
    /// once's worth of effect even if invoked from a moved-from or
    /// already-fired token -- both leave release_ null.
    void reset() { fire(); }

private:
    void fire() {
        if (release_) {
            std::function<void()> release = std::move(release_);
            release_ = nullptr;
            release();
        }
    }

    std::function<void()> release_;
};

}  // namespace gbm
