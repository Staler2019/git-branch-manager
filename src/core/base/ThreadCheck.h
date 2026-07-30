#pragma once

#include <thread>

namespace gbm {

/// Records which thread runs the UI event loop, so core entry points that touch
/// disk or spawn a process can assert they are *not* on it.
///
/// This assertion is the mechanism that keeps invariant #1 of the architecture
/// true over time. Without it, one innocuous-looking synchronous call added
/// months from now is all it takes for the app to start feeling laggy on a
/// 500k-commit repository, and the cause is very hard to find after the fact.
class UiThread {
public:
    static void markCurrentAsUi() { id() = std::this_thread::get_id(); }

    static bool isCurrent() { return id() == std::this_thread::get_id(); }

    static bool isRegistered() { return id() != std::thread::id{}; }

private:
    static std::thread::id& id() {
        static std::thread::id uiThreadId{};
        return uiThreadId;
    }
};

/// Aborts if called on the UI thread. Enabled in debug and in test builds; in
/// release it compiles away so a mistake degrades performance rather than
/// crashing a user's session.
void reportUiThreadViolation(const char* function, const char* file, int line);

#if defined(GBM_ENABLE_THREAD_CHECKS)
#define GBM_ASSERT_NOT_UI_THREAD()                                             \
    do {                                                                       \
        if (::gbm::UiThread::isRegistered() && ::gbm::UiThread::isCurrent()) { \
            ::gbm::reportUiThreadViolation(__func__, __FILE__, __LINE__);      \
        }                                                                      \
    } while (false)
#else
#define GBM_ASSERT_NOT_UI_THREAD() \
    do {                           \
    } while (false)
#endif

}  // namespace gbm
