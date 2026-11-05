#include "core/base/ExceptionDiagnostic.h"

#include "core/base/FsUtil.h"
#include "core/base/Logging.h"
#include "core/workers/ThreadPool.h"

#include <algorithm>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <vector>

namespace gbm {
namespace {

template <typename Thrower>
std::string describeThrown(Thrower thrower) {
    try {
        thrower();
    } catch (...) {
        return describeCurrentException();
    }
    return {};
}

std::string readLog() {
    std::ifstream in(nativeErrorLogPath(), std::ios::binary);
    std::ostringstream text;
    text << in.rdbuf();
    return text.str();
}

class ExceptionDiagnosticTest : public ::testing::Test {
protected:
    void SetUp() override {
        std::error_code ec;
        std::filesystem::remove(nativeErrorLogPath(), ec);
        std::filesystem::create_directories(nativeErrorLogPath().parent_path(), ec);
    }
};

/// Sets or, with nullptr, clears one variable, and restores it.
class ScopedEnv {
public:
    ScopedEnv(std::string name, const char* value) : name_(std::move(name)) {
        const char* previous = std::getenv(name_.c_str());
        hadValue_ = previous != nullptr;
        previous_ = hadValue_ ? previous : "";
        set(value);
    }

    ~ScopedEnv() { set(hadValue_ ? previous_.c_str() : nullptr); }

    ScopedEnv(const ScopedEnv&) = delete;
    ScopedEnv& operator=(const ScopedEnv&) = delete;

private:
    void set(const char* value) {
#if defined(_WIN32)
        _putenv_s(name_.c_str(), value != nullptr ? value : "");
#else
        if (value != nullptr) {
            setenv(name_.c_str(), value, 1);
        } else {
            unsetenv(name_.c_str());
        }
#endif
    }

    std::string name_;
    std::string previous_;
    bool hadValue_ = false;
};

TEST(NativeErrorLogPath, ATestBinaryStaysInItsProcessPrivateDirectory) {
    const std::filesystem::path log = nativeErrorLogPath();
    const std::filesystem::path temp = std::filesystem::temp_directory_path();
    EXPECT_EQ(log, temp / "native-error-logs" / "gbm-native-errors.log");
}

TEST(NativeErrorLogPath, WithNoOverrideItIsUnderThePerUserDirectory) {
    const ScopedEnv noOverride("GBM_NATIVE_ERROR_LOG_DIR", nullptr);
#if defined(_WIN32)
    const ScopedEnv home("LOCALAPPDATA", "C:\\Users\\u\\AppData\\Local");
    const std::filesystem::path expected = std::filesystem::path("C:\\Users\\u\\AppData\\Local") /
                                           "GitBranchManager" / "logs";
#elif defined(__APPLE__)
    const ScopedEnv home("HOME", "/home/u");
    const std::filesystem::path expected = "/home/u/Library/Logs/GitBranchManager";
#else
    const ScopedEnv home("HOME", "/home/u");
    const ScopedEnv noState("XDG_STATE_HOME", nullptr);
    const std::filesystem::path expected = "/home/u/.local/state/gitbranchmanager";
#endif
    EXPECT_EQ(nativeErrorLogPath(), expected / "gbm-native-errors.log");
}

#if !defined(_WIN32) && !defined(__APPLE__)
TEST(NativeErrorLogPath, TheStateDirectoryIsHonouredOnlyWhenAbsolute) {
    const ScopedEnv noOverride("GBM_NATIVE_ERROR_LOG_DIR", nullptr);
    const ScopedEnv home("HOME", "/home/u");
    {
        const ScopedEnv state("XDG_STATE_HOME", "/state");
        EXPECT_EQ(nativeErrorLogPath(), "/state/gitbranchmanager/gbm-native-errors.log");
    }
    const ScopedEnv state("XDG_STATE_HOME", "relative");
    EXPECT_EQ(nativeErrorLogPath(), "/home/u/.local/state/gitbranchmanager/gbm-native-errors.log");
}
#endif

TEST(NativeErrorLogPath, NoLocationMeansNoFileAndNoThrow) {
    const ScopedEnv noOverride("GBM_NATIVE_ERROR_LOG_DIR", nullptr);
#if defined(_WIN32)
    const ScopedEnv noHome("LOCALAPPDATA", nullptr);
#else
    const ScopedEnv noHome("HOME", nullptr);
    const ScopedEnv noState("XDG_STATE_HOME", nullptr);
#endif
    EXPECT_TRUE(nativeErrorLogPath().empty());
    try {
        throw std::runtime_error("boom");
    } catch (...) {
        reportCurrentException("nowhere to write");
    }
}

TEST(NativeErrorLogPath, TheDirectoryIsCreatedOnTheFirstReport) {
    const std::filesystem::path directory = std::filesystem::temp_directory_path() / "not-yet" / "here";
    const ScopedEnv override("GBM_NATIVE_ERROR_LOG_DIR", directory.string().c_str());
    try {
        throw std::runtime_error("boom");
    } catch (...) {
        reportCurrentException("first");
    }
    EXPECT_NE(readLog().find("first: "), std::string::npos);
}

#if !defined(_WIN32)
TEST(NativeErrorLogPath, TheDirectoryAndFileAreReadableOnlyByTheirOwner) {
    const std::filesystem::path directory = std::filesystem::temp_directory_path() / "owner-only";
    const ScopedEnv override("GBM_NATIVE_ERROR_LOG_DIR", directory.string().c_str());
    try {
        throw std::runtime_error("boom");
    } catch (...) {
        reportCurrentException("private");
    }
    const auto others = std::filesystem::perms::group_all | std::filesystem::perms::others_all;
    EXPECT_EQ(std::filesystem::status(directory).permissions() & others,
              std::filesystem::perms::none);
    EXPECT_EQ(std::filesystem::status(nativeErrorLogPath()).permissions() & others,
              std::filesystem::perms::none);
}
#endif

TEST(DescribeCurrentException, ASystemErrorCarriesTypeWhatCodeAndCategory) {
    const std::string text = describeThrown([] {
        throw std::system_error(std::make_error_code(std::errc::invalid_argument), "no mapping");
    });
    EXPECT_NE(text.find("system_error"), std::string::npos) << text;
    EXPECT_NE(text.find("no mapping"), std::string::npos) << text;
    EXPECT_NE(text.find("code=" + std::to_string(static_cast<int>(std::errc::invalid_argument))),
              std::string::npos)
        << text;
    EXPECT_NE(text.find("category=generic"), std::string::npos) << text;
}

TEST(DescribeCurrentException, AFilesystemErrorNamesBothPathsAsUtf8) {
    const std::string first = "\xE5\xB7\xA5\xE4\xBD\x9C\xE6\xA8\xB9";  // 工作樹
    const std::string second = "\xE6\xB8\xAC\xE8\xA9\xA6";             // 測試
    const std::string text = describeThrown([&] {
        throw std::filesystem::filesystem_error(
            "rename",
            fsutil::pathFromUtf8(first),
            fsutil::pathFromUtf8(second),
            std::make_error_code(std::errc::permission_denied));
    });
    EXPECT_NE(text.find("filesystem_error"), std::string::npos) << text;
    EXPECT_NE(text.find("path1=\"" + first + "\""), std::string::npos) << text;
    EXPECT_NE(text.find("path2=\"" + second + "\""), std::string::npos) << text;
}

TEST(DescribeCurrentException, ANonStandardExceptionIsStillDescribed) {
    EXPECT_EQ(describeThrown([] { throw 7; }), "non-standard exception");
}

TEST(DescribeCurrentException, NoActiveExceptionSaysSo) {
    EXPECT_EQ(describeCurrentException(), "no active exception");
}

// What MSVC's what() can hold under a non-UTF-8 code page: 中 in Big5. Dart's
// utf8.decode throws on it, which would turn the error report into a second crash.
TEST(DescribeCurrentException, BytesThatAreNotUtf8BecomeQuestionMarks) {
    const std::string text = describeThrown([] { throw std::runtime_error("\xA4\xA4 ok"); });
    EXPECT_NE(text.find(": ?? ok"), std::string::npos) << text;
}

TEST(DescribeCurrentException, UnterminatedOverlongAndSurrogateSequencesAreRejected) {
    const std::string text = describeThrown([] {
        throw std::runtime_error("a\xE5\xB7|\xC0\xAF|\xED\xA0\x80|\xF4\x90\x80\x80|\xE0\x80\xAF|\xF0\x80\x80\x80|z");
    });
    EXPECT_NE(text.find(": a??|??|???|????|???|????|z"), std::string::npos) << text;
}

TEST(DescribeCurrentException, WellFormedUtf8IsKept) {
    const std::string kept = "\xE5\xB7\xA5 \xC3\xA9 \xF0\x9F\x98\x80";
    const std::string text = describeThrown([&] { throw std::runtime_error(kept); });
    EXPECT_NE(text.find(": " + kept), std::string::npos) << text;
}

TEST_F(ExceptionDiagnosticTest, EachReportIsAppendedToTheLogFile) {
    for (const char* where : {"first", "second"}) {
        try {
            throw std::runtime_error("boom");
        } catch (...) {
            reportCurrentException(where);
        }
    }
    const std::string log = readLog();
    EXPECT_NE(log.find("first: "), std::string::npos) << log;
    EXPECT_NE(log.find("second: "), std::string::npos) << log;
    EXPECT_EQ(std::count(log.begin(), log.end(), '\n'), 2) << log;
}

std::filesystem::path rotatedLogPath() {
    std::filesystem::path path = nativeErrorLogPath();
    path += ".1";
    return path;
}

void reportBoom(const std::string& where) {
    try {
        throw std::runtime_error("boom");
    } catch (...) {
        reportCurrentException(where);
    }
}

TEST_F(ExceptionDiagnosticTest, ALogFileOverTheCapIsKeptAsTheDotOneAndStartsOver) {
    {
        std::ofstream out(nativeErrorLogPath(), std::ios::binary);
        out << std::string(1024 * 1024 + 1, 'Z');
    }
    {
        std::ofstream out(rotatedLogPath(), std::ios::binary);
        out << "the previous dot one";
    }
    reportBoom("after the cap");

    const std::string log = readLog();
    EXPECT_EQ(log.find("ZZZ"), std::string::npos);
    EXPECT_NE(log.find("after the cap: "), std::string::npos) << log;
    std::error_code ec;
    EXPECT_EQ(std::filesystem::file_size(rotatedLogPath(), ec), 1024u * 1024u + 1u);
}

TEST_F(ExceptionDiagnosticTest, ALogFileUnderTheCapIsAppendedTo) {
    {
        std::ofstream out(nativeErrorLogPath(), std::ios::binary);
        out << std::string(1024 * 1024, 'Z');
    }
    std::error_code ec;
    std::filesystem::remove(rotatedLogPath(), ec);
    reportBoom("at the cap");

    EXPECT_NE(readLog().find("ZZZ"), std::string::npos);
    EXPECT_FALSE(std::filesystem::exists(rotatedLogPath()));
}

TEST_F(ExceptionDiagnosticTest, ALogThatCannotBeRotatedStartsOverAndNeverGrowsPastTheCap) {
    {
        std::ofstream out(nativeErrorLogPath(), std::ios::binary);
        out << std::string(1024 * 1024 + 1, 'Z');
    }
    std::error_code ec;
    std::filesystem::remove_all(rotatedLogPath(), ec);
    std::filesystem::create_directories(rotatedLogPath() / "in the way", ec);
    reportBoom("unrotatable");
    std::filesystem::remove_all(rotatedLogPath(), ec);

    const std::string log = readLog();
    EXPECT_EQ(log.find("ZZZ"), std::string::npos);
    EXPECT_NE(log.find("unrotatable: "), std::string::npos) << log;
}

TEST_F(ExceptionDiagnosticTest, EachLineStartsWithAnIsoTimeInUtc) {
    reportBoom("timed");
    const std::string log = readLog();
    ASSERT_GE(log.size(), 24u) << log;
    const std::string stamp = log.substr(0, 24);
    for (const std::size_t i : {0u, 1u, 2u, 3u, 5u, 6u, 8u, 9u, 11u, 12u, 14u, 15u, 17u, 18u, 20u, 21u, 22u}) {
        EXPECT_TRUE(stamp[i] >= '0' && stamp[i] <= '9') << stamp;
    }
    EXPECT_EQ(stamp.substr(4, 1), "-") << stamp;
    EXPECT_EQ(stamp.substr(10, 1), "T") << stamp;
    EXPECT_EQ(stamp.substr(19, 1), ".") << stamp;
    EXPECT_EQ(stamp.substr(23, 1), "Z") << stamp;
    const std::string year = stamp.substr(0, 4);
    EXPECT_GE(year, "2024") << stamp;
}

// A branch or file name is repository content; it must not be able to forge a line
// or send terminal control sequences when the file is printed.
TEST_F(ExceptionDiagnosticTest, ControlCharactersCannotBreakOutOfTheLine) {
    try {
        throw std::runtime_error("a\nforged\x1b[2Jline\\");
    } catch (...) {
        reportCurrentException("w\nhere");
    }
    const std::string log = readLog();
    EXPECT_EQ(std::count(log.begin(), log.end(), '\n'), 1) << log;
    EXPECT_EQ(log.find('\x1b'), std::string::npos) << log;
    EXPECT_NE(log.find("w\\nhere: "), std::string::npos) << log;
    EXPECT_NE(log.find("a\\nforged\\x1b[2Jline\\\\"), std::string::npos) << log;
}

TEST_F(ExceptionDiagnosticTest, AReportReachesTheLogSink) {
    std::vector<std::string> messages;
    Log::instance().setMessageSink(
        [&](LogLevel level, std::string_view message) {
            if (level == LogLevel::Error) {
                messages.emplace_back(message);
            }
        });
    try {
        throw std::runtime_error("boom");
    } catch (...) {
        reportCurrentException("sink");
    }
    Log::instance().setMessageSink(nullptr);
    ASSERT_EQ(messages.size(), 1u);
    EXPECT_NE(messages[0].find("sink: "), std::string::npos) << messages[0];
    EXPECT_NE(messages[0].find("boom"), std::string::npos) << messages[0];
}

TEST(TerminateHandlerDeathTest, ANoexceptViolationPrintsTheExceptionBeforeAborting) {
    EXPECT_DEATH(
        {
            installTerminateHandler();
            try {
                throw std::runtime_error("escaped");
            } catch (...) {
                std::terminate();
            }
        },
        "gbm: fatal: std::terminate: .*escaped");
}

TEST_F(ExceptionDiagnosticTest, AGuardedThreadReportsAndGivesTheHandlerTheException) {
    std::string seen;
    guardedThread(
        "named thread",
        [] { throw std::runtime_error("from the body"); },
        [&] {
            seen = describeCurrentException();
            throw std::runtime_error("from the handler");
        })
        .join();

    EXPECT_NE(seen.find("from the body"), std::string::npos) << seen;
    const std::string log = readLog();
    EXPECT_NE(log.find("named thread: "), std::string::npos) << log;
    EXPECT_NE(log.find("named thread exception handler: "), std::string::npos) << log;
    EXPECT_NE(log.find("from the handler"), std::string::npos) << log;
}

TEST_F(ExceptionDiagnosticTest, AThrowingPoolTaskIsReportedAndThePoolKeepsRunning) {
    ThreadPool pool("diagnostic", 1);
    bool ranAfter = false;
    pool.post([] { throw std::runtime_error("from a task"); });
    pool.post([&] { ranAfter = true; });
    pool.drain();

    EXPECT_TRUE(ranAfter);
    const std::string log = readLog();
    EXPECT_NE(log.find("diagnostic worker: "), std::string::npos) << log;
    EXPECT_NE(log.find("from a task"), std::string::npos) << log;
}

}  // namespace
}  // namespace gbm
