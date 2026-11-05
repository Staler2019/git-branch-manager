// The native error channel through the extern "C" surface: a report made inside the
// library reaches a registered callback, as NativeCallable.listener would receive it.
// gbm_core is linked into both this binary and gbm_capi, and on Windows that is two
// copies of its state, so the report has to be raised from inside the library.
#include "capi/JsonWriter.h"
#include "capi/gbm_capi.h"
#include "core/base/ExceptionDiagnostic.h"
#include "core/base/FsUtil.h"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <gtest/gtest.h>
#include <sstream>
#include <string>
#include <system_error>
#include <vector>

GBM_API void gbm_test_raise_native_error(const char* message);

namespace gbm::capi {
namespace {

void recordPayload(const uint8_t* payload, int32_t payloadLen, void* userData) {
    static_cast<std::vector<std::string>*>(userData)->emplace_back(
        reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
    gbm_free_event_payload(payload);
}

std::string readFile(const std::filesystem::path& path) {
    std::ifstream in(path, std::ios::binary);
    std::ostringstream text;
    text << in.rdbuf();
    return text.str();
}

std::int64_t nowMs() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

std::filesystem::path legacyLog() {
    return std::filesystem::temp_directory_path() / "gbm-native-errors.log";
}

std::filesystem::path legacyRotatedLog() {
    return std::filesystem::temp_directory_path() / "gbm-native-errors.log.1";
}

class NativeErrorApiTest : public ::testing::Test {
protected:
    void SetUp() override { gbm_set_native_error_callback(&recordPayload, &payloads_); }

    void TearDown() override { gbm_set_native_error_callback(nullptr, nullptr); }

    std::vector<std::string> payloads_;
};

// Dart's GbmNativeErrorEvents test feeds this same shape to the callback it registers.
TEST_F(NativeErrorApiTest, AReportInsideTheLibraryReachesTheCallbackAsTheAgreedJson) {
    const std::int64_t before = nowMs();
    gbm_test_raise_native_error("kaboom \"quoted\"\nsecond line");
    const std::int64_t after = nowMs();

    ASSERT_EQ(payloads_.size(), 1u);
    const std::string& payload = payloads_[0];
    const std::string lead = "{\"whenEpochMs\":";
    ASSERT_EQ(payload.rfind(lead, 0), 0u) << payload;
    const std::int64_t when = std::stoll(payload.substr(lead.size()));
    EXPECT_GE(when, before);
    EXPECT_LE(when, after);

    EXPECT_NE(payload.find(",\"where\":\"gbm_test_raise_native_error\",\"summary\":\""),
              std::string::npos)
        << payload;
    EXPECT_NE(payload.find("kaboom \\\"quoted\\\"\\nsecond line\""), std::string::npos) << payload;

    std::string expectedTail = ",\"logPath\":";
    jsonAppendEscaped(expectedTail, fsutil::utf8FromPath(nativeErrorLogPath()));
    expectedTail += '}';
    ASSERT_GE(payload.size(), expectedTail.size());
    EXPECT_EQ(payload.substr(payload.size() - expectedTail.size()), expectedTail);
}

TEST_F(NativeErrorApiTest, TheLogFileGetsTheLineAndStaysInTheProcessPrivateDirectory) {
    gbm_test_raise_native_error("file too");

    const std::filesystem::path log = nativeErrorLogPath();
    // Appended, not parent_path()'d: Windows' temp path keeps a trailing separator, and a path
    // ending in one compares unequal to the same directory without it.
    EXPECT_EQ(log.parent_path(), std::filesystem::temp_directory_path() / "native-error-logs");
    EXPECT_NE(readFile(log).find("file too"), std::string::npos);
}

TEST_F(NativeErrorApiTest, ANullCallbackStopsTheReports) {
    gbm_set_native_error_callback(nullptr, nullptr);
    gbm_test_raise_native_error("after clearing");

    EXPECT_TRUE(payloads_.empty());
}

TEST_F(NativeErrorApiTest, AnotherRegistrationReplacesTheFirst) {
    std::vector<std::string> second;
    gbm_set_native_error_callback(&recordPayload, &second);
    gbm_test_raise_native_error("to the second");

    EXPECT_TRUE(payloads_.empty());
    EXPECT_EQ(second.size(), 1u);
}

TEST_F(NativeErrorApiTest, RegisteringRemovesTheOldLogAndItsDotOne) {
    std::ofstream(legacyLog()) << "old";
    std::ofstream(legacyRotatedLog()) << "old rotated";

    gbm_set_native_error_callback(&recordPayload, &payloads_);

    EXPECT_FALSE(std::filesystem::exists(legacyLog()));
    EXPECT_FALSE(std::filesystem::exists(legacyRotatedLog()));
}

TEST_F(NativeErrorApiTest, NoOldLogIsNotAProblem) {
    std::error_code ec;
    std::filesystem::remove(legacyLog(), ec);
    std::filesystem::remove(legacyRotatedLog(), ec);

    gbm_set_native_error_callback(&recordPayload, &payloads_);
    gbm_test_raise_native_error("still wired");

    EXPECT_EQ(payloads_.size(), 1u);
}

// A non-empty directory is what a removal cannot take on every platform.
TEST_F(NativeErrorApiTest, AnOldLogThatCannotBeRemovedDoesNotStopRegistration) {
    std::error_code ec;
    std::filesystem::remove(legacyLog(), ec);
    std::filesystem::create_directories(legacyLog() / "in the way", ec);

    gbm_set_native_error_callback(nullptr, nullptr);
    gbm_set_native_error_callback(&recordPayload, &payloads_);
    gbm_test_raise_native_error("still wired");
    std::filesystem::remove_all(legacyLog(), ec);

    EXPECT_EQ(payloads_.size(), 1u);
}

#if !defined(_WIN32)
// The old path sat in a shared temp directory, so another account could have planted a
// link there; removal takes the link and leaves what it points at.
TEST_F(NativeErrorApiTest, ALinkAtTheOldPathIsRemovedAndItsTargetIsLeftAlone) {
    const std::filesystem::path target = std::filesystem::temp_directory_path() / "link-target";
    std::ofstream(target) << "keep me";
    std::error_code ec;
    std::filesystem::remove(legacyLog(), ec);
    std::filesystem::create_symlink(target, legacyLog());

    gbm_set_native_error_callback(&recordPayload, &payloads_);

    EXPECT_FALSE(std::filesystem::is_symlink(std::filesystem::symlink_status(legacyLog())));
    EXPECT_EQ(readFile(target), "keep me");
}
#endif

}  // namespace
}  // namespace gbm::capi
