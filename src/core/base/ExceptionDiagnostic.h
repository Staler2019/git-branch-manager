#pragma once

#include <filesystem>
#include <functional>
#include <string>
#include <string_view>
#include <thread>
#include <typeinfo>
#include <utility>

namespace gbm {

/// A type's name for a report: code-chosen, so it holds no user text.
std::string typeName(const std::type_info& type);

/// The exception currently being handled as one line of text: dynamic type,
/// what(), error code and category, and any filesystem paths. Always valid UTF-8,
/// because it reaches Dart's strict decoder and MSVC's what() may be in the active
/// code page. Can throw only if it cannot allocate, so a caller on a noexcept path
/// catches it; with no active exception it says so.
std::string describeCurrentException();

/// For a catch site that swallows the exception: appends the description to
/// nativeErrorLogPath(), then sends it to the log sink and the native error sink.
/// Never throws.
void reportCurrentException(std::string_view where) noexcept;

/// For an error raised outside C++ (Dart's): `detail` goes to the file and the log sink,
/// `summary` to the native error sink as the caller wrote it, since only the caller knows
/// which of its error types carry data. Both are made valid UTF-8 and the summary is capped
/// like reportCurrentException's. Never throws.
void reportExternalError(std::string_view where,
                         std::string_view summary,
                         std::string_view detail) noexcept;

/// What the native error sink hears. All three are valid UTF-8. `summary` is for the
/// screen: at most 2 KiB, and a filesystem error gives only its type and code.
struct NativeErrorReport {
    std::string where;
    std::string summary;
    std::string logPath;
};

using NativeErrorSink = std::function<void(const NativeErrorReport&)>;

/// Replaces the sink; nullptr clears it. A sink runs under a lock on the reporting
/// thread, so this returning means the previous one is no longer running and its
/// captures can go. For the same reason a sink must not report. std::terminate never
/// calls it.
void setNativeErrorSink(NativeErrorSink sink);

/// `gbm-native-errors.log` under %LOCALAPPDATA%\\GitBranchManager\\logs,
/// ~/Library/Logs/GitBranchManager or $XDG_STATE_HOME (~/.local/state)/gitbranchmanager;
/// GBM_NATIVE_ERROR_LOG_DIR overrides it. Empty when none resolves, and then nothing
/// is written. No log sink is installed in a release build and a Windows GUI app has
/// no stderr, so this file is what a bug report can attach. Past 1 MiB it becomes
/// `.1`, replacing the previous one.
std::filesystem::path nativeErrorLogPath();

/// std::terminate writes the description to the log file and stderr before
/// aborting. MSVC keeps the handler per thread, so guardedThread installs it on
/// each one; the guards at thread and C API entries leave it as the last resort
/// for what they cannot catch, such as a throw out of a noexcept.
void installTerminateHandler() noexcept;

/// The only way this tree starts a thread. A thread entry has no caller, so an
/// exception leaving it is std::terminate with no message. `onException` runs
/// inside the handler, so it can call describeCurrentException(), and is where a
/// thread with a waiter reports the failure. check-native-exception-guards.py
/// refuses a bare std::thread.
template <typename Body, typename OnException>
std::thread guardedThread(std::string name, Body body, OnException onException) {
    return std::thread([name = std::move(name),
                        body = std::move(body),
                        onException = std::move(onException)]() mutable {
        installTerminateHandler();
        try {
            body();
        } catch (...) {
            reportCurrentException(name);
            try {
                onException();
            } catch (...) {
                reportCurrentException(name + " exception handler");
            }
        }
    });
}

template <typename Body>
std::thread guardedThread(std::string name, Body body) {
    return guardedThread(std::move(name), std::move(body), [] {});
}

}  // namespace gbm
