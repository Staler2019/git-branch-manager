// A repository, and a linked worktree, whose paths are Chinese -- read
// through the extern "C" surface exactly as the Dart side does, with every
// path handed over as UTF-8.
//
// Why this exists: on Windows a narrow `std::filesystem::path(std::string)`
// decodes with the active code page, not UTF-8 (FsUtil.h's pathFromUtf8 doc
// comment). Every path the capi receives is UTF-8, so a narrow construction
// gives the session a wide path that names a different directory. On a
// Western code page such as CI's 1252 the bytes still round-trip through a
// later `.string()` -- so git itself is handed the right path -- and what
// breaks is every place the core touches the filesystem with the wide path:
// MERGE_HEAD's stat (repo state), an untracked file's line count, the
// `.git/worktrees/*/gitdir` match behind the pending counts. Those are what
// each test below asserts. On macOS and Linux a narrow path is UTF-8 already,
// so these pass there with or without the fix; their red is Windows-only.
#include "capi/gbm_capi.h"
#include "support/GitCli.h"

#include <chrono>
#include <condition_variable>
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
    std::vector<int32_t> events;

    void add(int32_t eventType) {
        std::lock_guard<std::mutex> lock(mutex);
        events.push_back(eventType);
        cv.notify_all();
    }

    bool waitForType(int32_t type, std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] {
            for (const int32_t eventType : events) {
                if (eventType == type) return true;
            }
            return false;
        });
    }
};

void logCallback(
    GbmSessionHandle, int32_t eventType, const uint8_t* payload, int32_t, void* userData) {
    if (payload != nullptr) {
        gbm_free_event_payload(payload);
    }
    static_cast<EventLog*>(userData)->add(eventType);
}

/// The bytes the Dart side would send: UTF-8, whatever the platform.
std::string utf8(const std::filesystem::path& path) {
    const std::u8string text = path.u8string();
    return std::string(text.begin(), text.end());
}

std::string lastResultJson() {
    std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()),
                              static_cast<int32_t>(json.size()));
    return json;
}

class Utf8PathApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        const std::string name = info->name();
        const std::filesystem::path base = std::filesystem::temp_directory_path();
        repo_ =
            base / std::filesystem::path(u8"測試-倉庫-" + std::u8string(name.begin(), name.end()));
        linked_ =
            base / std::filesystem::path(u8"工作樹-一-" + std::u8string(name.begin(), name.end()));
        std::filesystem::remove_all(repo_);
        std::filesystem::remove_all(linked_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);
        std::ofstream(repo_ / "shared.txt") << "base\n";
        ASSERT_EQ(runGit({"add", "."}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Base commit"}), 0);

        session_ = gbm_session_open(utf8(repo_).c_str(), utf8(repo_ / ".git").c_str(), "");
        ASSERT_NE(session_, nullptr);
        gbm_register_callback(session_, &logCallback, &log_);
    }

    void TearDown() override {
        if (session_ != nullptr) {
            gbm_session_close(session_);
        }
        std::error_code ec;
        std::filesystem::remove_all(linked_, ec);
        std::filesystem::remove_all(repo_, ec);
    }

    int runGit(std::vector<std::string> args) { return GitCli::run(repo_, std::move(args)); }

    /// Leaves `shared.txt` conflicted and MERGE_HEAD on disk.
    void makeMergeConflict() {
        ASSERT_EQ(runGit({"checkout", "--quiet", "-b", "feature"}), 0);
        std::ofstream(repo_ / "shared.txt") << "feature change\n";
        ASSERT_EQ(runGit({"commit", "--quiet", "-am", "Feature edits shared.txt"}), 0);
        ASSERT_EQ(runGit({"checkout", "--quiet", "main"}), 0);
        std::ofstream(repo_ / "shared.txt") << "main change\n";
        ASSERT_EQ(runGit({"commit", "--quiet", "-am", "Main edits shared.txt"}), 0);
        ASSERT_NE(runGit({"merge", "--quiet", "feature"}), 0);
        ASSERT_TRUE(std::filesystem::exists(repo_ / ".git" / "MERGE_HEAD"));
    }

    std::filesystem::path repo_;
    std::filesystem::path linked_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(Utf8PathApiTest, AMergeInProgressIsSeenThroughAChinesePath) {
    makeMergeConflict();

    ASSERT_EQ(gbm_repo_state_json(session_), 0);
    const std::string json = lastResultJson();
    EXPECT_NE(json.find("\"isClean\":false"), std::string::npos)
        << "MERGE_HEAD exists, so the session must not report a clean state: " << json;
}

TEST_F(Utf8PathApiTest, TheWorkingCopyListsTheConflictAndCountsAnUntrackedFile) {
    makeMergeConflict();
    std::ofstream(repo_ / "untracked.txt") << "one\ntwo\n";

    gbm_working_copy_refresh(session_);
    ASSERT_TRUE(log_.waitForType(GBM_EVENT_WORKING_COPY_STATUS_UPDATED));
    ASSERT_EQ(gbm_working_copy_status_json(session_), 0);
    const std::string json = lastResultJson();

    EXPECT_NE(json.find("\"path\":\"shared.txt\""), std::string::npos) << json;
    EXPECT_NE(json.find("\"isConflicted\":true"), std::string::npos) << json;
    // Read from disk through paths.workDir() -- WorkingCopyStatus.cpp's
    // countUntrackedLines -- so a wide path naming the wrong directory
    // measures nothing and leaves 0.
    const std::size_t untracked = json.find("\"path\":\"untracked.txt\"");
    ASSERT_NE(untracked, std::string::npos) << json;
    // Searched from the untracked entry onward, and cut at the next entry:
    // the conflicted shared.txt carries its own unstagedAdded, which must not
    // be the one that satisfies this.
    const std::size_t nextEntry = json.find("\"path\":", untracked + 1);
    const std::string entry = json.substr(
        untracked, nextEntry == std::string::npos ? std::string::npos : nextEntry - untracked);
    EXPECT_NE(entry.find("\"unstagedAdded\":2,"), std::string::npos) << entry;
}

TEST_F(Utf8PathApiTest, ALinkedWorktreeAtAChinesePathIsMeasured) {
    ASSERT_EQ(runGit({"worktree", "add", "--quiet", "-b", "feature", utf8(linked_)}), 0);
    std::ofstream(linked_ / "shared.txt") << "changed\n";

    gbm_worktree_request_pending_counts(session_);
    ASSERT_TRUE(log_.waitForType(GBM_EVENT_WORKTREES_UPDATED));
    ASSERT_EQ(gbm_worktrees_json(session_), 0);
    const std::string json = lastResultJson();

    EXPECT_NE(json.find(utf8(linked_.filename())), std::string::npos)
        << "the linked worktree's path must come back as the same UTF-8: " << json;
    EXPECT_NE(json.find("\"pendingChanges\":1,\"pendingCountState\":\"measured\""),
              std::string::npos)
        << "expected the linked worktree measured at 1: " << json;
}

}  // namespace
}  // namespace gbm::capi
