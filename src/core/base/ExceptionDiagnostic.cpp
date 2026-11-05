#include "core/base/ExceptionDiagnostic.h"

#include "core/base/FsUtil.h"
#include "core/base/Logging.h"

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <fstream>
#include <mutex>
#include <sstream>
#include <system_error>
#include <thread>
#include <typeinfo>

#if defined(__GNUG__)
#include <cxxabi.h>
#include <memory>
#endif

namespace gbm {

namespace {

constexpr std::uintmax_t kMaxLogBytes = 1024 * 1024;

std::string typeName(const std::type_info& type) {
#if defined(__GNUG__)
    int status = 0;
    const std::unique_ptr<char, decltype(&std::free)> demangled(
        abi::__cxa_demangle(type.name(), nullptr, nullptr, &status), &std::free);
    if (status == 0 && demangled != nullptr) {
        return demangled.get();
    }
#endif
    return type.name();
}

/// Length of the well-formed UTF-8 sequence at `index`, or 0 if there is none.
/// As strict as Dart's utf8.decode: no overlong forms, no surrogates, nothing
/// past U+10FFFF.
std::size_t utf8SequenceLength(std::string_view text, std::size_t index) {
    const auto at = [&](std::size_t i) { return static_cast<unsigned char>(text[i]); };
    const unsigned char lead = at(index);
    std::size_t length = 0;
    unsigned char low = 0x80;
    unsigned char high = 0xBF;
    if (lead <= 0x7F) {
        return 1;
    } else if (lead >= 0xC2 && lead <= 0xDF) {
        length = 2;
    } else if (lead >= 0xE0 && lead <= 0xEF) {
        length = 3;
        low = lead == 0xE0 ? 0xA0 : 0x80;
        high = lead == 0xED ? 0x9F : 0xBF;
    } else if (lead >= 0xF0 && lead <= 0xF4) {
        length = 4;
        low = lead == 0xF0 ? 0x90 : 0x80;
        high = lead == 0xF4 ? 0x8F : 0xBF;
    } else {
        return 0;
    }
    if (index + length > text.size() || at(index + 1) < low || at(index + 1) > high) {
        return 0;
    }
    for (std::size_t i = 2; i < length; ++i) {
        if (at(index + i) < 0x80 || at(index + i) > 0xBF) {
            return 0;
        }
    }
    return length;
}

/// A byte that is not part of well-formed UTF-8 becomes `?`.
std::string validUtf8(std::string_view text) {
    std::string out;
    out.reserve(text.size());
    std::size_t index = 0;
    while (index < text.size()) {
        const std::size_t length = utf8SequenceLength(text, index);
        if (length == 0) {
            out += '?';
            ++index;
        } else {
            out.append(text, index, length);
            index += length;
        }
    }
    return out;
}

std::string describeStandard(const std::exception& error) {
    return typeName(typeid(error)) + ": " + error.what();
}

std::string describeCode(const std::error_code& code) {
    return " [code=" + std::to_string(code.value()) + " category=" + code.category().name() + "]";
}

void appendToLog(std::string_view where, std::string_view description) {
    static std::mutex mutex;
    const std::lock_guard<std::mutex> lock(mutex);

    const std::filesystem::path path = nativeErrorLogPath();
    if (path.empty()) {
        return;
    }
    std::error_code ec;
    const std::uintmax_t size = std::filesystem::file_size(path, ec);
    const bool startOver = !ec && size > kMaxLogBytes;
    std::ofstream out(path, std::ios::binary | (startOver ? std::ios::trunc : std::ios::app));

    const auto now = std::chrono::system_clock::now().time_since_epoch();
    out << std::chrono::duration_cast<std::chrono::milliseconds>(now).count() << " thread "
        << std::this_thread::get_id() << " " << where << ": " << description << "\n";
}

[[noreturn]] void onTerminate() noexcept {
    static thread_local bool entered = false;
    if (!entered) {
        entered = true;
        try {
            const std::string description = describeCurrentException();
            appendToLog("std::terminate", description);
            std::fprintf(stderr, "gbm: fatal: std::terminate: %s\n", description.c_str());
        } catch (...) {
            std::fputs("gbm: fatal: std::terminate\n", stderr);
        }
    }
    std::abort();
}

}  // namespace

std::string describeCurrentException() {
    try {
        if (!std::current_exception()) {
            return "no active exception";
        }
        try {
            throw;
        } catch (const std::filesystem::filesystem_error& error) {
            // utf8FromPath, never path::string(): that can throw right here.
            return validUtf8(describeStandard(error) + describeCode(error.code()) + " path1=\"" +
                             fsutil::utf8FromPath(error.path1()) + "\" path2=\"" +
                             fsutil::utf8FromPath(error.path2()) + "\"");
        } catch (const std::system_error& error) {
            return validUtf8(describeStandard(error) + describeCode(error.code()));
        } catch (const std::exception& error) {
            return validUtf8(describeStandard(error));
        } catch (...) {
            return "non-standard exception";
        }
    } catch (...) {
        return "exception while describing an exception";
    }
}

void reportCurrentException(std::string_view where) noexcept {
    try {
        const std::string description = describeCurrentException();
        logMessage(LogLevel::Error, std::string(where) + ": " + description);
        appendToLog(where, description);
    } catch (...) {
        // Nothing left to report through.
    }
}

std::filesystem::path nativeErrorLogPath() {
    std::error_code ec;
    const std::filesystem::path temp = std::filesystem::temp_directory_path(ec);
    return ec ? std::filesystem::path{} : temp / "gbm-native-errors.log";
}

void installTerminateHandler() noexcept {
    std::set_terminate(&onTerminate);
}

}  // namespace gbm
