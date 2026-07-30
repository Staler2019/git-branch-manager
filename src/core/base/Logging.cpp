#include "core/base/Logging.h"

namespace gbm {

std::string_view toString(LogLevel level) {
    switch (level) {
        case LogLevel::Trace:
            return "trace";
        case LogLevel::Debug:
            return "debug";
        case LogLevel::Info:
            return "info";
        case LogLevel::Warn:
            return "warn";
        case LogLevel::Error:
            return "error";
    }
    return "info";
}

std::string OperationRecord::commandLine() const {
    std::string out;
    for (std::size_t i = 0; i < argv.size(); ++i) {
        if (i != 0) {
            out.push_back(' ');
        }
        const std::string& arg = argv[i];
        const bool needsQuotes =
            arg.empty() || arg.find_first_of(" \t\"'\\$*?") != std::string::npos;
        if (!needsQuotes) {
            out += arg;
            continue;
        }
        out.push_back('"');
        for (char c : arg) {
            if (c == '"' || c == '\\') {
                out.push_back('\\');
            }
            out.push_back(c);
        }
        out.push_back('"');
    }
    return out;
}

Log& Log::instance() {
    static Log log;
    return log;
}

void Log::setLevel(LogLevel level) {
    std::lock_guard<std::mutex> lock(mutex_);
    level_ = level;
}

LogLevel Log::level() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return level_;
}

void Log::setMessageSink(MessageSink sink) {
    std::lock_guard<std::mutex> lock(mutex_);
    messageSink_ = std::move(sink);
}

void Log::setOperationSink(OperationSink sink) {
    std::lock_guard<std::mutex> lock(mutex_);
    operationSink_ = std::move(sink);
}

void Log::write(LogLevel level, std::string_view message) {
    MessageSink sink;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (level < level_ || !messageSink_) {
            return;
        }
        sink = messageSink_;
    }
    // Called outside the lock: a sink that logs back into us must not deadlock.
    sink(level, message);
}

void Log::recordOperation(const OperationRecord& record) {
    OperationSink sink;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        if (!operationSink_) {
            return;
        }
        sink = operationSink_;
    }
    sink(record);
}

void logMessage(LogLevel level, std::string_view message) {
    Log::instance().write(level, message);
}

}  // namespace gbm
