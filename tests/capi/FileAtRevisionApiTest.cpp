// Integration tests for gbm_export_file_at_revision() -- the blob-read data
// path behind context menu 05-K's "Open file at this revision" and "Save
// this revision as..." (issues #58/#59).
//
// The export writes raw bytes to a destination path rather than returning
// content inline the way gbm_request_working_tree_content() does, so the
// assertions here are on the bytes that land on disk. That is the whole
// reason for the shape: neither caller displays the content in-app (one
// hands the path to the OS, the other saves it where the user asked), and a
// JSON string payload cannot carry a binary blob -- which is what
// ExportsABinaryFileByteIdentical exists to prove.
#include "capi/gbm_capi.h"
#include "core/git/GitExecutable.h"
#include "support/GitCli.h"

#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <functional>
#include <gtest/gtest.h>
#include <mutex>
#include <string>
#include <vector>

namespace gbm::capi {
namespace {

using ::gbm::testing::GitCli;

struct EventLog {
    std::mutex mutex;
    std::condition_variable cv;
    std::vector<std::pair<int32_t, std::string>> events;

    void add(int32_t eventType, std::string payload) {
        std::lock_guard<std::mutex> lock(mutex);
        events.emplace_back(eventType, std::move(payload));
        cv.notify_all();
    }

    bool waitFor(const std::function<bool(const std::vector<std::pair<int32_t, std::string>>&)>& pred,
                 std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] { return pred(events); });
    }

    std::string lastPayloadOfType(int32_t type) {
        std::lock_guard<std::mutex> lock(mutex);
        std::string last;
        for (const auto& [eventType, payload] : events) {
            if (eventType == type) last = payload;
        }
        return last;
    }
};

void logCallback(GbmSessionHandle, int32_t eventType, const uint8_t* payload, int32_t payloadLen, void* userData) {
    auto* log = static_cast<EventLog*>(userData);
    std::string body;
    if (payload != nullptr) {
        body.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        gbm_free_event_payload(payload);
    }
    log->add(eventType, std::move(body));
}

/// The binary fixture: an embedded NUL plus bytes that are not valid UTF-8,
/// so anything that round-tripped this through a JSON string or a text-mode
/// stream would corrupt it.
const std::string& binaryFixture() {
    static const std::string bytes = [] {
        std::string data;
        data += '\x89';
        data += "PNG";
        data += '\r';
        data += '\n';
        data.push_back('\0');
        data += '\x1a';
        data += '\n';
        data += '\xff';
        data += '\xfe';
        data.push_back('\0');
        data += "trailer";
        return data;
    }();
    return bytes;
}

std::string readAllBytes(const std::filesystem::path& path) {
    std::ifstream in(path, std::ios::binary);
    return std::string(std::istreambuf_iterator<char>(in), std::istreambuf_iterator<char>());
}

class FileAtRevisionApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        // GitCli detects git once per test binary and caches it; this used to
        // be a GitExecutable::detect() per suite, i.e. one `git --version`
        // process each -- 29 of them across this binary.
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() /
                ("gbm-capi-file-at-revision-" + std::string(info->name()));
        out_ = std::filesystem::temp_directory_path() /
               ("gbm-capi-file-at-revision-out-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::remove_all(out_);
        std::filesystem::create_directories(repo_);
        std::filesystem::create_directories(out_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "hello.txt", std::ios::binary) << "first revision\n";
        {
            std::ofstream binary(repo_ / "logo.bin", std::ios::binary);
            binary.write(binaryFixture().data(), static_cast<std::streamsize>(binaryFixture().size()));
        }
        std::ofstream(repo_ / "gone.txt", std::ios::binary) << "deleted later\n";
        std::filesystem::create_directories(repo_ / "docs");
        std::ofstream(repo_ / "docs" / "notes.txt", std::ios::binary) << "notes\n";
        ASSERT_EQ(runGit({"add", "."}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "First revision"}), 0);

        std::ofstream(repo_ / "hello.txt", std::ios::binary) << "second revision\n";
        ASSERT_EQ(runGit({"rm", "--quiet", "gone.txt"}), 0);
        ASSERT_EQ(runGit({"add", "hello.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Second revision"}), 0);

        session_ = gbm_session_open(repo_.string().c_str(), (repo_ / ".git").string().c_str(), "");
        ASSERT_NE(session_, nullptr);
        gbm_register_callback(session_, &logCallback, &log_);
    }

    void TearDown() override {
        if (session_ != nullptr) {
            gbm_session_close(session_);
        }
        std::error_code ec;
        std::filesystem::remove_all(repo_, ec);
        std::filesystem::remove_all(out_, ec);
    }

    /// Fixture git, without a shell in the middle -- see tests/support/GitCli.h
    /// for why that matters (one process instead of two, and no per-platform
    /// quoting hazard).
    int runGit(std::vector<std::string> args) {
        return GitCli::run(repo_, std::move(args));
    }

    /// Fires the export and blocks until its reply arrives, returning the
    /// reply payload.
    std::string exportAndWait(const std::string& revision,
                              const std::string& path,
                              const std::filesystem::path& destination) {
        gbm_export_file_at_revision(session_, revision.c_str(), path.c_str(), destination.string().c_str());
        EXPECT_TRUE(log_.waitFor([](const auto& events) {
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_FILE_AT_REVISION_EXPORTED) return true;
            }
            return false;
        }));
        return log_.lastPayloadOfType(GBM_EVENT_FILE_AT_REVISION_EXPORTED);
    }

    std::filesystem::path repo_;
    std::filesystem::path out_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(FileAtRevisionApiTest, ExportsATextFileByteIdentical) {
    const std::filesystem::path destination = out_ / "hello-first.txt";
    const std::string reply = exportAndWait("HEAD~1", "hello.txt", destination);

    EXPECT_NE(reply.find("\"succeeded\":true"), std::string::npos) << reply;
    EXPECT_NE(reply.find("\"path\":\"hello.txt\""), std::string::npos) << reply;
    EXPECT_NE(reply.find("\"revision\":\"HEAD~1\""), std::string::npos) << reply;
    ASSERT_TRUE(std::filesystem::exists(destination));
    EXPECT_EQ(readAllBytes(destination), "first revision\n");
}

TEST_F(FileAtRevisionApiTest, ExportsABinaryFileByteIdentical) {
    const std::filesystem::path destination = out_ / "logo.bin";
    const std::string reply = exportAndWait("HEAD", "logo.bin", destination);

    EXPECT_NE(reply.find("\"succeeded\":true"), std::string::npos) << reply;
    ASSERT_TRUE(std::filesystem::exists(destination));
    // Byte-for-byte, NULs and invalid UTF-8 included: this is what an inline
    // JSON-string payload could not have carried.
    EXPECT_EQ(readAllBytes(destination), binaryFixture());
}

TEST_F(FileAtRevisionApiTest, ExportsAFileThatALaterCommitDeleted) {
    const std::filesystem::path destination = out_ / "gone.txt";
    const std::string reply = exportAndWait("HEAD~1", "gone.txt", destination);

    EXPECT_NE(reply.find("\"succeeded\":true"), std::string::npos) << reply;
    ASSERT_TRUE(std::filesystem::exists(destination));
    EXPECT_EQ(readAllBytes(destination), "deleted later\n");
}

TEST_F(FileAtRevisionApiTest, ReportsFailureWhenThePathIsAbsentAtThatRevision) {
    const std::filesystem::path destination = out_ / "gone.txt";
    const std::string reply = exportAndWait("HEAD", "gone.txt", destination);

    EXPECT_NE(reply.find("\"succeeded\":false"), std::string::npos) << reply;
    EXPECT_NE(reply.find("\"error\":"), std::string::npos) << reply;
    // A failed export must not leave a truncated or empty file behind for
    // the caller to hand to the OS.
    EXPECT_FALSE(std::filesystem::exists(destination));
}

TEST_F(FileAtRevisionApiTest, ReportsFailureWhenThePathIsADirectory) {
    // `<rev>:<dir>` resolves to a tree -- a valid object, so this is not the
    // NotFound branch above. Writing a tree listing out under the user's
    // chosen filename would be worse than refusing.
    const std::filesystem::path destination = out_ / "docs";
    const std::string reply = exportAndWait("HEAD", "docs", destination);

    EXPECT_NE(reply.find("\"succeeded\":false"), std::string::npos) << reply;
    EXPECT_NE(reply.find("not a file"), std::string::npos) << reply;
    EXPECT_FALSE(std::filesystem::exists(destination));
}

TEST_F(FileAtRevisionApiTest, ReportsFailureWhenTheDestinationDirectoryIsMissing) {
    const std::filesystem::path destination = out_ / "no-such-dir" / "hello.txt";
    const std::string reply = exportAndWait("HEAD", "hello.txt", destination);

    EXPECT_NE(reply.find("\"succeeded\":false"), std::string::npos) << reply;
    EXPECT_NE(reply.find("\"error\":"), std::string::npos) << reply;
    EXPECT_FALSE(std::filesystem::exists(destination));
}

}  // namespace
}  // namespace gbm::capi
