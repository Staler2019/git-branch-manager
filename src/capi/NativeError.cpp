#include "capi/Handle.h"
#include "capi/JsonWriter.h"
#include "capi/StagingBuffer.h"
#include "capi/gbm_capi.h"
#include "core/base/ExceptionDiagnostic.h"
#include "core/base/FsUtil.h"

#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <stdexcept>
#include <string>
#include <system_error>

namespace gbm::capi {

namespace {

std::string nativeErrorJson(const NativeErrorReport& report) {
    std::string out = "{\"whenEpochMs\":";
    jsonAppendInt(out,
                  std::chrono::duration_cast<std::chrono::milliseconds>(
                      std::chrono::system_clock::now().time_since_epoch())
                      .count());
    out += ",\"where\":";
    jsonAppendEscaped(out, report.where);
    out += ",\"summary\":";
    jsonAppendEscaped(out, report.summary);
    out += ",\"logPath\":";
    jsonAppendEscaped(out, report.logPath);
    out += '}';
    return out;
}

/// Earlier versions wrote these to the shared temp directory. remove() takes a link
/// itself, never what it points at, and whatever fails stays: this is tidying.
void removeLegacyNativeErrorLogs() {
    std::error_code ec;
    const std::filesystem::path temp = std::filesystem::temp_directory_path(ec);
    if (ec) {
        return;
    }
    std::filesystem::remove(temp / "gbm-native-errors.log", ec);
    std::filesystem::remove(temp / "gbm-native-errors.log.1", ec);
}

}  // namespace

}  // namespace gbm::capi

using namespace gbm;
using namespace gbm::capi;

GBM_API void gbm_set_native_error_callback(GbmNativeErrorCallback callback, void* userData) try {
    if (callback == nullptr) {
        setNativeErrorSink(nullptr);
        return;
    }
    removeLegacyNativeErrorLogs();
    setNativeErrorSink([callback, userData](const NativeErrorReport& report) {
        const std::string json = nativeErrorJson(report);
        // Freed by the receiver via gbm_free_event_payload() -- see gbm_capi.h.
        auto* buffer = static_cast<uint8_t*>(std::malloc(json.size()));
        if (buffer == nullptr) {
            return;  // Out of memory: the file already has the line.
        }
        std::memcpy(buffer, json.data(), json.size());
        callback(buffer, static_cast<int32_t>(json.size()), userData);
    });
} catch (...) {
    reportCurrentException(__func__);
}

GBM_API void gbm_report_external_error(const char* where,
                                       const char* summary,
                                       const char* detail) try {
    const auto text = [](const char* value) {
        return std::string_view(value != nullptr ? value : "");
    };
    reportExternalError(text(where), text(summary), text(detail));
} catch (...) {
    reportCurrentException(__func__);
}

GBM_API int32_t gbm_native_error_log_path_json(void) try {
    std::string out = "{\"path\":";
    jsonAppendEscaped(out, fsutil::utf8FromPath(nativeErrorLogPath()));
    out += '}';
    setStagingBuffer(out);
    return 0;
} catch (...) {
    reportNativeException(__func__);
    return -1;
}

#if defined(GBM_CAPI_TEST_EXPORTS)
GBM_API void gbm_test_raise_native_error(const char* message);

GBM_API void gbm_test_raise_native_error(const char* message) try {
    throw std::runtime_error(message);
} catch (...) {
    reportCurrentException(__func__);
}
#endif
