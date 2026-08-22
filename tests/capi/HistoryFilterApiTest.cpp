// Integration test for gbm_history_set_filter against a real repository whose
// trunk has two merges in it.
//
// The narrowing itself is asserted against `git rev-list` rather than against
// a hardcoded count, and the two failure modes that motivated the entry
// point's design get a case each: a stale ref name must not blank the graph,
// and the filter must survive a refresh it did not ask for.
#include "capi/gbm_capi.h"
#include "support/GitCli.h"

#include <chrono>
#include <condition_variable>
#include <cstdint>
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

    /// Number of GRAPH_UPDATED events carrying {"complete": true}. The walk
    /// streams, so counting *completed* walks is the only way to tell "the
    /// filter I just set has been applied" from "a chunk of the previous walk
    /// arrived late".
    std::size_t completedWalks() {
        std::lock_guard<std::mutex> lock(mutex);
        std::size_t count = 0;
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_GRAPH_UPDATED && payload.find("true") != std::string::npos) {
                ++count;
            }
        }
        return count;
    }

    bool waitForCompletedWalks(std::size_t target,
                               std::chrono::milliseconds timeout = std::chrono::seconds(10)) {
        std::unique_lock<std::mutex> lock(mutex);
        return cv.wait_for(lock, timeout, [&] {
            std::size_t count = 0;
            for (const auto& [type, payload] : events) {
                if (type == GBM_EVENT_GRAPH_UPDATED && payload.find("true") != std::string::npos) {
                    ++count;
                }
            }
            return count >= target;
        });
    }
};

void logCallback(GbmSessionHandle,
                 int32_t eventType,
                 const uint8_t* payload,
                 int32_t payloadLen,
                 void* userData) {
    auto* log = static_cast<EventLog*>(userData);
    std::string body;
    if (payload != nullptr) {
        body.assign(reinterpret_cast<const char*>(payload), static_cast<std::size_t>(payloadLen));
        gbm_free_event_payload(payload);
    }
    log->add(eventType, std::move(body));
}

class HistoryFilterApiTest : public ::testing::Test {
protected:
    static void SetUpTestSuite() {
        if (GitCli::executable().empty()) {
            GTEST_SKIP() << "no usable git found";
        }
    }

    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() /
                ("gbm-capi-histfilter-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);

        commit("base.txt", "base", "c1");
        // Two side branches merged back into main, so the unfiltered walk has
        // parallel lanes and merge rows and the filtered one cannot.
        for (const std::string& side : {std::string("side-one"), std::string("side-two")}) {
            ASSERT_EQ(runGit({"checkout", "--quiet", "-b", side}), 0);
            commit(side + ".txt", "x", "on " + side);
            ASSERT_EQ(runGit({"checkout", "--quiet", "main"}), 0);
            commit("base.txt", "before " + side, "main before " + side);
            ASSERT_EQ(runGit({"merge", "--quiet", "--no-ff", "-m", "merge " + side, side}), 0);
        }
        commit("base.txt", "tip", "tip");

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

    int runGit(std::vector<std::string> args) { return GitCli::run(repo_, std::move(args)); }

    void commit(const std::string& file, const std::string& body, const std::string& message) {
        std::ofstream(repo_ / file) << body << "\n";
        ASSERT_EQ(runGit({"add", file}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", message}), 0);
    }

    /// Rows in the most recently published snapshot.
    int32_t graphRowCount() {
        int32_t rows = 0;
        int32_t stride = 0;
        gbm_graph_snapshot_rows(session_, &rows, &stride);
        gbm_graph_snapshot_release(session_);
        return rows;
    }

    /// What git itself reports for the same walk, so the expected numbers are
    /// never hand-counted from the fixture.
    std::size_t gitRowCount(std::vector<std::string> revListArgs) {
        std::vector<std::string> args{"rev-list"};
        args.insert(args.end(), revListArgs.begin(), revListArgs.end());
        return GitCli::capture(repo_, std::move(args)).lines().size();
    }

    /// Refreshes and blocks until walk number `walkIndex` has completed.
    void refreshAndWait(std::size_t walkIndex) {
        gbm_history_refresh(session_);
        ASSERT_TRUE(log_.waitForCompletedWalks(walkIndex))
            << "walk " << walkIndex << " never completed";
    }

    std::filesystem::path repo_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(HistoryFilterApiTest, NarrowsTheWalkToOneBranchWithoutMerges) {
    refreshAndWait(1);
    const int32_t unfiltered = graphRowCount();
    ASSERT_EQ(static_cast<std::size_t>(unfiltered), gitRowCount({"--all"}));

    const char* refs[] = {"refs/heads/main"};
    gbm_history_set_filter(session_, refs, 1, /*firstParentOnly=*/1, /*noMerges=*/1);
    ASSERT_TRUE(log_.waitForCompletedWalks(2));

    const std::size_t expected = gitRowCount({"--first-parent", "--no-merges", "refs/heads/main"});
    EXPECT_EQ(static_cast<std::size_t>(graphRowCount()), expected);
    EXPECT_LT(graphRowCount(), unfiltered) << "the filter must actually narrow the walk";
}

TEST_F(HistoryFilterApiTest, ClearingTheFilterRestoresTheFullWalk) {
    refreshAndWait(1);
    const int32_t unfiltered = graphRowCount();

    const char* refs[] = {"refs/heads/main"};
    gbm_history_set_filter(session_, refs, 1, 1, 1);
    ASSERT_TRUE(log_.waitForCompletedWalks(2));
    ASSERT_LT(graphRowCount(), unfiltered);

    // Count 0 is how a caller clears it -- there is no separate reset call.
    gbm_history_set_filter(session_, nullptr, 0, 0, 0);
    ASSERT_TRUE(log_.waitForCompletedWalks(3));
    EXPECT_EQ(graphRowCount(), unfiltered);
}

TEST_F(HistoryFilterApiTest, SurvivesARefreshItDidNotAskFor) {
    // The filter is session state, not a parameter of one walk: an operation
    // or an auto-fetch resync calls refreshHistory() on its own, and if that
    // dropped the filter the graph would silently widen back out under the
    // user while the sidebar still showed one branch.
    refreshAndWait(1);
    const int32_t unfiltered = graphRowCount();

    const char* refs[] = {"refs/heads/main"};
    gbm_history_set_filter(session_, refs, 1, 1, 1);
    ASSERT_TRUE(log_.waitForCompletedWalks(2));
    const int32_t filtered = graphRowCount();
    ASSERT_LT(filtered, unfiltered);

    refreshAndWait(3);
    EXPECT_EQ(graphRowCount(), filtered);
}

TEST_F(HistoryFilterApiTest, DropsARefThatNoLongerExistsInsteadOfBlankingTheGraph) {
    // rev-list aborts the *entire* walk with "unknown revision" on one stale
    // name, so a branch deleted or pruned while its filter is set would empty
    // the graph rather than just stop narrowing it.
    refreshAndWait(1);
    const int32_t unfiltered = graphRowCount();

    const char* refs[] = {"refs/heads/main", "refs/heads/deleted-since"};
    gbm_history_set_filter(session_, refs, 2, /*firstParentOnly=*/0, /*noMerges=*/0);
    ASSERT_TRUE(log_.waitForCompletedWalks(2));

    // main survives, the stale name is dropped: the walk is main's history,
    // which here is everything, and emphatically not zero rows.
    EXPECT_GT(graphRowCount(), 0);
    EXPECT_EQ(static_cast<std::size_t>(graphRowCount()), gitRowCount({"refs/heads/main"}));
    EXPECT_LE(graphRowCount(), unfiltered);
}

TEST_F(HistoryFilterApiTest, EveryNameStaleFallsBackToTheUnfilteredWalk) {
    refreshAndWait(1);
    const int32_t unfiltered = graphRowCount();

    const char* refs[] = {"refs/heads/gone-a", "refs/heads/gone-b"};
    gbm_history_set_filter(session_, refs, 2, 0, 0);
    ASSERT_TRUE(log_.waitForCompletedWalks(2));

    EXPECT_EQ(graphRowCount(), unfiltered)
        << "with nothing left to narrow by, the walk must widen rather than empty";
}

}  // namespace
}  // namespace gbm::capi
