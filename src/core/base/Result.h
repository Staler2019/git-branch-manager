#pragma once

// A minimal expected<T, E>. Git failures (conflict, lock held, auth failure,
// dirty work tree) are *expected control flow*, not programmer errors, so they
// travel as values rather than exceptions. Throwing across a worker-thread
// boundary into a Qt slot is a stability liability we refuse to take on.
//
// std::expected is C++23; our floor is C++20, so this is a small purpose-built
// substitute covering only what the codebase uses.

#include <cassert>
#include <optional>
#include <type_traits>
#include <utility>
#include <variant>

namespace gbm {

template <class E>
class Unexpected {
public:
    explicit Unexpected(E error) : error_(std::move(error)) {}

    const E& error() const& noexcept { return error_; }

    E&& error() && noexcept { return std::move(error_); }

private:
    E error_;
};

template <class E>
Unexpected<std::decay_t<E>> makeUnexpected(E&& e) {
    return Unexpected<std::decay_t<E>>(std::forward<E>(e));
}

/// Tag type used to give Result<void> a valid "success" state.
struct Void {};

template <class T, class E>
class Result {
public:
    using value_type = T;
    using error_type = E;

    Result() : storage_(T{}) {}

    Result(T value) : storage_(std::move(value)) {}  // NOLINT(google-explicit-constructor)

    Result(Unexpected<E> unexpected)  // NOLINT(google-explicit-constructor)
        : storage_(std::move(unexpected).error()) {}

    bool hasValue() const noexcept { return storage_.index() == 0; }

    explicit operator bool() const noexcept { return hasValue(); }

    const T& value() const& {
        assert(hasValue() && "Result::value() on an error");
        return std::get<0>(storage_);
    }

    T& value() & {
        assert(hasValue() && "Result::value() on an error");
        return std::get<0>(storage_);
    }

    T&& value() && {
        assert(hasValue() && "Result::value() on an error");
        return std::get<0>(std::move(storage_));
    }

    const T& operator*() const& { return value(); }

    T& operator*() & { return value(); }

    const T* operator->() const { return &value(); }

    T* operator->() { return &value(); }

    const E& error() const& {
        assert(!hasValue() && "Result::error() on a value");
        return std::get<1>(storage_);
    }

    E&& error() && {
        assert(!hasValue() && "Result::error() on a value");
        return std::get<1>(std::move(storage_));
    }

    template <class U>
    T valueOr(U&& fallback) const& {
        return hasValue() ? value() : static_cast<T>(std::forward<U>(fallback));
    }

private:
    std::variant<T, E> storage_;
};

/// Result<void, E> specialisation: carries only success/failure plus the error.
template <class E>
class Result<void, E> {
public:
    using value_type = void;
    using error_type = E;

    Result() = default;

    Result(Unexpected<E> unexpected)  // NOLINT(google-explicit-constructor)
        : error_(std::move(unexpected).error()) {}

    bool hasValue() const noexcept { return !error_.has_value(); }

    explicit operator bool() const noexcept { return hasValue(); }

    const E& error() const& {
        assert(!hasValue() && "Result::error() on a value");
        return *error_;
    }

    E&& error() && {
        assert(!hasValue() && "Result::error() on a value");
        return std::move(*error_);
    }

private:
    std::optional<E> error_;
};

}  // namespace gbm
