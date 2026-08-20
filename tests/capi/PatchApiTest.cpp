// Integration tests for the M7 patch import/export slice of the extern "C"
// surface (gbm_capi.h).
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

    void clear() {
        std::lock_guard<std::mutex> lock(mutex);
        events.clear();
    }
};

bool anyEventOfType(const std::vector<std::pair<int32_t, std::string>>& events, int32_t type) {
    for (const auto& [eventType, payload] : events) {
        if (eventType == type) return true;
    }
    return false;
}

void logCallback(GbmSessionHandle, int32_t eventType, const uint8_t* payload, int32_t payloadLen, void* userData) {
    auto* log = static_cast<EventLog*>(userData);
    std::string body;
    if (payload != nullptr) {
        body.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        gbm_free_event_payload(payload);
    }
    log->add(eventType, std::move(body));
}

class PatchApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        auto detected = GitExecutable::detect();
        if (!detected) {
            GTEST_SKIP() << "no usable git found: " << detected.error().message;
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-patch-" + std::string(info->name()));
        outputDir_ = std::filesystem::temp_directory_path() / ("gbm-capi-patch-out-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::remove_all(outputDir_);
        std::filesystem::create_directories(repo_);
        std::filesystem::create_directories(outputDir_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "file.txt") << "v1\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "First commit"}), 0);

        std::ofstream(repo_ / "file.txt") << "v1\nv2\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Second commit"}), 0);
        secondCommit_ = commitHex("HEAD");

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
        std::filesystem::remove_all(outputDir_, ec);
    }

    /// Fixture git, without a shell in the middle -- see tests/support/GitCli.h
    /// for why that matters (one process instead of two, and no per-platform
    /// quoting hazard).
    int runGit(std::vector<std::string> args) {
        return ::gbm::testing::GitCli::run(repo_, std::move(args));
    }

    std::string commitHex(const std::string& revision) {
        const std::string outFile = (repo_ / "..gbm_rev.txt").string();
        std::string command = "git -C \"" + repo_.string() + "\" rev-parse " + revision + " > \"" + outFile + "\"";
        [[maybe_unused]] const int rc = std::system(command.c_str());
        std::ifstream in(outFile);
        std::string line;
        std::getline(in, line);
        return line;
    }

    bool waitForWorkingCopyOperationFinished() {
        return log_.waitFor([](const auto& events) {
            return anyEventOfType(events, GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
        });
    }

    std::filesystem::path repo_;
    std::filesystem::path outputDir_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
    std::string secondCommit_;
};

TEST_F(PatchApiTest, ExportPatchesWritesAFormatPatchFile) {
    const char* commitHexes[] = {secondCommit_.c_str()};
    gbm_patch_export(session_, commitHexes, 1, outputDir_.string().c_str());
    ASSERT_TRUE(waitForWorkingCopyOperationFinished());

    bool foundPatch = false;
    for (const auto& entry : std::filesystem::directory_iterator(outputDir_)) {
        if (entry.path().extension() == ".patch") {
            foundPatch = true;
        }
    }
    EXPECT_TRUE(foundPatch);
}

TEST_F(PatchApiTest, ApplyPatchFilesAppliesADiffToTheWorkTree) {
    // Build a plain diff for an uncommitted change via `git diff`, then reset
    // the work tree and re-apply it through gbm_patch_apply_files() instead.
    std::ofstream(repo_ / "file.txt") << "v1\nv2\nv3\n";
    const std::filesystem::path patchFile = outputDir_ / "change.patch";
    std::string diffCommand =
        "git -C \"" + repo_.string() + "\" diff > \"" + patchFile.string() + "\"";
    ASSERT_EQ(std::system(diffCommand.c_str()), 0);
    ASSERT_EQ(runGit({"checkout", "--quiet", "--", "file.txt"}), 0);

    // gbm_patch_apply_files() shells out with paths.commandDir() as its
    // working directory, so an absolute path avoids depending on cwd.
    const std::string patchFilePath = patchFile.string();
    const char* patchFiles[] = {patchFilePath.c_str()};
    gbm_patch_apply_files(session_, patchFiles, 1, /*threeWay=*/0, /*updateIndex=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished());

    std::ifstream file(repo_ / "file.txt");
    std::string content((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
    EXPECT_EQ(content, "v1\nv2\nv3\n");
}

}  // namespace
}  // namespace gbm::capi
