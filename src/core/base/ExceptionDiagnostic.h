#pragma once

#include <filesystem>
#include <string>
#include <string_view>

namespace gbm {

/// The exception currently being handled as one line of text: dynamic type,
/// what(), error code and category, and any filesystem paths. Always valid UTF-8,
/// because it reaches Dart's strict decoder and MSVC's what() may be in the active
/// code page. Never throws; with no active exception it says so.
std::string describeCurrentException();

/// For a catch site that swallows the exception: sends the description to the
/// log sink and appends it to nativeErrorLogPath(). Never throws.
void reportCurrentException(std::string_view where) noexcept;

/// `<temp>/gbm-native-errors.log`. No log sink is installed in a release build and
/// a Windows GUI app has no stderr, so this file is what a bug report can attach.
/// Started over once it passes 1 MiB.
std::filesystem::path nativeErrorLogPath();

/// std::terminate writes the description to the log file and stderr before
/// aborting. MSVC keeps the handler per thread, so a long-lived thread calls this
/// itself; the exception guards at thread and C API entries make the handler a
/// last resort for what they cannot catch, such as a throw out of a noexcept.
void installTerminateHandler() noexcept;

}  // namespace gbm
