#include "core/base/ExceptionDiagnostic.h"

#include "core/base/FsUtil.h"
#include "core/base/Logging.h"
#include "core/workers/ThreadPool.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <exception>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <memory>
#include <sstream>
#include <stdexcept>
#include <string>
#include <system_error>
#include <thread>
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

/// Records every report, and clears the sink at the end of the test.
class RecordedReports {
public:
    RecordedReports() {
        setNativeErrorSink([this](const NativeErrorReport& report) { reports_.push_back(report); });
    }

    ~RecordedReports() { setNativeErrorSink(nullptr); }

    RecordedReports(const RecordedReports&) = delete;
    RecordedReports& operator=(const RecordedReports&) = delete;

    const std::vector<NativeErrorReport>& operator*() const { return reports_; }
    const std::vector<NativeErrorReport>* operator->() const { return &reports_; }

private:
    std::vector<NativeErrorReport> reports_;
};

template <typename Thrower>
void reportThrown(std::string_view where, Thrower thrower) {
    try {
        thrower();
    } catch (...) {
        reportCurrentException(where);
    }
}

TEST_F(ExceptionDiagnosticTest, TheSinkReceivesWhereSummaryAndLogPath) {
    const RecordedReports reports;
    reportBoom("the place");

    ASSERT_EQ(reports->size(), 1u);
    const NativeErrorReport& report = reports->front();
    EXPECT_EQ(report.where, "the place");
    EXPECT_NE(report.summary.find("runtime_error"), std::string::npos) << report.summary;
    EXPECT_NE(report.summary.find("boom"), std::string::npos) << report.summary;
    EXPECT_EQ(report.logPath, fsutil::utf8FromPath(nativeErrorLogPath()));
}

// The summary reaches the screen, where a path can name a private repository; the file
// keeps the paths for a bug report.
TEST_F(ExceptionDiagnosticTest, AFilesystemErrorSummaryHasTypeAndCodeAndNoPath) {
    const RecordedReports reports;
    reportThrown("fs", [] {
        throw std::filesystem::filesystem_error("rename-op",
                                                fsutil::pathFromUtf8("private-one"),
                                                fsutil::pathFromUtf8("private-two"),
                                                std::make_error_code(std::errc::permission_denied));
    });

    ASSERT_EQ(reports->size(), 1u);
    const std::string& summary = reports->front().summary;
    EXPECT_NE(summary.find("filesystem_error"), std::string::npos) << summary;
    EXPECT_NE(summary.find("code=" + std::to_string(static_cast<int>(std::errc::permission_denied))),
              std::string::npos)
        << summary;
    EXPECT_NE(summary.find("category=generic"), std::string::npos) << summary;
    EXPECT_EQ(summary.find("private"), std::string::npos) << summary;
    EXPECT_EQ(summary.find("rename-op"), std::string::npos) << summary;
    EXPECT_NE(readLog().find("private-one"), std::string::npos);
}

TEST_F(ExceptionDiagnosticTest, ASystemErrorSummaryKeepsWhatAndCode) {
    const RecordedReports reports;
    reportThrown("sys", [] {
        throw std::system_error(std::make_error_code(std::errc::invalid_argument), "no mapping");
    });

    ASSERT_EQ(reports->size(), 1u);
    const std::string& summary = reports->front().summary;
    EXPECT_NE(summary.find("no mapping"), std::string::npos) << summary;
    EXPECT_NE(summary.find("category=generic"), std::string::npos) << summary;
}

TEST_F(ExceptionDiagnosticTest, ANonStandardExceptionStillReachesTheSink) {
    const RecordedReports reports;
    reportThrown("odd", [] { throw 7; });

    ASSERT_EQ(reports->size(), 1u);
    EXPECT_EQ(reports->front().summary, "non-standard exception");
}

TEST_F(ExceptionDiagnosticTest, AReportWithNoActiveExceptionSaysSo) {
    const RecordedReports reports;
    reportCurrentException("idle");

    ASSERT_EQ(reports->size(), 1u);
    EXPECT_EQ(reports->front().summary, "no active exception");
}

// Three leads, so that one of them lands the cut inside a character whatever the length
// of the type name in front of it.
TEST_F(ExceptionDiagnosticTest, TheSummaryIsCappedOnACharacterBoundary) {
    std::string characters;
    for (int i = 0; i < 3000; ++i) {
        characters += "\xE5\xB7\xA5";  // 工
    }
    for (const std::string lead : {"", "a", "aa"}) {
        const std::string what = lead + characters;
        const RecordedReports reports;
        reportThrown("long", [&] { throw std::runtime_error(what); });

        ASSERT_EQ(reports->size(), 1u);
        const std::string& summary = reports->front().summary;
        EXPECT_LE(summary.size(), 2048u);
        EXPECT_GT(summary.size(), 2000u);
        const std::size_t start = summary.find("\xE5\xB7\xA5");
        ASSERT_NE(start, std::string::npos) << summary;
        EXPECT_EQ((summary.size() - start) % 3, 0u) << "ends inside a character, lead: " << lead;
        EXPECT_NE(readLog().find(what), std::string::npos) << "the file keeps all of it";
    }
}

TEST_F(ExceptionDiagnosticTest, BytesThatAreNotUtf8NeverReachTheSink) {
    const RecordedReports reports;
    reportThrown("w\xA4here", [] { throw std::runtime_error("\xA4\xA4 ok"); });

    ASSERT_EQ(reports->size(), 1u);
    EXPECT_EQ(reports->front().where, "w?here");
    EXPECT_NE(reports->front().summary.find(": ?? ok"), std::string::npos)
        << reports->front().summary;
}

#if !defined(_WIN32)
TEST(NativeErrorSink, ALogPathThatIsNotUtf8IsSanitised) {
    const std::string directory =
        fsutil::utf8FromPath(std::filesystem::temp_directory_path()) + "/odd\xA4name";
    const ScopedEnv override("GBM_NATIVE_ERROR_LOG_DIR", directory.c_str());
    const RecordedReports reports;
    reportBoom("odd path");

    ASSERT_EQ(reports->size(), 1u);
    EXPECT_NE(reports->front().logPath.find("odd?name"), std::string::npos)
        << reports->front().logPath;
}
#endif

TEST(NativeErrorSink, WithNoFileLocationTheSinkStillHearsOfIt) {
    const ScopedEnv noOverride("GBM_NATIVE_ERROR_LOG_DIR", nullptr);
#if defined(_WIN32)
    const ScopedEnv noHome("LOCALAPPDATA", nullptr);
#else
    const ScopedEnv noHome("HOME", nullptr);
    const ScopedEnv noState("XDG_STATE_HOME", nullptr);
#endif
    const RecordedReports reports;
    reportBoom("nowhere");

    ASSERT_EQ(reports->size(), 1u);
    EXPECT_EQ(reports->front().logPath, "");
}

// A sink that kills the process, or a log sink that does, must not cost the line.
TEST_F(ExceptionDiagnosticTest, TheFileHasTheLineBeforeEitherSinkRuns) {
    std::string logSeenByLogSink;
    std::string logSeenByNativeSink;
    Log::instance().setMessageSink(
        [&](LogLevel, std::string_view) { logSeenByLogSink = readLog(); });
    setNativeErrorSink([&](const NativeErrorReport&) { logSeenByNativeSink = readLog(); });
    reportBoom("ordered");
    setNativeErrorSink(nullptr);
    Log::instance().setMessageSink(nullptr);

    EXPECT_NE(logSeenByLogSink.find("ordered: "), std::string::npos);
    EXPECT_NE(logSeenByNativeSink.find("ordered: "), std::string::npos);
}

TEST_F(ExceptionDiagnosticTest, AThrowingSinkKeepsTheLineAndTheNextReportStillArrives) {
    int calls = 0;
    setNativeErrorSink([&](const NativeErrorReport&) {
        ++calls;
        throw std::runtime_error("from the sink");
    });
    reportBoom("first");
    reportBoom("second");
    setNativeErrorSink(nullptr);

    EXPECT_EQ(calls, 2);
    const std::string log = readLog();
    EXPECT_NE(log.find("first: "), std::string::npos) << log;
    EXPECT_NE(log.find("second: "), std::string::npos) << log;
}

TEST_F(ExceptionDiagnosticTest, AThrowingLogSinkStillReachesTheFileAndTheNativeSink) {
    Log::instance().setMessageSink(
        [](LogLevel, std::string_view) { throw std::runtime_error("from the log sink"); });
    const RecordedReports reports;
    reportBoom("past the log sink");
    Log::instance().setMessageSink(nullptr);

    EXPECT_EQ(reports->size(), 1u);
    EXPECT_NE(readLog().find("past the log sink: "), std::string::npos);
}

TEST_F(ExceptionDiagnosticTest, AClearedSinkHearsNothing) {
    int calls = 0;
    setNativeErrorSink([&](const NativeErrorReport&) { ++calls; });
    setNativeErrorSink(nullptr);
    reportBoom("after clearing");

    EXPECT_EQ(calls, 0);
}

// What lets the owner of the sink's captures destroy them right after clearing.
TEST_F(ExceptionDiagnosticTest, ClearingTheSinkWaitsForTheOneThatIsRunning) {
    std::atomic<bool> entered{false};
    std::atomic<bool> release{false};
    std::atomic<bool> cleared{false};
    setNativeErrorSink([&](const NativeErrorReport&) {
        entered = true;
        while (!release) {
            std::this_thread::yield();
        }
    });
    std::thread reporter = guardedThread("reporter", [] { reportBoom("slow sink"); });
    while (!entered) {
        std::this_thread::yield();
    }
    std::thread clearer = guardedThread("clearer", [&] {
        setNativeErrorSink(nullptr);
        cleared = true;
    });

    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    EXPECT_FALSE(cleared);
    release = true;
    clearer.join();
    reporter.join();
    EXPECT_TRUE(cleared);
}

// Red under TSan or ASan, not by assertion: a sink running past its clear touches freed memory.
TEST_F(ExceptionDiagnosticTest, ASinkNeverOutlivesItsClearUnderRacingReports) {
    std::atomic<bool> stop{false};
    std::vector<std::thread> reporters;
    for (int i = 0; i < 4; ++i) {
        reporters.push_back(guardedThread("racing reporter", [&] {
            while (!stop) {
                reportBoom("racing");
            }
        }));
    }
    for (int round = 0; round < 200; ++round) {
        auto counter = std::make_unique<int>(0);
        setNativeErrorSink([count = counter.get()](const NativeErrorReport&) { ++*count; });
        std::this_thread::yield();
        setNativeErrorSink(nullptr);
        counter.reset();
    }
    stop = true;
    for (std::thread& reporter : reporters) {
        reporter.join();
    }
}

// The process is going down: a sink could block on Dart or allocate on a broken heap.
// Exit 0 from the sink is the one way this death test can go red.
TEST(TerminateHandlerDeathTest, TerminateWritesTheFileAndNeverCallsTheSink) {
    EXPECT_DEATH(
        {
            installTerminateHandler();
            setNativeErrorSink([](const NativeErrorReport&) { std::_Exit(0); });
            try {
                throw std::runtime_error("escaped");
            } catch (...) {
                std::terminate();
            }
        },
        "gbm: fatal: std::terminate: .*escaped");
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

// An error raised outside C++ (Dart's) brings its own summary: the caller knows which of
// its types carry data, so nothing here re-derives one from the detail.
TEST_F(ExceptionDiagnosticTest, AnExternalErrorPutsTheDetailInTheFileAndTheSummaryInTheSink) {
    const RecordedReports reports;
    reportExternalError("FlutterError", "on screen", "in the file\nwith a stack");

    ASSERT_EQ(reports->size(), 1u);
    EXPECT_EQ(reports->front().where, "FlutterError");
    EXPECT_EQ(reports->front().summary, "on screen");
    EXPECT_EQ(reports->front().logPath, fsutil::utf8FromPath(nativeErrorLogPath()));
    const std::string log = readLog();
    EXPECT_NE(log.find("FlutterError: in the file\\nwith a stack\n"), std::string::npos) << log;
    EXPECT_EQ(log.find("on screen"), std::string::npos) << log;
}

TEST_F(ExceptionDiagnosticTest, AnExternalErrorReachesTheLogSinkWithItsDetail) {
    std::vector<std::string> messages;
    Log::instance().setMessageSink([&](LogLevel level, std::string_view message) {
        if (level == LogLevel::Error) {
            messages.emplace_back(message);
        }
    });
    reportExternalError("PlatformDispatcher", "short", "long detail");
    Log::instance().setMessageSink(nullptr);

    ASSERT_EQ(messages.size(), 1u);
    EXPECT_EQ(messages[0], "PlatformDispatcher: long detail");
}

TEST_F(ExceptionDiagnosticTest, AnExternalSummaryIsSanitisedAndCappedOnACharacterBoundary) {
    std::string characters;
    for (int i = 0; i < 3000; ++i) {
        characters += "\xE5\xB7\xA5";  // 工
    }
    for (const std::string lead : {"", "a", "aa"}) {
        const RecordedReports reports;
        reportExternalError("w\xA4here", "\xA4" + lead + characters, "detail");

        ASSERT_EQ(reports->size(), 1u);
        EXPECT_EQ(reports->front().where, "w?here");
        const std::string& summary = reports->front().summary;
        EXPECT_EQ(summary.rfind("?", 0), 0u) << "not UTF-8, so a question mark";
        EXPECT_LE(summary.size(), 2048u);
        EXPECT_GT(summary.size(), 2000u);
        const std::size_t start = summary.find("\xE5\xB7\xA5");
        ASSERT_NE(start, std::string::npos);
        EXPECT_EQ((summary.size() - start) % 3, 0u) << "ends inside a character, lead: " << lead;
    }
}

TEST_F(ExceptionDiagnosticTest, AnExternalDetailThatIsNotUtf8IsSanitisedInTheFile) {
    reportExternalError("bytes", "s", "odd \xA4 byte");

    EXPECT_NE(readLog().find("bytes: odd ? byte"), std::string::npos) << readLog();
}

TEST_F(ExceptionDiagnosticTest, AThrowingSinkStillKeepsAnExternalErrorsLine) {
    setNativeErrorSink([](const NativeErrorReport&) { throw std::runtime_error("from the sink"); });
    reportExternalError("guarded", "s", "kept");
    setNativeErrorSink(nullptr);

    EXPECT_NE(readLog().find("guarded: kept"), std::string::npos) << readLog();
}

}  // namespace
}  // namespace gbm
