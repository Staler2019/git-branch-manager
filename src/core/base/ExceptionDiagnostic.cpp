#include "core/base/ExceptionDiagnostic.h"

#include "core/base/FsUtil.h"
#include "core/base/Logging.h"

#include <array>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <fstream>
#include <mutex>
#include <sstream>
#include <system_error>
#include <typeinfo>

#if defined(__GNUG__)
#include <cxxabi.h>
#include <memory>
#endif

#if defined(_WIN32)
#include <windows.h>
#endif

namespace gbm {

namespace {

constexpr std::uintmax_t kMaxLogBytes = 1024 * 1024;

#if defined(_WIN32)
std::filesystem::path pathFromEnv(const wchar_t* name) {
    std::wstring value(32768, L'\0');
    const DWORD length =
        ::GetEnvironmentVariableW(name, value.data(), static_cast<DWORD>(value.size()));
    if (length == 0 || length >= value.size()) {
        return {};
    }
    value.resize(length);
    return std::filesystem::path(value);
}
#else
std::filesystem::path pathFromEnv(const char* name) {
    const char* value = std::getenv(name);
    return value != nullptr ? fsutil::pathFromUtf8(value) : std::filesystem::path{};
}
#endif

/// Per user because a shared temp directory lets another local account read this
/// file or plant a link at its fixed name.
std::filesystem::path nativeErrorLogDirectory() {
#if defined(_WIN32)
    if (std::filesystem::path override = pathFromEnv(L"GBM_NATIVE_ERROR_LOG_DIR");
        !override.empty()) {
        return override;
    }
    const std::filesystem::path base = pathFromEnv(L"LOCALAPPDATA");
    return base.empty() ? base : base / "GitBranchManager" / "logs";
#else
    if (std::filesystem::path override = pathFromEnv("GBM_NATIVE_ERROR_LOG_DIR");
        !override.empty()) {
        return override;
    }
    const std::filesystem::path home = pathFromEnv("HOME");
#if defined(__APPLE__)
    return home.empty() ? home : home / "Library" / "Logs" / "GitBranchManager";
#else
    if (const std::filesystem::path state = pathFromEnv("XDG_STATE_HOME"); state.is_absolute()) {
        return state / "gitbranchmanager";
    }
    return home.empty() ? home : home / ".local" / "state" / "gitbranchmanager";
#endif
#endif
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
        low = static_cast<unsigned char>(lead == 0xE0 ? 0xA0 : 0x80);
        high = static_cast<unsigned char>(lead == 0xED ? 0x9F : 0xBF);
    } else if (lead >= 0xF0 && lead <= 0xF4) {
        length = 4;
        low = static_cast<unsigned char>(lead == 0xF0 ? 0x90 : 0x80);
        high = static_cast<unsigned char>(lead == 0xF4 ? 0x8F : 0xBF);
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

/// Repository content reaches this file, so it stays one line per report and holds
/// nothing a terminal would act on.
std::string escapedForLogLine(std::string_view text) {
    std::string out;
    out.reserve(text.size());
    for (const char c : text) {
        const auto byte = static_cast<unsigned char>(c);
        if (c == '\\') {
            out += "\\\\";
        } else if (c == '\n') {
            out += "\\n";
        } else if (c == '\r') {
            out += "\\r";
        } else if (c == '\t') {
            out += "\\t";
        } else if (byte < 0x20 || byte == 0x7F) {
            std::array<char, 5> hex{};
            std::snprintf(hex.data(), hex.size(), "\\x%02x", byte);
            out += hex.data();
        } else {
            out += c;
        }
    }
    return out;
}

/// `2026-11-05T13:30:11.123Z`.
std::string isoTimeNow() {
    using namespace std::chrono;
    const auto now = floor<milliseconds>(system_clock::now());
    const auto day = floor<days>(now);
    const year_month_day date{day};
    const hh_mm_ss<milliseconds> time{now - day};
    std::array<char, 32> text{};
    std::snprintf(text.data(),
                  text.size(),
                  "%04d-%02u-%02uT%02d:%02d:%02d.%03dZ",
                  static_cast<int>(date.year()),
                  static_cast<unsigned>(date.month()),
                  static_cast<unsigned>(date.day()),
                  static_cast<int>(time.hours().count()),
                  static_cast<int>(time.minutes().count()),
                  static_cast<int>(time.seconds().count()),
                  static_cast<int>(time.subseconds().count()));
    return text.data();
}

void appendToLog(std::string_view where, std::string_view description) {
    static std::mutex mutex;
    const std::lock_guard<std::mutex> lock(mutex);

    const std::filesystem::path path = nativeErrorLogPath();
    if (path.empty()) {
        return;
    }
    std::error_code ec;
    std::filesystem::create_directories(path.parent_path(), ec);
    std::filesystem::permissions(path.parent_path(), std::filesystem::perms::owner_all, ec);
    const std::uintmax_t size = std::filesystem::file_size(path, ec);
    bool startOver = false;
    if (!ec && size > kMaxLogBytes) {
        std::filesystem::path rotated = path;
        rotated += ".1";
        std::filesystem::rename(path, rotated, ec);
        startOver = static_cast<bool>(ec);
    }
    std::ofstream out(path, std::ios::binary | (startOver ? std::ios::trunc : std::ios::app));

    out << isoTimeNow() << " thread " << std::this_thread::get_id() << " "
        << escapedForLogLine(where) << ": " << escapedForLogLine(description) << "\n";
    out.close();
    std::filesystem::permissions(
        path, std::filesystem::perms::owner_read | std::filesystem::perms::owner_write, ec);
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
    const std::filesystem::path directory = nativeErrorLogDirectory();
    return directory.empty() ? directory : directory / "gbm-native-errors.log";
}

void installTerminateHandler() noexcept {
    std::set_terminate(&onTerminate);
}

}  // namespace gbm
