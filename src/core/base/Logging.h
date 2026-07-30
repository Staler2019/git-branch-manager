#pragma once

#include <chrono>
#include <cstdint>
#include <functional>
#include <mutex>
#include <string>
#include <string_view>
#include <vector>

namespace gbm {

enum class LogLevel { Trace, Debug, Info, Warn, Error };

std::string_view toString(LogLevel level);

/// One git invocation, as recorded for the operation log panel. The UI renders
/// argv, duration, exit code and full stderr with a copy button — this record is
/// the app's primary support tool, so nothing here is abbreviated.
struct OperationRecord {
    std::chrono::system_clock::time_point when;
    std::string repoDir;
    std::vector<std::string> argv;
    int exitCode = 0;
    std::int64_t durationMs = 0;
    std::string stderrText;
    bool cancelled = false;
    bool timedOut = false;

    /// argv rendered for display, quoting only arguments that need it.
    std::string commandLine() const;
};

/// Process-wide log sink. Deliberately tiny: the core has no logging framework
/// dependency, and the app installs its own sink to feed the operation log view.
class Log {
public:
    using MessageSink = std::function<void(LogLevel, std::string_view)>;
    using OperationSink = std::function<void(const OperationRecord&)>;

    static Log& instance();

    void setLevel(LogLevel level);
    LogLevel level() const;

    void setMessageSink(MessageSink sink);
    void setOperationSink(OperationSink sink);

    void write(LogLevel level, std::string_view message);
    void recordOperation(const OperationRecord& record);

private:
    Log() = default;

    mutable std::mutex mutex_;
    LogLevel level_ = LogLevel::Info;
    MessageSink messageSink_;
    OperationSink operationSink_;
};

void logMessage(LogLevel level, std::string_view message);

#define GBM_LOG_DEBUG(msg) ::gbm::logMessage(::gbm::LogLevel::Debug, (msg))
#define GBM_LOG_INFO(msg) ::gbm::logMessage(::gbm::LogLevel::Info, (msg))
#define GBM_LOG_WARN(msg) ::gbm::logMessage(::gbm::LogLevel::Warn, (msg))
#define GBM_LOG_ERROR(msg) ::gbm::logMessage(::gbm::LogLevel::Error, (msg))

}  // namespace gbm
