// A read that throws on the shared read pool still answers. Without postRead()'s catch the
// pool's own one only logs (ThreadPool.cpp's workerLoop), and the Dart caller waiting on the
// reply -- History's isRefreshing, a dialog's Completer -- waits for good.
//
// The failures are injected with gbm_test_fail_read(), which arms one postRead() `where` name:
// only the read posted under that name throws, so the reads a session posts on its own cannot
// use it up.
#include "capi/JsonWriter.h"
#include "capi/Session.h"
#include "capi/gbm_capi.h"
#include "core/base/Error.h"
#include "support/GitCli.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdint>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <functional>
#include <gtest/gtest.h>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

GBM_API void gbm_test_fail_read(const char* where);
GBM_API void gbm_test_fail_register(void);

namespace gbm::capi {
namespace {

using ::gbm::testing::GitCli;
using Events = std::vector<std::pair<int32_t, std::string>>;

struct EventLog {
    std::mutex mutex;
    std::condition_variable cv;
    Events events;

    void add(int32_t eventType, std::string payload) {
        std::lock_guard<std::mutex> lock(mutex);
        events.emplace_back(eventType, std::move(payload));
        cv.notify_all();
    }

    bool waitFor(const std::function<bool(const Events&)>& pred,
                 std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] { return pred(events); });
    }

    Events snapshot() {
        std::lock_guard<std::mutex> lock(mutex);
        return events;
    }
};

void logCallback(GbmSessionHandle,
                 int32_t eventType,
                 const uint8_t* payload,
                 int32_t payloadLen,
                 void* userData) {
    std::string body;
    if (payload != nullptr) {
        body.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        gbm_free_event_payload(payload);
    }
    static_cast<EventLog*>(userData)->add(eventType, std::move(body));
}

void recordNativeError(const uint8_t* payload, int32_t payloadLen, void* userData) {
    auto* reports = static_cast<std::pair<std::mutex, std::vector<std::string>>*>(userData);
    std::lock_guard<std::mutex> lock(reports->first);
    reports->second.emplace_back(reinterpret_cast<const char*>(payload),
                                 static_cast<std::size_t>(payloadLen));
    gbm_free_event_payload(payload);
}

std::size_t countOf(const Events& events, int32_t type) {
    std::size_t n = 0;
    for (const auto& [eventType, payload] : events) {
        if (eventType == type) ++n;
    }
    return n;
}

const std::string* firstOf(const Events& events, int32_t type) {
    for (const auto& [eventType, payload] : events) {
        if (eventType == type) return &payload;
    }
    return nullptr;
}

bool contains(const std::string& haystack, const std::string& needle) {
    return haystack.find(needle) != std::string::npos;
}

class ReadFailureApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ =
            std::filesystem::temp_directory_path() / ("gbm-readfail-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);
        ASSERT_EQ(git({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(git({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(git({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(git({"config", "commit.gpgsign", "false"}), 0);
        std::ofstream(repo_ / "file.txt") << "hello\n";
        ASSERT_EQ(git({"add", "file.txt"}), 0);
        ASSERT_EQ(git({"commit", "--quiet", "-m", "Initial commit"}), 0);

        gbm_set_native_error_callback(&recordNativeError, &nativeErrors_);
        session_ = gbm_session_open(repo_.string().c_str(), (repo_ / ".git").string().c_str(), "");
        ASSERT_NE(session_, nullptr);
        gbm_register_callback(session_, &logCallback, &log_);
    }

    void TearDown() override {
        if (session_ != nullptr) {
            gbm_session_close(session_);
        }
        gbm_set_native_error_callback(nullptr, nullptr);
        gbm_test_fail_read("");
        std::error_code ec;
        std::filesystem::remove_all(repo_, ec);
    }

    int git(const std::vector<std::string>& args) { return GitCli::run(repo_, args); }

    /// A real commit, so a read that did not throw would answer with content and the
    /// assertions on the empty failure reply can tell the two apart.
    std::string headOid() { return GitCli::capture(repo_, {"rev-parse", "HEAD"}).firstLine(); }

    std::vector<std::string> nativeErrors() {
        std::lock_guard<std::mutex> lock(nativeErrors_.first);
        return nativeErrors_.second;
    }

    bool waitForEvent(int32_t type) {
        return log_.waitFor([type](const Events& events) { return countOf(events, type) > 0; });
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
    std::pair<std::mutex, std::vector<std::string>> nativeErrors_;
};

TEST_F(ReadFailureApiTest, AHistoryRefreshThatThrowsRepliesWithAnUnknownErrorAndIsStillLogged) {
    gbm_test_fail_read("Session::dispatchRefresh");
    gbm_history_refresh(session_);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));
    const std::string error = *firstOf(log_.snapshot(), GBM_EVENT_ERROR_OCCURRED);
    EXPECT_TRUE(contains(error, "\"codeName\":\"Unknown\"")) << error;
    EXPECT_TRUE(contains(error, "\"message\":\"The read failed unexpectedly\"")) << error;

    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"Session::dispatchRefresh\"")) << reports[0];
}

// The refresh's own terminal-path guard must run on the injected throw too, which fires
// before the body: otherwise RefreshCoalescer stays running and history never refreshes again.
TEST_F(ReadFailureApiTest, HistoryStillRefreshesAfterARefreshThatThrew) {
    gbm_test_fail_read("Session::dispatchRefresh");
    gbm_history_refresh(session_);
    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));

    const uint64_t second = gbm_history_refresh(session_);
    ASSERT_NE(second, 0u);
    const std::string covers = "\"coversRequest\":" + std::to_string(second);
    EXPECT_TRUE(log_.waitFor([&](const Events& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_REFS_UPDATED && contains(payload, covers)) return true;
        }
        return false;
    }));
}

/// Blame answers a failure on its own reply, under its key (read-failure-states-spec.html);
/// `"error":{` is a failed reply, `"error":null` a successful one.
std::size_t countFailedBlames(const Events& events) {
    std::size_t n = 0;
    for (const auto& [type, payload] : events) {
        if (type == GBM_EVENT_BLAME_READY && contains(payload, "\"error\":{")) ++n;
    }
    return n;
}

TEST_F(ReadFailureApiTest, ABlameThatThrowsRepliesUnderItsPathWithAnError) {
    gbm_test_fail_read("Session::requestBlame");
    EXPECT_EQ(gbm_request_blame(session_, "file.txt", "", 0, 0), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_BLAME_READY));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_BLAME_READY);
    EXPECT_TRUE(contains(reply, "\"path\":\"file.txt\"")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

// A throw before postRead's try -- its own make_shared, or the export's string temporaries --
// never reaches the pool or onFailure. The export answers it: 0, with the error staged, and no
// reply follows, so Dart sees exactly one of the two.
TEST_F(ReadFailureApiTest, ABlameThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::requestBlame");
    EXPECT_EQ(gbm_request_blame(session_, "file.txt", "", 0, 0), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_BLAME_READY), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_request_blame\"")) << reports[0];
}

// A hand-off that throws inside postRead's try is answered by onFailure on the caller's thread,
// so the export has queued an answer and returns 1 -- never 0 as well.
TEST_F(ReadFailureApiTest, ABlameThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::requestBlame");
    EXPECT_EQ(gbm_request_blame(session_, "file.txt", "", 0, 0), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_BLAME_READY));
    EXPECT_EQ(countFailedBlames(log_.snapshot()), 1u);
}

// Dart keeps a fetch-triggered preview's failure out of the banner by matching this argv
// (repo_session_repository.dart's _isSuppressedAutoPrunePreviewError); an error without it
// would surface as a banner and leave that remote's in-flight marker behind.
std::size_t countFailedFileHistories(const Events& events) {
    std::size_t n = 0;
    for (const auto& [type, payload] : events) {
        if (type == GBM_EVENT_FILE_HISTORY_READY && contains(payload, "\"error\":{")) ++n;
    }
    return n;
}

TEST_F(ReadFailureApiTest, AFileHistoryThatThrowsRepliesUnderItsPathWithAnError) {
    gbm_test_fail_read("Session::requestFileHistory");
    EXPECT_EQ(gbm_request_file_history(session_, "file.txt", ""), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_FILE_HISTORY_READY));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_FILE_HISTORY_READY);
    EXPECT_TRUE(contains(reply, "\"path\":\"file.txt\"")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, AFileHistoryThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::requestFileHistory");
    EXPECT_EQ(gbm_request_file_history(session_, "file.txt", ""), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_FILE_HISTORY_READY), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_request_file_history\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, AFileHistoryThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::requestFileHistory");
    EXPECT_EQ(gbm_request_file_history(session_, "file.txt", ""), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_FILE_HISTORY_READY));
    EXPECT_EQ(countFailedFileHistories(log_.snapshot()), 1u);
}

std::size_t countFailedLineHistories(const Events& events) {
    std::size_t n = 0;
    for (const auto& [type, payload] : events) {
        if (type == GBM_EVENT_LINE_HISTORY_READY && contains(payload, "\"error\":{")) ++n;
    }
    return n;
}

TEST_F(ReadFailureApiTest, ALineHistoryThatThrowsRepliesUnderItsRangeWithAnError) {
    gbm_test_fail_read("Session::requestLineHistory");
    EXPECT_EQ(gbm_request_line_history(session_, "file.txt", 3, 4, ""), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_LINE_HISTORY_READY));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_LINE_HISTORY_READY);
    EXPECT_TRUE(contains(reply, "\"path\":\"file.txt\",\"startLine\":3,\"endLine\":4")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, ALineHistoryThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::requestLineHistory");
    EXPECT_EQ(gbm_request_line_history(session_, "file.txt", 1, 1, ""), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_LINE_HISTORY_READY), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_request_line_history\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, ALineHistoryThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::requestLineHistory");
    EXPECT_EQ(gbm_request_line_history(session_, "file.txt", 1, 1, ""), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_LINE_HISTORY_READY));
    EXPECT_EQ(countFailedLineHistories(log_.snapshot()), 1u);
}

std::size_t countFailedReflogs(const Events& events) {
    std::size_t n = 0;
    for (const auto& [type, payload] : events) {
        if (type == GBM_EVENT_REFLOG_READY && contains(payload, "\"error\":{")) ++n;
    }
    return n;
}

TEST_F(ReadFailureApiTest, AReflogThatThrowsRepliesUnderItsRefWithAnError) {
    gbm_test_fail_read("Session::requestReflog");
    EXPECT_EQ(gbm_request_reflog(session_, "main"), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_REFLOG_READY));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_REFLOG_READY);
    EXPECT_TRUE(contains(reply, "\"ref\":\"main\"")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, AReflogThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::requestReflog");
    EXPECT_EQ(gbm_request_reflog(session_, ""), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_REFLOG_READY), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_request_reflog\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, AReflogThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::requestReflog");
    EXPECT_EQ(gbm_request_reflog(session_, ""), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_REFLOG_READY));
    EXPECT_EQ(countFailedReflogs(log_.snapshot()), 1u);
}

std::size_t countFailedRebasePlans(const Events& events) {
    std::size_t n = 0;
    for (const auto& [type, payload] : events) {
        if (type == GBM_EVENT_REBASE_PLAN_READY && contains(payload, "\"error\":{")) ++n;
    }
    return n;
}

TEST_F(ReadFailureApiTest, ARebasePlanThatThrowsRepliesUnderItsUpstreamWithAnError) {
    gbm_test_fail_read("Session::requestRebasePlan");
    EXPECT_EQ(gbm_request_rebase_plan(session_, "main"), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_REBASE_PLAN_READY));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_REBASE_PLAN_READY);
    EXPECT_TRUE(contains(reply, "\"upstream\":\"main\"")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, ARebasePlanThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::requestRebasePlan");
    EXPECT_EQ(gbm_request_rebase_plan(session_, "main"), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_REBASE_PLAN_READY), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_request_rebase_plan\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, ARebasePlanThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::requestRebasePlan");
    EXPECT_EQ(gbm_request_rebase_plan(session_, "main"), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_REBASE_PLAN_READY));
    EXPECT_EQ(countFailedRebasePlans(log_.snapshot()), 1u);
}

// A refreshed list that fails answers on its own *_UPDATED event with {"error": ...} instead of
// ERROR_OCCURRED: the panel keeps the list it has and says the refresh failed
// (read-failure-states-spec.html, R class). Success still sends no payload.
std::size_t countFailedRefreshes(const Events& events, int32_t type) {
    std::size_t n = 0;
    for (const auto& [eventType, payload] : events) {
        if (eventType == type && contains(payload, "\"error\":{")) ++n;
    }
    return n;
}

TEST_F(ReadFailureApiTest, AStashListThatThrowsRepliesOnStashesUpdatedWithAnError) {
    gbm_test_fail_read("Session::refreshStashes");
    EXPECT_EQ(gbm_stash_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_STASHES_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_STASHES_UPDATED);
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, AStashListThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::refreshStashes");
    EXPECT_EQ(gbm_stash_refresh(session_), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_STASHES_UPDATED), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_stash_refresh\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, AStashListThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::refreshStashes");
    EXPECT_EQ(gbm_stash_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_STASHES_UPDATED));
    EXPECT_EQ(countFailedRefreshes(log_.snapshot(), GBM_EVENT_STASHES_UPDATED), 1u);
}

// The ordinary failure path, not the injected throw: git itself fails once the repository is
// gone, and the reply is the same shape.
TEST_F(ReadFailureApiTest, AStashListGitRefusesRepliesOnStashesUpdatedWithItsError) {
    std::filesystem::remove_all(repo_ / ".git");
    EXPECT_EQ(gbm_stash_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_STASHES_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    EXPECT_EQ(countFailedRefreshes(events, GBM_EVENT_STASHES_UPDATED), 1u)
        << *firstOf(events, GBM_EVENT_STASHES_UPDATED);
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, AStashListThatSucceedsStillRepliesWithNoPayload) {
    EXPECT_EQ(gbm_stash_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_STASHES_UPDATED));
    EXPECT_EQ(*firstOf(log_.snapshot(), GBM_EVENT_STASHES_UPDATED), "");
}

// A stash diff answers under the index it was asked for, on success and on failure, so the
// panel can stop waiting for the stash it shows (read-failure-states-spec.html, C class).
TEST_F(ReadFailureApiTest, AStashDiffThatThrowsRepliesUnderItsIndexWithAnError) {
    gbm_test_fail_read("Session::requestStashDiff");
    EXPECT_EQ(gbm_stash_request_diff(session_, 3), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_STASH_DIFF_READY));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_STASH_DIFF_READY);
    EXPECT_TRUE(contains(reply, "\"index\":3")) << reply;
    EXPECT_TRUE(contains(reply, "\"diff\":null")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, AStashDiffThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::requestStashDiff");
    EXPECT_EQ(gbm_stash_request_diff(session_, 3), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_STASH_DIFF_READY), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_stash_request_diff\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, AStashDiffThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::requestStashDiff");
    EXPECT_EQ(gbm_stash_request_diff(session_, 3), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_STASH_DIFF_READY));
    EXPECT_EQ(countFailedRefreshes(log_.snapshot(), GBM_EVENT_STASH_DIFF_READY), 1u);
}

// The ordinary failure path: there is no stash@{3} in this repository, and git says so.
TEST_F(ReadFailureApiTest, AStashDiffGitRefusesRepliesUnderItsIndexWithItsError) {
    EXPECT_EQ(gbm_stash_request_diff(session_, 3), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_STASH_DIFF_READY));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_STASH_DIFF_READY);
    EXPECT_TRUE(contains(reply, "\"index\":3")) << reply;
    EXPECT_EQ(countFailedRefreshes(events, GBM_EVENT_STASH_DIFF_READY), 1u) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, AWorktreeListThatThrowsRepliesOnWorktreesUpdatedWithAnError) {
    gbm_test_fail_read("Session::refreshWorktrees");
    EXPECT_EQ(gbm_worktree_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_WORKTREES_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_WORKTREES_UPDATED);
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, AWorktreeListThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::refreshWorktrees");
    EXPECT_EQ(gbm_worktree_refresh(session_), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_WORKTREES_UPDATED), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_worktree_refresh\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, AWorktreeListThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::refreshWorktrees");
    EXPECT_EQ(gbm_worktree_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_WORKTREES_UPDATED));
    EXPECT_EQ(countFailedRefreshes(log_.snapshot(), GBM_EVENT_WORKTREES_UPDATED), 1u);
}

// The ordinary failure path: `git worktree list` itself fails once the repository is gone.
TEST_F(ReadFailureApiTest, AWorktreeListGitRefusesRepliesOnWorktreesUpdatedWithItsError) {
    std::filesystem::remove_all(repo_ / ".git");
    EXPECT_EQ(gbm_worktree_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_WORKTREES_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    EXPECT_EQ(countFailedRefreshes(events, GBM_EVENT_WORKTREES_UPDATED), 1u)
        << *firstOf(events, GBM_EVENT_WORKTREES_UPDATED);
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, AWorktreeListThatSucceedsStillRepliesWithNoPayload) {
    EXPECT_EQ(gbm_worktree_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_WORKTREES_UPDATED));
    EXPECT_EQ(*firstOf(log_.snapshot(), GBM_EVENT_WORKTREES_UPDATED), "");
}

TEST_F(ReadFailureApiTest, APendingCountThatThrowsRepliesOnWorktreesUpdatedWithAnError) {
    gbm_test_fail_read("Session::requestWorktreePendingCounts");
    EXPECT_EQ(gbm_worktree_request_pending_counts(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_WORKTREES_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_WORKTREES_UPDATED);
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, APendingCountThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::requestWorktreePendingCounts");
    EXPECT_EQ(gbm_worktree_request_pending_counts(session_), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_WORKTREES_UPDATED), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_worktree_request_pending_counts\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, APendingCountThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::requestWorktreePendingCounts");
    EXPECT_EQ(gbm_worktree_request_pending_counts(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_WORKTREES_UPDATED));
    EXPECT_EQ(countFailedRefreshes(log_.snapshot(), GBM_EVENT_WORKTREES_UPDATED), 1u);
}

// The ordinary failure path: `git worktree list` itself fails once the repository is gone.
TEST_F(ReadFailureApiTest, APendingCountGitRefusesRepliesOnWorktreesUpdatedWithItsError) {
    std::filesystem::remove_all(repo_ / ".git");
    EXPECT_EQ(gbm_worktree_request_pending_counts(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_WORKTREES_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    EXPECT_EQ(countFailedRefreshes(events, GBM_EVENT_WORKTREES_UPDATED), 1u)
        << *firstOf(events, GBM_EVENT_WORKTREES_UPDATED);
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, APendingCountThatSucceedsStillRepliesWithNoPayload) {
    EXPECT_EQ(gbm_worktree_request_pending_counts(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_WORKTREES_UPDATED));
    EXPECT_EQ(*firstOf(log_.snapshot(), GBM_EVENT_WORKTREES_UPDATED), "");
}

TEST_F(ReadFailureApiTest, ARemoteListThatThrowsRepliesOnRemotesUpdatedWithAnError) {
    gbm_test_fail_read("Session::refreshRemotes");
    EXPECT_EQ(gbm_remote_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_REMOTES_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_REMOTES_UPDATED);
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, ARemoteListThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::refreshRemotes");
    EXPECT_EQ(gbm_remote_refresh(session_), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_REMOTES_UPDATED), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_remote_refresh\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, ARemoteListThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::refreshRemotes");
    EXPECT_EQ(gbm_remote_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_REMOTES_UPDATED));
    EXPECT_EQ(countFailedRefreshes(log_.snapshot(), GBM_EVENT_REMOTES_UPDATED), 1u);
}

// The ordinary failure path: `git remote -v` itself fails once the repository is gone.
TEST_F(ReadFailureApiTest, ARemoteListGitRefusesRepliesOnRemotesUpdatedWithItsError) {
    std::filesystem::remove_all(repo_ / ".git");
    EXPECT_EQ(gbm_remote_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_REMOTES_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    EXPECT_EQ(countFailedRefreshes(events, GBM_EVENT_REMOTES_UPDATED), 1u) << *firstOf(events, GBM_EVENT_REMOTES_UPDATED);
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, ARemoteListThatSucceedsStillRepliesWithNoPayload) {
    EXPECT_EQ(gbm_remote_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_REMOTES_UPDATED));
    EXPECT_EQ(*firstOf(log_.snapshot(), GBM_EVENT_REMOTES_UPDATED), "");
}

TEST_F(ReadFailureApiTest, ABisectStatusThatThrowsRepliesOnBisectStatusUpdatedWithAnError) {
    gbm_test_fail_read("Session::refreshBisectStatus");
    EXPECT_EQ(gbm_bisect_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_BISECT_STATUS_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_BISECT_STATUS_UPDATED);
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, ABisectStatusThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::refreshBisectStatus");
    EXPECT_EQ(gbm_bisect_refresh(session_), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_BISECT_STATUS_UPDATED), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_bisect_refresh\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, ABisectStatusThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::refreshBisectStatus");
    EXPECT_EQ(gbm_bisect_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_BISECT_STATUS_UPDATED));
    EXPECT_EQ(countFailedRefreshes(log_.snapshot(), GBM_EVENT_BISECT_STATUS_UPDATED), 1u);
}

// The ordinary failure path. With no BISECT_LOG the status is read without running git at all,
// so the log has to exist and `git bisect log` still fail: a directory in its place does both
// (measured, git 2.56.1: exit 1, nothing on stdout).
TEST_F(ReadFailureApiTest, ABisectStatusGitRefusesRepliesOnBisectStatusUpdatedWithItsError) {
    std::filesystem::create_directory(repo_ / ".git" / "BISECT_LOG");
    EXPECT_EQ(gbm_bisect_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_BISECT_STATUS_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    EXPECT_EQ(countFailedRefreshes(events, GBM_EVENT_BISECT_STATUS_UPDATED), 1u) << *firstOf(events, GBM_EVENT_BISECT_STATUS_UPDATED);
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, ABisectStatusThatSucceedsStillRepliesWithNoPayload) {
    EXPECT_EQ(gbm_bisect_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_BISECT_STATUS_UPDATED));
    EXPECT_EQ(*firstOf(log_.snapshot(), GBM_EVENT_BISECT_STATUS_UPDATED), "");
}

TEST_F(ReadFailureApiTest, ASubmoduleListThatThrowsRepliesOnSubmodulesUpdatedWithAnError) {
    gbm_test_fail_read("Session::refreshSubmodules");
    EXPECT_EQ(gbm_submodule_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_SUBMODULES_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_SUBMODULES_UPDATED);
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, ASubmoduleListThatCannotBeHandedToPostReadReturnsZeroAndNeverReplies) {
    gbm_test_fail_read("pre:Session::refreshSubmodules");
    EXPECT_EQ(gbm_submodule_refresh(session_), 0);
    EXPECT_GT(gbm_last_result_json_len(), 0);

    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_SUBMODULES_UPDATED), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_submodule_refresh\"")) << reports[0];
}

TEST_F(ReadFailureApiTest, ASubmoduleListThatCannotBePostedRepliesWithAnErrorAndReturnsOne) {
    gbm_test_fail_read("post:Session::refreshSubmodules");
    EXPECT_EQ(gbm_submodule_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_SUBMODULES_UPDATED));
    EXPECT_EQ(countFailedRefreshes(log_.snapshot(), GBM_EVENT_SUBMODULES_UPDATED), 1u);
}

// The ordinary failure path: `git submodule status` itself fails once the repository is gone.
TEST_F(ReadFailureApiTest, ASubmoduleListGitRefusesRepliesOnSubmodulesUpdatedWithItsError) {
    std::filesystem::remove_all(repo_ / ".git");
    EXPECT_EQ(gbm_submodule_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_SUBMODULES_UPDATED));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    EXPECT_EQ(countFailedRefreshes(events, GBM_EVENT_SUBMODULES_UPDATED), 1u) << *firstOf(events, GBM_EVENT_SUBMODULES_UPDATED);
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, ASubmoduleListThatSucceedsStillRepliesWithNoPayload) {
    EXPECT_EQ(gbm_submodule_refresh(session_), 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_SUBMODULES_UPDATED));
    EXPECT_EQ(*firstOf(log_.snapshot(), GBM_EVENT_SUBMODULES_UPDATED), "");
}

TEST_F(ReadFailureApiTest, APrunePreviewThatThrowsCarriesItsDryRunArgv) {
    gbm_test_fail_read("Session::requestRemotePrunePreview");
    gbm_request_remote_prune_preview(session_, "origin");

    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));
    const std::string error = *firstOf(log_.snapshot(), GBM_EVENT_ERROR_OCCURRED);
    EXPECT_TRUE(contains(error, "\"argv\":[\"git\",\"remote\",\"prune\",\"origin\",\"--dry-run\"]"))
        << error;
}

TEST_F(ReadFailureApiTest, AnArmedNameIsNotUsedUpByAnotherRead) {
    gbm_test_fail_read("Session::requestBlame");
    const uint64_t refresh = gbm_history_refresh(session_);
    const std::string covers = "\"coversRequest\":" + std::to_string(refresh);
    ASSERT_TRUE(log_.waitFor([&](const Events& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_REFS_UPDATED && contains(payload, covers)) return true;
        }
        return false;
    }));
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_ERROR_OCCURRED), 0u);

    gbm_request_blame(session_, "file.txt", "", 0, 0);
    ASSERT_TRUE(waitForEvent(GBM_EVENT_BLAME_READY));
    EXPECT_EQ(countFailedBlames(log_.snapshot()), 1u);
}

TEST_F(ReadFailureApiTest, AnArmedNameFailsOneReadOnly) {
    gbm_test_fail_read("Session::requestBlame");
    gbm_request_blame(session_, "file.txt", "", 0, 0);
    ASSERT_TRUE(waitForEvent(GBM_EVENT_BLAME_READY));

    gbm_request_blame(session_, "file.txt", "", 0, 0);
    ASSERT_TRUE(log_.waitFor(
        [](const Events& events) { return countOf(events, GBM_EVENT_BLAME_READY) >= 2; }));
    EXPECT_EQ(countFailedBlames(log_.snapshot()), 1u);
}

// The reads below answer a failure in their own reply rather than (or as well as) on
// GBM_EVENT_ERROR_OCCURRED, because their caller waits on that reply by a key the error
// event does not carry. A throw has to answer the same way, or the caller waits for good.

std::size_t indexOf(const Events& events, int32_t type) {
    for (std::size_t i = 0; i < events.size(); ++i) {
        if (events[i].first == type) return i;
    }
    return events.size();
}

TEST_F(ReadFailureApiTest, ABranchDeletionProbeThatThrowsRepliesUnderItsRequestId) {
    gbm_test_fail_read("Session::requestBranchDeletionProbe");
    const char* names[] = {"main"};
    gbm_request_branch_deletion_probe(session_, 4242, names, 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_BRANCH_DELETION_PROBE_READY));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_BRANCH_DELETION_PROBE_READY);
    EXPECT_TRUE(contains(reply, "\"requestId\":4242")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_TRUE(contains(reply, "\"probes\":[]")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, AnExportThatThrowsRepliesUnderItsDestinationAsNotSucceeded) {
    gbm_test_fail_read("Session::exportFileAtRevision");
    const std::string dest = (repo_ / "exported.txt").string();
    gbm_export_file_at_revision(session_, "HEAD", "file.txt", dest.c_str());

    ASSERT_TRUE(waitForEvent(GBM_EVENT_FILE_AT_REVISION_EXPORTED));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_FILE_AT_REVISION_EXPORTED);
    std::string destJson;
    jsonAppendEscaped(destJson, dest);
    EXPECT_TRUE(contains(reply, "\"destPath\":" + destJson)) << reply;
    EXPECT_TRUE(contains(reply, "\"succeeded\":false")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, ASquashMessageThatThrowsReportsTheErrorFirstThenRepliesForItsSource) {
    gbm_test_fail_read("Session::requestSquashMessage");
    gbm_request_squash_message(session_, "feature");

    ASSERT_TRUE(waitForEvent(GBM_EVENT_SQUASH_MESSAGE_READY));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_SQUASH_MESSAGE_READY);
    EXPECT_TRUE(contains(reply, "\"source\":\"feature\"")) << reply;
    EXPECT_TRUE(contains(reply, "\"message\":\"\"")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    ASSERT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 1u);
    EXPECT_LT(indexOf(events, GBM_EVENT_ERROR_OCCURRED),
              indexOf(events, GBM_EVENT_SQUASH_MESSAGE_READY));
}

TEST_F(ReadFailureApiTest, APreparedMessageThatThrowsReportsTheErrorFirstThenReplies) {
    gbm_test_fail_read("Session::requestPreparedMessage");
    gbm_request_prepared_message(session_);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_PREPARED_MESSAGE_READY));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_PREPARED_MESSAGE_READY);
    EXPECT_TRUE(contains(reply, "\"message\":\"\"")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    ASSERT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 1u);
    EXPECT_LT(indexOf(events, GBM_EVENT_ERROR_OCCURRED),
              indexOf(events, GBM_EVENT_PREPARED_MESSAGE_READY));
}

TEST_F(ReadFailureApiTest, AWorkingTreeReadThatThrowsRepliesNotEditableForItsPath) {
    gbm_test_fail_read("Session::requestWorkingTreeContent");
    gbm_request_working_tree_content(session_, "file.txt");

    ASSERT_TRUE(waitForEvent(GBM_EVENT_WORKING_TREE_CONTENT_READY));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_WORKING_TREE_CONTENT_READY);
    EXPECT_EQ(reply, "{\"path\":\"file.txt\",\"content\":\"\",\"editable\":false}");
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, AnOriginalOperationMessageThatThrowsRepliesEmpty) {
    // A message on disk, so an untouched read would reply with it.
    std::ofstream(repo_ / ".git" / "MERGE_MSG") << "Merge branch 'feature'\n";
    gbm_test_fail_read("Session::requestOriginalOperationMessage");
    gbm_request_original_operation_message(session_);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY));
    const Events events = log_.snapshot();
    EXPECT_EQ(*firstOf(events, GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY), "{\"message\":\"\"}");
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

// gbm_capi.h promises both of these always reply and never raise the error event.
TEST_F(ReadFailureApiTest, CommitMetaThatThrowsRepliesWithAnEmptyBatch) {
    gbm_test_fail_read("Session::requestCommitMeta");
    const std::string head = headOid();
    const char* oids[] = {head.c_str()};
    gbm_request_commit_meta(session_, oids, 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_COMMIT_META_READY));
    const Events events = log_.snapshot();
    EXPECT_EQ(*firstOf(events, GBM_EVENT_COMMIT_META_READY), "[]");
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST_F(ReadFailureApiTest, CommitFileCountsThatThrowRepliesWithAnEmptyBatch) {
    gbm_test_fail_read("Session::requestCommitFileCounts");
    const std::string head = headOid();
    const char* oids[] = {head.c_str()};
    gbm_request_commit_file_counts(session_, oids, 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_COMMIT_FILE_COUNTS_READY));
    const Events events = log_.snapshot();
    EXPECT_EQ(*firstOf(events, GBM_EVENT_COMMIT_FILE_COUNTS_READY), "[]");
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

// An LFS read that fails is not an error: the refresh still fires GBM_EVENT_LFS_UPDATED with
// whatever it had (Session::refreshLfs), so a throw answers the same way.
TEST_F(ReadFailureApiTest, AnLfsRefreshThatThrowsStillFiresLfsUpdatedAndNoError) {
    gbm_test_fail_read("Session::refreshLfs");
    gbm_lfs_refresh(session_);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_LFS_UPDATED));
    sharedReadPool().drain();
    EXPECT_EQ(countOf(log_.snapshot(), GBM_EVENT_ERROR_OCCURRED), 0u);
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"Session::refreshLfs\"")) << reports[0];
}

// Reads posted from several threads at once compete for the armed name: compare-and-clear under
// one mutex lets exactly one of them take it, and every other one answers normally.
TEST_F(ReadFailureApiTest, ConcurrentBlamesFailOnlyTheOneThatTookTheArmedName) {
    constexpr int kReads = 16;
    gbm_test_fail_read("Session::requestBlame");
    std::vector<std::thread> posters;
    for (int i = 0; i < kReads; ++i) {
        posters.emplace_back([this] { gbm_request_blame(session_, "file.txt", "", 0, 0); });
    }
    for (std::thread& poster : posters) poster.join();

    ASSERT_TRUE(log_.waitFor([](const Events& events) {
        return countOf(events, GBM_EVENT_BLAME_READY) >= static_cast<std::size_t>(kReads);
    }));
    sharedReadPool().drain();
    const Events events = log_.snapshot();
    EXPECT_EQ(countFailedBlames(events), 1u);
    EXPECT_EQ(countOf(events, GBM_EVENT_BLAME_READY), static_cast<std::size_t>(kReads));
    EXPECT_EQ(nativeErrors().size(), 1u);
}

struct PostReadProbe {
    std::mutex mutex;
    std::condition_variable cv;
    int always = 0;
    int failures = 0;

    void bump(int& counter) {
        std::lock_guard<std::mutex> lock(mutex);
        ++counter;
        cv.notify_all();
    }

    bool waitForAlways(int n) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, std::chrono::seconds(10), [&] { return always >= n; });
    }
};

TEST(PostRead, RunsOnAlwaysOnceOnEveryPath) {
    PostReadProbe probe;
    const auto onFailure = [&](const GitError&) { probe.bump(probe.failures); };
    const auto onAlways = [&] { probe.bump(probe.always); };

    postRead(ReadLane::Back, "PostReadTest::succeeds", [] {}, onFailure, onAlways);
    postRead(
        ReadLane::Back,
        "PostReadTest::throws",
        [] { throw std::runtime_error("body"); },
        onFailure,
        onAlways);
    gbm_test_fail_read("PostReadTest::injected");
    postRead(ReadLane::Front, "PostReadTest::injected", [] {}, onFailure, onAlways);

    ASSERT_TRUE(probe.waitForAlways(3));
    sharedReadPool().drain();
    std::lock_guard<std::mutex> lock(probe.mutex);
    EXPECT_EQ(probe.always, 3);
    EXPECT_EQ(probe.failures, 2);
}

// Posters on several threads, bodies that throw, and a thread re-arming the switch the whole
// time: whichever read takes a failure, each one answers exactly once -- success or failure,
// never both and never neither -- and runs onAlways once.
TEST(PostRead, ConcurrentReadsEachAnswerExactlyOnce) {
    constexpr int kPosters = 8;
    constexpr int kPerPoster = 32;
    constexpr int kReads = kPosters * kPerPoster;
    std::vector<std::atomic<int>> successes(kReads);
    std::vector<std::atomic<int>> failures(kReads);
    std::vector<std::atomic<int>> always(kReads);
    std::atomic<int> answered{0};
    std::atomic<bool> posting{true};

    std::thread arming([&] {
        for (int k = 0; posting; k = (k + 7) % kReads) {
            gbm_test_fail_read(("PostReadTest::race-" + std::to_string(k)).c_str());
        }
    });
    std::vector<std::thread> posters;
    for (int p = 0; p < kPosters; ++p) {
        posters.emplace_back([&, p] {
            for (int j = 0; j < kPerPoster; ++j) {
                const int k = p * kPerPoster + j;
                postRead(
                    k % 2 == 0 ? ReadLane::Front : ReadLane::Back,
                    "PostReadTest::race-" + std::to_string(k),
                    [&, k] {
                        if (k % 5 == 0) throw std::runtime_error("body");
                        ++successes[k];
                    },
                    [&, k](const GitError&) { ++failures[k]; },
                    [&, k] {
                        ++always[k];
                        ++answered;
                    });
            }
        });
    }
    for (std::thread& poster : posters) poster.join();
    sharedReadPool().drain();
    posting = false;
    arming.join();
    gbm_test_fail_read("");

    EXPECT_EQ(answered.load(), kReads);
    int failed = 0;
    for (int k = 0; k < kReads; ++k) {
        EXPECT_EQ(always[k].load(), 1) << k;
        EXPECT_EQ(successes[k].load() + failures[k].load(), 1) << k;
        if (k % 5 == 0) {
            EXPECT_EQ(failures[k].load(), 1) << k;
        }
        failed += failures[k].load();
    }
    EXPECT_GE(failed, (kReads + 4) / 5);
}

// A `post:` name fails the hand-off itself, after the read has been moved into the pool's
// argument -- where an allocation failure in the pool's push_back would land. Nothing reaches a
// worker, so postRead answers inline, on the caller's thread.

TEST_F(ReadFailureApiTest, AHistoryRefreshThatCannotBePostedRepliesWithAnErrorAndIsLogged) {
    gbm_test_fail_read("post:Session::dispatchRefresh");
    gbm_history_refresh(session_);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));
    const std::string error = *firstOf(log_.snapshot(), GBM_EVENT_ERROR_OCCURRED);
    EXPECT_TRUE(contains(error, "\"codeName\":\"Unknown\"")) << error;
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"Session::dispatchRefresh\"")) << reports[0];
}

// finishRefresh is the refresh's onAlways: skipped, the coalescer stays running and every later
// request folds into a dirty bit nothing drives.
TEST_F(ReadFailureApiTest, HistoryStillRefreshesAfterARefreshThatCannotBePosted) {
    gbm_test_fail_read("post:Session::dispatchRefresh");
    gbm_history_refresh(session_);
    ASSERT_TRUE(waitForEvent(GBM_EVENT_ERROR_OCCURRED));

    const uint64_t second = gbm_history_refresh(session_);
    ASSERT_NE(second, 0u);
    const std::string covers = "\"coversRequest\":" + std::to_string(second);
    EXPECT_TRUE(log_.waitFor([&](const Events& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_REFS_UPDATED && contains(payload, covers)) return true;
        }
        return false;
    }));
}

TEST_F(ReadFailureApiTest, ABranchDeletionProbeThatCannotBePostedRepliesUnderItsRequestId) {
    gbm_test_fail_read("post:Session::requestBranchDeletionProbe");
    const char* names[] = {"main"};
    gbm_request_branch_deletion_probe(session_, 4243, names, 1);

    ASSERT_TRUE(waitForEvent(GBM_EVENT_BRANCH_DELETION_PROBE_READY));
    const Events events = log_.snapshot();
    const std::string reply = *firstOf(events, GBM_EVENT_BRANCH_DELETION_PROBE_READY);
    EXPECT_TRUE(contains(reply, "\"requestId\":4243")) << reply;
    EXPECT_TRUE(contains(reply, "\"codeName\":\"Unknown\"")) << reply;
    EXPECT_EQ(countOf(events, GBM_EVENT_ERROR_OCCURRED), 0u);
}

TEST(PostRead, AReadThatCannotBePostedAnswersOnceAndRunsOnAlwaysOnce) {
    PostReadProbe probe;
    std::atomic<bool> taskRan{false};
    gbm_test_fail_read("post:PostReadTest::unposted");
    postRead(
        ReadLane::Back,
        "PostReadTest::unposted",
        [&] { taskRan = true; },
        [&](const GitError&) { probe.bump(probe.failures); },
        [&] { probe.bump(probe.always); });
    sharedReadPool().drain();

    EXPECT_FALSE(taskRan);
    std::lock_guard<std::mutex> lock(probe.mutex);
    EXPECT_EQ(probe.failures, 1);
    EXPECT_EQ(probe.always, 1);
}

TEST(PostRead, AFailureReplyThatThrowsIsLoggedAndGoesNoFurther) {
    std::pair<std::mutex, std::vector<std::string>> reports;
    gbm_set_native_error_callback(&recordNativeError, &reports);
    std::atomic<bool> nextRan{false};

    postRead(
        ReadLane::Back,
        "PostReadTest::body",
        [] { throw std::runtime_error("body"); },
        [](const GitError&) { throw std::runtime_error("reply"); });
    postRead(ReadLane::Back, "PostReadTest::next", [&] { nextRan = true; }, [](const GitError&) {});
    sharedReadPool().drain();
    gbm_set_native_error_callback(nullptr, nullptr);

    EXPECT_TRUE(nextRan);
    std::lock_guard<std::mutex> lock(reports.first);
    ASSERT_EQ(reports.second.size(), 2u);
    EXPECT_TRUE(contains(reports.second[0], "\"where\":\"PostReadTest::body\""))
        << reports.second[0];
    EXPECT_TRUE(contains(reports.second[1], "\"where\":\"postRead failure reply\""))
        << reports.second[1];
}


// Gap 3a: a registration that fails leaves the session silent for good, so the export
// says so and Dart treats it as a failed open.
TEST_F(ReadFailureApiTest, ACallbackRegistrationThatFailsSaysSoAndLeavesTheError) {
    gbm_test_fail_register();
    EXPECT_EQ(gbm_register_callback(session_, &logCallback, &log_), 0);

    std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
    gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
    EXPECT_TRUE(contains(json, "Native error in gbm_register_callback")) << json;
    const std::vector<std::string> reports = nativeErrors();
    ASSERT_EQ(reports.size(), 1u);
    EXPECT_TRUE(contains(reports[0], "\"where\":\"gbm_register_callback\"")) << reports[0];

    EXPECT_EQ(gbm_register_callback(session_, &logCallback, &log_), 1) << "one arm fails one call";
}

// Measures what a refresh does when every hand-off to the pool fails: each failed
// post replies and runs finishRefresh, which re-arms only for a request that arrived
// meanwhile. The number of attempts must be bounded by the requests, not grow on its own.
// Spaced wider than RefreshCoalescer::kDelay (150 ms) so no request is debounced into
// another: the worst case, one attempt per request. (At 30 ms, 20 requests made 1.)
TEST_F(ReadFailureApiTest, ARefreshThatCanNeverBePostedRetriesNoMoreThanItIsAsked) {
    constexpr int kRequests = 20;
    gbm_test_fail_read("sticky:post:Session::dispatchRefresh");
    for (int i = 0; i < kRequests; ++i) {
        gbm_history_refresh(session_);
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
    std::this_thread::sleep_for(std::chrono::seconds(2));
    const auto attempts = [this] {
        std::size_t n = 0;
        for (const std::string& report : nativeErrors()) {
            if (contains(report, "\"where\":\"Session::dispatchRefresh\"")) ++n;
        }
        return n;
    };
    const std::size_t settled = attempts();
    std::this_thread::sleep_for(std::chrono::seconds(1));

    std::printf("[measure] %d requests -> %zu failed hand-offs\n", kRequests, settled);
    EXPECT_GE(settled, 1u);
    EXPECT_LE(settled, static_cast<std::size_t>(kRequests));
    EXPECT_EQ(attempts(), settled) << "attempts kept growing with no new request";
}

}  // namespace
}  // namespace gbm::capi
