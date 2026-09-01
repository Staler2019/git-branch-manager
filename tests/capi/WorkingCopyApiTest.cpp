// Integration tests for the M2 working-copy/diff/commit slice of the
// extern "C" surface (gbm_capi.h), against a real repository with
// uncommitted changes -- the working-copy analog of SessionApiTest.cpp.
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

    /// Every payload seen for `type`, in arrival order.
    std::vector<std::string> payloadsOfType(int32_t type) {
        std::lock_guard<std::mutex> lock(mutex);
        std::vector<std::string> out;
        for (const auto& [eventType, payload] : events) {
            if (eventType == type) out.push_back(payload);
        }
        return out;
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

class WorkingCopyApiTest : public ::testing::Test {
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
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-wc-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        std::ofstream(repo_ / "committed.txt") << "line1\n";
        ASSERT_EQ(runGit({"add", "committed.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Initial commit"}), 0);

        // Uncommitted state the tests exercise: a modified tracked file plus
        // a new untracked one, so status() has both a staged-candidate and
        // an untracked entry from the very first refresh.
        std::ofstream(repo_ / "committed.txt") << "line1\nline2\n";
        std::ofstream(repo_ / "untracked.txt") << "new file\n";

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
    }

    /// Fixture git, without a shell in the middle -- see tests/support/GitCli.h
    /// for why that matters (one process instead of two, and no per-platform
    /// quoting hazard).
    int runGit(std::vector<std::string> args) {
        return GitCli::run(repo_, std::move(args));
    }

    std::string statusJson() {
        [[maybe_unused]] const int32_t rc = gbm_working_copy_status_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    /// Triggers gbm_working_copy_diff() and returns the JSON payload of the
    /// next GBM_EVENT_WORKING_COPY_DIFF_READY, cleared from the log first so
    /// a later call in the same test can't see a stale earlier reply.
    std::string requestDiffJson(const std::string& path, bool staged) {
        {
            std::lock_guard<std::mutex> lock(log_.mutex);
            log_.events.clear();
        }
        gbm_working_copy_diff(session_, path.c_str(), staged ? 1 : 0);
        const bool arrived = log_.waitFor([](const auto& events) {
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_WORKING_COPY_DIFF_READY) return true;
            }
            return false;
        });
        if (!arrived) return "";
        return log_.payloadsOfType(GBM_EVENT_WORKING_COPY_DIFF_READY).back();
    }

    bool waitForWorkingCopyOperationFinished() {
        return log_.waitFor([](const auto& events) {
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
            }
            return false;
        });
    }

    /// Waits for GBM_EVENT_WORKING_COPY_OPERATION_FINISHED and returns whether
    /// it reported success, printing the outcome JSON (including any git
    /// error) on failure. Callers that expect the operation to succeed should
    /// use this instead of waitForWorkingCopyOperationFinished() alone -- that
    /// one only proves the event arrived, not that the underlying git command
    /// did what was asked, so a real failure would otherwise only surface as
    /// a confusing mismatch several lines later in an unrelated diff assertion.
    bool waitForWorkingCopyOperationSucceeded() {
        if (!waitForWorkingCopyOperationFinished()) return false;
        const std::vector<std::string> outcomes =
            log_.payloadsOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
        if (outcomes.empty()) return false;
        const bool succeeded = outcomes.back().find("\"succeeded\":true") != std::string::npos;
        if (!succeeded) {
            ADD_FAILURE() << "working copy operation did not succeed: " << outcomes.back();
        }
        return succeeded;
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(WorkingCopyApiTest, RefreshReportsModifiedAndUntrackedFiles) {
    gbm_working_copy_refresh(session_);
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) { return !events.empty() && events.back().first == GBM_EVENT_WORKING_COPY_STATUS_UPDATED; }));

    const std::string json = statusJson();
    EXPECT_NE(json.find("\"path\":\"committed.txt\""), std::string::npos) << json;
    EXPECT_NE(json.find("\"path\":\"untracked.txt\""), std::string::npos) << json;
    EXPECT_NE(json.find("\"untracked\":true"), std::string::npos) << json;
}

TEST_F(WorkingCopyApiTest, StatusJsonCarriesPerFileLineCounts) {
    gbm_working_copy_refresh(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        return !events.empty() && events.back().first == GBM_EVENT_WORKING_COPY_STATUS_UPDATED;
    }));

    const std::string json = statusJson();

    // committed.txt gained "line2" in the work tree and nothing is staged.
    const std::size_t committed = json.find("\"path\":\"committed.txt\"");
    ASSERT_NE(committed, std::string::npos) << json;
    const std::size_t committedEnd = json.find("}", committed);
    const std::string committedEntry = json.substr(committed, committedEnd - committed);
    EXPECT_NE(committedEntry.find("\"unstagedAdded\":1"), std::string::npos) << committedEntry;
    EXPECT_NE(committedEntry.find("\"unstagedRemoved\":0"), std::string::npos) << committedEntry;
    EXPECT_NE(committedEntry.find("\"stagedAdded\":0"), std::string::npos) << committedEntry;
    EXPECT_NE(committedEntry.find("\"stagedRemoved\":0"), std::string::npos) << committedEntry;

    // untracked.txt is one line, counted by reading the file.
    const std::size_t untracked = json.find("\"path\":\"untracked.txt\"");
    ASSERT_NE(untracked, std::string::npos) << json;
    const std::size_t untrackedEnd = json.find("}", untracked);
    const std::string untrackedEntry = json.substr(untracked, untrackedEnd - untracked);
    EXPECT_NE(untrackedEntry.find("\"unstagedAdded\":1"), std::string::npos) << untrackedEntry;
    EXPECT_NE(untrackedEntry.find("\"unstagedRemoved\":0"), std::string::npos) << untrackedEntry;
}

TEST_F(WorkingCopyApiTest, WorkingCopyDiffReportsAddedLine) {
    gbm_working_copy_diff(session_, "committed.txt", /*staged=*/0);

    // Waits specifically for GBM_EVENT_WORKING_COPY_DIFF_READY, not just "any
    // event": the session now also emits GBM_EVENT_OPERATION_LOG_RECORD for
    // the underlying `git diff` subprocess (see Session::
    // dispatchOperationLogRecord()), which arrives first and would otherwise
    // satisfy a looser "events non-empty" predicate before the diff itself
    // has actually arrived.
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_DIFF_READY) return true;
        }
        return false;
    }));
    const std::vector<std::string> diffs = log_.payloadsOfType(GBM_EVENT_WORKING_COPY_DIFF_READY);
    ASSERT_EQ(diffs.size(), 1u);
    EXPECT_NE(diffs[0].find("\"path\":\"committed.txt\""), std::string::npos) << diffs[0];
    EXPECT_NE(diffs[0].find("\"staged\":false"), std::string::npos) << diffs[0];
    EXPECT_NE(diffs[0].find("\"text\":\"line2\""), std::string::npos) << diffs[0];
}

TEST_F(WorkingCopyApiTest, WorkingCopyDiffReportsAnUntrackedFileAsWhollyAdded) {
    // The fixture's untracked.txt has sat here unused by any diff test since
    // this file was written, which is how the gap survived: `git diff` prints
    // nothing for a path in neither the index nor HEAD, so the reply arrived
    // as an ordinary empty diff and the Working Copy pane drew "Nothing
    // unstaged" over a file whose own row badge said +1.
    //
    // This is the FFI tier rather than the DiffService tier because the two
    // can disagree: the fields have to survive JsonCodec and the event
    // payload, not just exist in the C++ struct.
    const std::string json = requestDiffJson("untracked.txt", /*staged=*/false);
    ASSERT_FALSE(json.empty());

    EXPECT_NE(json.find("\"path\":\"untracked.txt\""), std::string::npos) << json;
    EXPECT_NE(json.find("\"staged\":false"), std::string::npos) << json;
    EXPECT_NE(json.find("\"truncated\":false"), std::string::npos) << json;
    // kind 1 == FileChangeKind::Added.
    EXPECT_NE(json.find("\"kind\":1"), std::string::npos) << json;
    EXPECT_NE(json.find("\"displayPath\":\"untracked.txt\""), std::string::npos) << json;
    EXPECT_NE(json.find("\"text\":\"new file\""), std::string::npos) << json;
}

TEST_F(WorkingCopyApiTest, WorkingCopyDiffOfAnUnchangedTrackedFileStaysEmpty) {
    ASSERT_EQ(runGit({"checkout", "--", "committed.txt"}), 0);

    // The negative half of the test above, at the same tier: a tracked file
    // with nothing to stage also produces an empty `git diff`, and answering
    // that one with --no-index would draw the whole file as newly added.
    const std::string json = requestDiffJson("committed.txt", /*staged=*/false);
    ASSERT_FALSE(json.empty());
    EXPECT_NE(json.find("\"files\":[]"), std::string::npos) << json;
    EXPECT_NE(json.find("\"truncated\":false"), std::string::npos) << json;
}

TEST_F(WorkingCopyApiTest, StageFilesMovesFileIntoStagedState) {
    const char* paths[] = {"committed.txt"};
    gbm_stage_files(session_, paths, 1);

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    }));
    // stageFiles() chains a refresh on success -- wait for that too before
    // reading status.
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_STATUS_UPDATED) return true;
        }
        return false;
    }));

    const std::string json = statusJson();
    EXPECT_NE(json.find("\"path\":\"committed.txt\""), std::string::npos) << json;
    EXPECT_NE(json.find("\"staged\":true"), std::string::npos) << json;
}

TEST_F(WorkingCopyApiTest, CommitChangesCreatesCommitAndRefreshesGraph) {
    const char* paths[] = {"committed.txt"};
    gbm_stage_files(session_, paths, 1);
    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    }));

    gbm_commit_changes(session_, "Second commit", /*amend=*/0, /*signOff=*/0);

    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) {
            int32_t operationFinishedCount = 0;
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) ++operationFinishedCount;
            }
            return operationFinishedCount >= 2;  // stage + commit
        },
        std::chrono::seconds(10)));

    // commitChanges() chains both a working-copy refresh and a history
    // refresh on success -- the new commit should show up in the graph.
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) {
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_GRAPH_UPDATED && payload.find("\"complete\":true") != std::string::npos) {
                    return true;
                }
            }
            return false;
        },
        std::chrono::seconds(10)));

    int32_t rowCount = -1;
    int32_t rowStride = -1;
    const uint8_t* rows = gbm_graph_snapshot_rows(session_, &rowCount, &rowStride);
    EXPECT_NE(rows, nullptr);
    EXPECT_EQ(rowCount, 2);  // initial commit + the new one
    gbm_graph_snapshot_release(session_);
}

TEST_F(WorkingCopyApiTest, StageHunkStagesOnlyThatHunkLeavingTheOtherUnstaged) {
    std::string original;
    for (int i = 1; i <= 30; ++i) original += "L" + std::to_string(i) + "\n";
    std::ofstream(repo_ / "multi.txt") << original;
    ASSERT_EQ(runGit({"add", "multi.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Add multi.txt"}), 0);

    // Two edits far enough apart (well past the default 3-line context on
    // each side) to land in separate hunks: a top hunk and a bottom hunk.
    std::string modified;
    for (int i = 1; i <= 30; ++i) {
        if (i == 2) {
            modified += "L2-changed\n";
        } else if (i == 29) {
            modified += "L29-changed\n";
        } else {
            modified += "L" + std::to_string(i) + "\n";
        }
    }
    std::ofstream(repo_ / "multi.txt") << modified;

    const std::string beforeDiff = requestDiffJson("multi.txt", /*staged=*/false);
    ASSERT_NE(beforeDiff.find("\"L2-changed\""), std::string::npos) << beforeDiff;
    ASSERT_NE(beforeDiff.find("\"L29-changed\""), std::string::npos) << beforeDiff;

    gbm_stage_hunk(session_, "multi.txt", /*hunkIndex=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationSucceeded());

    const std::string stagedDiff = requestDiffJson("multi.txt", /*staged=*/true);
    EXPECT_NE(stagedDiff.find("\"L2-changed\""), std::string::npos) << stagedDiff;
    EXPECT_EQ(stagedDiff.find("\"L29-changed\""), std::string::npos) << stagedDiff;

    const std::string unstagedDiff = requestDiffJson("multi.txt", /*staged=*/false);
    EXPECT_EQ(unstagedDiff.find("\"L2-changed\""), std::string::npos) << unstagedDiff;
    EXPECT_NE(unstagedDiff.find("\"L29-changed\""), std::string::npos) << unstagedDiff;
}

TEST_F(WorkingCopyApiTest, UnstageHunkReversesAFullyStagedSingleHunkFile) {
    std::ofstream(repo_ / "single.txt") << "a\nb\nc\n";
    ASSERT_EQ(runGit({"add", "single.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Add single.txt"}), 0);
    std::ofstream(repo_ / "single.txt") << "a\nb\nc\nd\n";

    gbm_stage_hunk(session_, "single.txt", /*hunkIndex=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationSucceeded());
    const std::string stagedDiff = requestDiffJson("single.txt", /*staged=*/true);
    ASSERT_NE(stagedDiff.find("\"d\""), std::string::npos) << stagedDiff;

    gbm_unstage_hunk(session_, "single.txt", /*hunkIndex=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationSucceeded());

    const std::string stagedAfter = requestDiffJson("single.txt", /*staged=*/true);
    EXPECT_EQ(stagedAfter.find("\"files\":[{"), std::string::npos) << stagedAfter;
    const std::string unstagedAfter = requestDiffJson("single.txt", /*staged=*/false);
    EXPECT_NE(unstagedAfter.find("\"d\""), std::string::npos) << unstagedAfter;
}

TEST_F(WorkingCopyApiTest, StageLinesStagesOnlyTheSelectedAddedLines) {
    std::string original;
    for (int i = 1; i <= 7; ++i) original += "l" + std::to_string(i) + "\n";
    std::ofstream(repo_ / "lines.txt") << original;
    ASSERT_EQ(runGit({"add", "lines.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Add lines.txt"}), 0);

    // Insert two new lines between l4 and l5. With the default 3-line
    // context, the resulting hunk is exactly: context l2,l3,l4 (indices
    // 0-2), added NEW1,NEW2 (indices 3-4), context l5,l6,l7 (indices 5-7).
    std::ofstream(repo_ / "lines.txt") << "l1\nl2\nl3\nl4\nNEW1\nNEW2\nl5\nl6\nl7\n";

    const int32_t lineIndices[] = {3};  // NEW1 only
    gbm_stage_lines(session_, "lines.txt", /*hunkIndex=*/0, lineIndices, 1);
    ASSERT_TRUE(waitForWorkingCopyOperationSucceeded());

    const std::string stagedDiff = requestDiffJson("lines.txt", /*staged=*/true);
    EXPECT_NE(stagedDiff.find("\"NEW1\""), std::string::npos) << stagedDiff;
    EXPECT_EQ(stagedDiff.find("\"NEW2\""), std::string::npos) << stagedDiff;

    // NEW1 is now part of the index, so the remaining unstaged diff (work
    // tree vs index) shows it as unchanged context rather than omitting it
    // entirely -- it still appears in the text, just not as an added line.
    // Only NEW2 remains a real addition, so the file-level added-line count
    // drops from 2 to 1.
    const std::string unstagedDiff = requestDiffJson("lines.txt", /*staged=*/false);
    EXPECT_NE(unstagedDiff.find("\"addedLines\":1"), std::string::npos) << unstagedDiff;
    EXPECT_NE(unstagedDiff.find("\"kind\":1,\"oldLine\":0,\"newLine\":6,\"text\":\"NEW2\""), std::string::npos) << unstagedDiff;
}

TEST_F(WorkingCopyApiTest, DiscardLinesRemovesOnlyTheSelectedLinesFromTheWorkTree) {
    std::string original;
    for (int i = 1; i <= 7; ++i) original += "l" + std::to_string(i) + "\n";
    std::ofstream(repo_ / "discard.txt") << original;
    ASSERT_EQ(runGit({"add", "discard.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Add discard.txt"}), 0);

    // Same hunk shape as StageLinesStagesOnlyTheSelectedAddedLines: context
    // l2,l3,l4 (indices 0-2), added NEW1,NEW2 (indices 3-4), context
    // l5,l6,l7 (indices 5-7).
    std::ofstream(repo_ / "discard.txt") << "l1\nl2\nl3\nl4\nNEW1\nNEW2\nl5\nl6\nl7\n";

    const int32_t lineIndices[] = {3};  // NEW1 only
    gbm_discard_lines(session_, "discard.txt", /*hunkIndex=*/0, lineIndices, 1);
    ASSERT_TRUE(waitForWorkingCopyOperationSucceeded());

    // Unlike gbm_unstage_lines, this touches the file on disk: NEW1 is gone
    // from the work tree entirely, NEW2 is untouched.
    std::ifstream in(repo_ / "discard.txt");
    const std::string onDisk((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(onDisk, "l1\nl2\nl3\nl4\nNEW2\nl5\nl6\nl7\n");

    // The index was never touched, so the remaining unstaged diff still has
    // NEW2 as its one and only added line.
    const std::string unstagedDiff = requestDiffJson("discard.txt", /*staged=*/false);
    EXPECT_NE(unstagedDiff.find("\"addedLines\":1"), std::string::npos) << unstagedDiff;
    EXPECT_NE(unstagedDiff.find("\"NEW2\""), std::string::npos) << unstagedDiff;
    EXPECT_EQ(unstagedDiff.find("\"NEW1\""), std::string::npos) << unstagedDiff;
}

TEST_F(WorkingCopyApiTest, DiscardLinesWithNoSelectionDiscardsTheWholeHunk) {
    std::ofstream(repo_ / "wholehunk.txt") << "a\nb\nc\n";
    ASSERT_EQ(runGit({"add", "wholehunk.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Add wholehunk.txt"}), 0);
    std::ofstream(repo_ / "wholehunk.txt") << "a\nb\nc\nd\n";

    gbm_discard_lines(session_, "wholehunk.txt", /*hunkIndex=*/0, nullptr, 0);
    ASSERT_TRUE(waitForWorkingCopyOperationSucceeded());

    std::ifstream in(repo_ / "wholehunk.txt");
    const std::string onDisk((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(onDisk, "a\nb\nc\n");
}

TEST_F(WorkingCopyApiTest, DiscardLinesFailsCleanlyWhenTheHunkIndexNoLongerExists) {
    std::ofstream(repo_ / "stale.txt") << "a\nb\nc\n";
    ASSERT_EQ(runGit({"add", "stale.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Add stale.txt"}), 0);
    std::ofstream(repo_ / "stale.txt") << "a\nb\nc\nd\n";

    const int32_t lineIndices[] = {0};
    gbm_discard_lines(session_, "stale.txt", /*hunkIndex=*/5, lineIndices, 1);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished());

    const std::vector<std::string> outcomes = log_.payloadsOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    ASSERT_FALSE(outcomes.empty());
    EXPECT_NE(outcomes.back().find("\"succeeded\":false"), std::string::npos) << outcomes.back();

    // The work tree must be exactly as it was -- a failed discard that had
    // already half-applied would be unrecoverable.
    std::ifstream in(repo_ / "stale.txt");
    const std::string onDisk((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    EXPECT_EQ(onDisk, "a\nb\nc\nd\n");
}

TEST_F(WorkingCopyApiTest, StageHunkFailsCleanlyWhenTheHunkIndexNoLongerExists) {
    std::ofstream(repo_ / "onehunk.txt") << "a\nb\nc\n";
    ASSERT_EQ(runGit({"add", "onehunk.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Add onehunk.txt"}), 0);
    std::ofstream(repo_ / "onehunk.txt") << "a\nb\nc\nd\n";

    gbm_stage_hunk(session_, "onehunk.txt", /*hunkIndex=*/5);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished());

    const std::vector<std::string> outcomes = log_.payloadsOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    ASSERT_FALSE(outcomes.empty());
    EXPECT_NE(outcomes.back().find("\"succeeded\":false"), std::string::npos) << outcomes.back();
}

}  // namespace
}  // namespace gbm::capi
