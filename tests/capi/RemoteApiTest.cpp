// Integration tests for the M5 remote slice of the extern "C" surface
// (gbm_capi.h): fetch/pull/push against a local bare repository reached
// over the plain filesystem transport, which needs no credentials -- git
// never invokes askpass for it, so these stay fully offline.
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

    void clear() {
        std::lock_guard<std::mutex> lock(mutex);
        events.clear();
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

bool waitForWorkingCopyOperationFinished(EventLog& log) {
    return log.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_WORKING_COPY_OPERATION_FINISHED) return true;
        }
        return false;
    });
}

bool waitForOperationFinished(EventLog& log) {
    return log.waitFor([](const auto& events) {
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_OPERATION_FINISHED) return true;
        }
        return false;
    });
}

class RemoteApiTest : public ::testing::Test {
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
        repo_ = std::filesystem::temp_directory_path() / ("gbm-capi-remote-" + std::string(info->name()));
        remote_ = std::filesystem::temp_directory_path() / ("gbm-capi-remote-bare-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::remove_all(remote_);
        std::filesystem::create_directories(repo_);

        ASSERT_EQ(runIn(remote_.parent_path(), {"init", "--quiet", "--bare", remote_.string()}), 0);

        ASSERT_EQ(runGit({"init", "--quiet", "--initial-branch=main"}), 0);
        ASSERT_EQ(runGit({"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runGit({"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runGit({"config", "commit.gpgsign", "false"}), 0);
        ASSERT_EQ(runGit({"remote", "add", "origin", remote_.string()}), 0);

        std::ofstream(repo_ / "file.txt") << "content\n";
        ASSERT_EQ(runGit({"add", "file.txt"}), 0);
        ASSERT_EQ(runGit({"commit", "--quiet", "-m", "Initial commit"}), 0);
        ASSERT_EQ(runGit({"push", "--quiet", "-u", "origin", "main"}), 0);

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
        std::filesystem::remove_all(remote_, ec);
    }

    int runGit(std::vector<std::string> args) { return runIn(repo_, std::move(args)); }

    int runIn(const std::filesystem::path& dir, std::vector<std::string> args) {
        return GitCli::run(dir, std::move(args));
    }

    std::string remotesJson() {
        [[maybe_unused]] const int32_t rc = gbm_remotes_json(session_);
        std::string json(static_cast<std::size_t>(gbm_last_result_json_len()), '\0');
        gbm_last_result_json_copy(reinterpret_cast<uint8_t*>(json.data()), static_cast<int32_t>(json.size()));
        return json;
    }

    /// A second clone pushes one commit to `main` that repo_ has not fetched.
    void pushFromAnotherClone(const std::string& fileName) {
        const std::filesystem::path other =
            repo_.parent_path() / (repo_.filename().string() + "-pusher");
        std::error_code ec;
        std::filesystem::remove_all(other, ec);
        ASSERT_EQ(
            runIn(other.parent_path(), {"clone", "--quiet", remote_.string(), other.string()}), 0);
        ASSERT_EQ(runIn(other, {"checkout", "--quiet", "main"}), 0);
        ASSERT_EQ(runIn(other, {"config", "user.email", "test@example.invalid"}), 0);
        ASSERT_EQ(runIn(other, {"config", "user.name", "Test"}), 0);
        ASSERT_EQ(runIn(other, {"config", "commit.gpgsign", "false"}), 0);
        std::ofstream(other / fileName) << "content\n";
        ASSERT_EQ(runIn(other, {"add", fileName}), 0);
        ASSERT_EQ(runIn(other, {"commit", "--quiet", "-m", "From another clone"}), 0);
        ASSERT_EQ(runIn(other, {"push", "--quiet", "origin", "main"}), 0);
        std::filesystem::remove_all(other, ec);
    }

    /// Runs one history refresh to completion, so Session holds the ref
    /// snapshot a background fetch compares against, then forgets every event.
    ///
    /// A plain fetch first: since git 2.48 (`remote.<name>.followRemoteHEAD`)
    /// the first fetch of a remote creates `refs/remotes/origin/HEAD`, which is
    /// a real new ref -- without this a "quiet" remote is not quiet.
    void settleInitialRefresh() {
        ASSERT_EQ(runGit({"fetch", "--quiet", "origin"}), 0);
        gbm_history_refresh(session_);
        ASSERT_TRUE(
            log_.waitFor([](const auto& events) { return completeGraphUpdates(events) > 0; }));
        log_.clear();
    }

    static int completeGraphUpdates(const std::vector<std::pair<int32_t, std::string>>& events) {
        int count = 0;
        for (const auto& [type, payload] : events) {
            if (type == GBM_EVENT_GRAPH_UPDATED &&
                payload.find("\"complete\":true") != std::string::npos) {
                ++count;
            }
        }
        return count;
    }

    std::filesystem::path repo_;
    std::filesystem::path remote_;
    GbmSessionHandle session_ = nullptr;
    EventLog log_;
};

TEST_F(RemoteApiTest, RefreshReportsTheConfiguredRemote) {
    gbm_remote_refresh(session_);
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_REMOTES_UPDATED); }));

    const std::string json = remotesJson();
    EXPECT_NE(json.find("\"name\":\"origin\""), std::string::npos) << json;
}

TEST_F(RemoteApiTest, FetchBringsInNewRemoteCommits) {
    // A second clone pushes a commit that repo_ has not seen yet.
    const std::filesystem::path other = repo_.parent_path() / (repo_.filename().string() + "-other");
    std::error_code ec;
    std::filesystem::remove_all(other, ec);
    ASSERT_EQ(runIn(other.parent_path(), {"clone", "--quiet", remote_.string(), other.string()}), 0);
    // The bare remote's default branch (its HEAD symref, fixed at `git init
    // --bare` time) is whatever init.defaultBranch says, not necessarily
    // "main" -- only pushing to it makes "main" exist there. A clone
    // therefore checks out that default branch, which may not be "main"
    // even though `main` exists as a remote-tracking branch; check it out
    // explicitly so the commit below lands on the branch this test expects.
    ASSERT_EQ(runIn(other, {"checkout", "--quiet", "main"}), 0);
    ASSERT_EQ(runIn(other, {"config", "user.email", "test@example.invalid"}), 0);
    ASSERT_EQ(runIn(other, {"config", "user.name", "Test"}), 0);
    ASSERT_EQ(runIn(other, {"config", "commit.gpgsign", "false"}), 0);
    std::ofstream(other / "from-other.txt") << "content\n";
    ASSERT_EQ(runIn(other, {"add", "from-other.txt"}), 0);
    ASSERT_EQ(runIn(other, {"commit", "--quiet", "-m", "From the other clone"}), 0);
    ASSERT_EQ(runIn(other, {"push", "--quiet", "origin", "main"}), 0);
    std::filesystem::remove_all(other, ec);

    gbm_remote_fetch(session_, "origin", nullptr, 0, /*prune=*/0, /*tags=*/0, /*background=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    // The remote-tracking ref now has the file the other clone pushed...
    EXPECT_EQ(runGit({"cat-file", "-e", "origin/main:from-other.txt"}), 0);
    // ...but a fetch never touches the work tree or local main.
    EXPECT_FALSE(std::filesystem::exists(repo_ / "from-other.txt"));
}

TEST_F(RemoteApiTest, FetchWithRefsBringsInOnlyTheNamedBranch) {
    // Two new branches pushed to the bare remote. A successful push also
    // updates the pushed branch's own local remote-tracking ref as a side
    // effect (independent of any fetch) -- delete both right back off so
    // the fetch below is really the one bringing them in, not the push.
    ASSERT_EQ(runGit({"push", "--quiet", "origin", "main:refs/heads/wanted"}), 0);
    ASSERT_EQ(runGit({"push", "--quiet", "origin", "main:refs/heads/unwanted"}), 0);
    ASSERT_EQ(runGit({"update-ref", "-d", "refs/remotes/origin/wanted"}), 0);
    ASSERT_EQ(runGit({"update-ref", "-d", "refs/remotes/origin/unwanted"}), 0);
    ASSERT_NE(runGit({"rev-parse", "--verify", "origin/wanted"}), 0);
    ASSERT_NE(runGit({"rev-parse", "--verify", "origin/unwanted"}), 0);

    const char* refs[] = {"wanted"};
    gbm_remote_fetch(session_, "origin", refs, 1, /*prune=*/0, /*tags=*/0, /*background=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    EXPECT_EQ(runGit({"rev-parse", "--verify", "origin/wanted"}), 0);
    // The other branch on the same remote is untouched -- gbm_remote_fetch
    // with refs fetches exactly what it's given, not everything.
    EXPECT_NE(runGit({"rev-parse", "--verify", "origin/unwanted"}), 0);
}

TEST_F(RemoteApiTest, FetchStampsItsOutcomeWithAKindSoDartCanAttributeIt) {
    // Roughly thirty controller methods share GBM_EVENT_WORKING_COPY_OPERATION_FINISHED
    // and OperationRunner's queue can hold more than one operation, so
    // "the next completion event is my fetch" is wrong whenever anything
    // else is submitted in between. Operation::kind() exists precisely so
    // Dart's PendingOperationTracker can pair an outcome with the request
    // that produced it (see OperationRunner.h's doc comment); fetch had no
    // override, which is why the post-fetch gone-marking had nothing stable
    // to hang off.
    gbm_remote_fetch(session_, "origin", nullptr, 0, /*prune=*/0, /*tags=*/0, /*background=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"kind\":\"fetch\""), std::string::npos) << outcome;
}

TEST_F(RemoteApiTest, AFailedFetchIsStampedToo) {
    // The stamp is applied by OperationRunner on the single path every
    // completion funnels through, so it must survive a failure. Dart pops
    // its FIFO on any outcome, success or not -- an unstamped failure would
    // leave the queue misaligned and attribute the *next* fetch's outcome
    // to this request.
    const char* refs[] = {"main"};
    gbm_remote_fetch(session_, "", refs, 1, /*prune=*/0, /*tags=*/0, /*background=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":false"), std::string::npos) << outcome;
    EXPECT_NE(outcome.find("\"kind\":\"fetch\""), std::string::npos) << outcome;
}

TEST_F(RemoteApiTest, FetchWithRefsButNoRemoteNameFailsCleanly) {
    const char* refs[] = {"main"};
    gbm_remote_fetch(session_, "", refs, 1, /*prune=*/0, /*tags=*/0, /*background=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":false"), std::string::npos) << outcome;
}

TEST_F(RemoteApiTest, PullMergesRemoteCommitsIntoTheCurrentBranch) {
    const std::filesystem::path other = repo_.parent_path() / (repo_.filename().string() + "-other");
    std::error_code ec;
    std::filesystem::remove_all(other, ec);
    ASSERT_EQ(runIn(other.parent_path(), {"clone", "--quiet", remote_.string(), other.string()}), 0);
    // The bare remote's default branch (its HEAD symref, fixed at `git init
    // --bare` time) is whatever init.defaultBranch says, not necessarily
    // "main" -- only pushing to it makes "main" exist there. A clone
    // therefore checks out that default branch, which may not be "main"
    // even though `main` exists as a remote-tracking branch; check it out
    // explicitly so the commit below lands on the branch this test expects.
    ASSERT_EQ(runIn(other, {"checkout", "--quiet", "main"}), 0);
    ASSERT_EQ(runIn(other, {"config", "user.email", "test@example.invalid"}), 0);
    ASSERT_EQ(runIn(other, {"config", "user.name", "Test"}), 0);
    ASSERT_EQ(runIn(other, {"config", "commit.gpgsign", "false"}), 0);
    std::ofstream(other / "from-other.txt") << "content\n";
    ASSERT_EQ(runIn(other, {"add", "from-other.txt"}), 0);
    ASSERT_EQ(runIn(other, {"commit", "--quiet", "-m", "From the other clone"}), 0);
    ASSERT_EQ(runIn(other, {"push", "--quiet", "origin", "main"}), 0);
    std::filesystem::remove_all(other, ec);

    gbm_pull(session_, "origin", "main", /*rebase=*/0, /*stashFirst=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    EXPECT_TRUE(std::filesystem::exists(repo_ / "from-other.txt"));
}

TEST_F(RemoteApiTest, PushUploadsLocalCommitsToTheRemote) {
    std::ofstream(repo_ / "new-file.txt") << "content\n";
    ASSERT_EQ(runGit({"add", "new-file.txt"}), 0);
    ASSERT_EQ(runGit({"commit", "--quiet", "-m", "New commit"}), 0);

    const char* branches[] = {"main"};
    gbm_push(session_,
             "origin",
             branches,
             /*branchCount=*/1,
             /*setUpstream=*/0,
             /*pushTags=*/0,
             /*forceWithLease=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    // Named explicitly, not bare HEAD: the bare remote's HEAD symref is
    // whatever init.defaultBranch says (fixed at `git init --bare` time),
    // not necessarily "main" -- see the FetchBringsInNewRemoteCommits doc
    // comment above for the same distinction.
    EXPECT_EQ(runIn(remote_, {"cat-file", "-e", "refs/heads/main:new-file.txt"}), 0);
}

TEST_F(RemoteApiTest, PrunePreviewListsARemoteTrackingBranchDeletedOnTheRemote) {
    // A remote-tracking ref for a branch that no longer exists on the
    // remote -- delete it there directly (bypassing gbm_push, which has no
    // "delete a remote branch" affordance) so origin/gone is genuinely
    // stale from repo_'s point of view.
    //
    // Started from "main" explicitly, not from the bare remote's HEAD: that
    // symref is fixed at `git init --bare` time to whatever
    // init.defaultBranch says (plain git: "master"), while the only ref this
    // fixture ever pushes is "main". A bare `git branch gone` therefore
    // resolves HEAD to a nonexistent refs/heads/master and exits 128 -- the
    // same trap the FetchBringsInNewRemoteCommits comment above calls out.
    ASSERT_EQ(runIn(remote_, {"branch", "gone", "main"}), 0);
    gbm_remote_fetch(session_, "origin", nullptr, 0, /*prune=*/0, /*tags=*/0, /*background=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));
    ASSERT_EQ(runGit({"rev-parse", "--verify", "origin/gone"}), 0);
    ASSERT_EQ(runIn(remote_, {"branch", "-D", "gone"}), 0);

    gbm_request_remote_prune_preview(session_, "origin");
    ASSERT_TRUE(log_.waitFor(
        [](const auto& events) { return anyEventOfType(events, GBM_EVENT_REMOTE_PRUNE_PREVIEW_READY); }));

    const std::string payload = log_.lastPayloadOfType(GBM_EVENT_REMOTE_PRUNE_PREVIEW_READY);
    EXPECT_NE(payload.find("\"remote\":\"origin\""), std::string::npos) << payload;
    EXPECT_NE(payload.find("origin/gone"), std::string::npos) << payload;
    // The dry-run preview must not have actually removed the stale ref.
    EXPECT_EQ(runGit({"rev-parse", "--verify", "origin/gone"}), 0);
}

TEST_F(RemoteApiTest, PruneDeletesExactlyTheSelectedRemoteTrackingRef) {
    // Explicit start point -- see the note in the preview test above.
    ASSERT_EQ(runIn(remote_, {"branch", "gone", "main"}), 0);
    gbm_remote_fetch(session_, "origin", nullptr, 0, /*prune=*/0, /*tags=*/0, /*background=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));
    ASSERT_EQ(runGit({"rev-parse", "--verify", "origin/gone"}), 0);
    ASSERT_EQ(runGit({"rev-parse", "--verify", "origin/main"}), 0);

    const char* refs[] = {"origin/gone"};
    gbm_remote_prune(session_, "origin", refs, 1);
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    EXPECT_NE(runGit({"rev-parse", "--verify", "origin/gone"}), 0);
    // Untouched: gbm_remote_prune only deletes the refs it is given.
    EXPECT_EQ(runGit({"rev-parse", "--verify", "origin/main"}), 0);
}

TEST_F(RemoteApiTest, PruneStampsItsOutcomeWithAKindSoDartCanAttributeIt) {
    // Same reasoning as FetchStampsItsOutcomeWithAKindSoDartCanAttributeIt
    // above, on the other completion channel: Dart clears its gone-pending
    // marks when a prune succeeds, and "the next OPERATION_FINISHED is my
    // prune" is wrong whenever any of the ~thirty other methods sharing
    // that channel is submitted in between.
    ASSERT_EQ(runIn(remote_, {"branch", "gone", "main"}), 0);
    gbm_remote_fetch(session_, "origin", nullptr, 0, /*prune=*/0, /*tags=*/0, /*background=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const char* refs[] = {"origin/gone"};
    gbm_remote_prune(session_, "origin", refs, 1);
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"kind\":\"prune-remote\""), std::string::npos) << outcome;
}

TEST_F(RemoteApiTest, AFailedPruneIsStampedToo) {
    // The stamp comes from OperationRunner's single completion path, so it
    // must survive a failure. Dart pops its FIFO on any outcome -- an
    // unstamped failure would misalign the queue and let a *failed* prune
    // clear gone marks the next prune was supposed to answer for.
    const char* refs[] = {"origin/never-existed"};
    gbm_remote_prune(session_, "origin", refs, 1);
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":false"), std::string::npos) << outcome;
    EXPECT_NE(outcome.find("\"kind\":\"prune-remote\""), std::string::npos) << outcome;
}

TEST_F(RemoteApiTest, AddRemoteAddsANewRemote) {
    const std::filesystem::path upstream = remote_.parent_path() / "gbm-capi-remote-upstream";
    std::error_code ec;
    std::filesystem::remove_all(upstream, ec);
    ASSERT_EQ(runIn(upstream.parent_path(), {"init", "--quiet", "--bare", upstream.string()}), 0);

    gbm_remote_add(session_, "upstream", upstream.string().c_str());
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_REMOTES_UPDATED); }));
    const std::string json = remotesJson();
    EXPECT_NE(json.find("\"name\":\"upstream\""), std::string::npos) << json;

    std::filesystem::remove_all(upstream, ec);
}

TEST_F(RemoteApiTest, AddRemoteFailsWhenNameAlreadyExists) {
    gbm_remote_add(session_, "origin", remote_.string().c_str());
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":false"), std::string::npos) << outcome;
}

TEST_F(RemoteApiTest, RemoveRemoteRemovesIt) {
    gbm_remote_remove(session_, "origin");
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return anyEventOfType(events, GBM_EVENT_REMOTES_UPDATED); }));
    const std::string json = remotesJson();
    EXPECT_EQ(json.find("\"name\":\"origin\""), std::string::npos) << json;
}

TEST_F(RemoteApiTest, RemoveRemoteFailsWhenNoSuchRemote) {
    gbm_remote_remove(session_, "does-not-exist");
    ASSERT_TRUE(waitForOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":false"), std::string::npos) << outcome;
}

TEST_F(RemoteApiTest, BackgroundFetchOfAQuietRemoteSkipsTheHistoryWalk) {
    settleInitialRefresh();

    gbm_remote_fetch(session_, "origin", nullptr, 0, /*prune=*/0, /*tags=*/0, /*background=*/1);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":true"), std::string::npos) << outcome;
    EXPECT_NE(outcome.find("\"refsMoved\":false"), std::string::npos) << outcome;
    // Well past RefreshCoalescer's 150 ms window: a walk would have finished.
    EXPECT_FALSE(log_.waitFor([](const auto& events) { return completeGraphUpdates(events) > 0; },
                              std::chrono::milliseconds(1500)))
        << "nothing moved, so no history walk may run";
}

TEST_F(RemoteApiTest, BackgroundFetchThatMovesARefWalksHistoryOnce) {
    settleInitialRefresh();
    pushFromAnotherClone("moved.txt");

    gbm_remote_fetch(session_, "origin", nullptr, 0, /*prune=*/0, /*tags=*/0, /*background=*/1);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"refsMoved\":true"), std::string::npos) << outcome;
    ASSERT_TRUE(log_.waitFor([](const auto& events) { return completeGraphUpdates(events) > 0; }));
    log_.waitFor([](const auto& events) { return completeGraphUpdates(events) > 1; },
                 std::chrono::milliseconds(1000));
    std::lock_guard<std::mutex> lock(log_.mutex);
    EXPECT_EQ(completeGraphUpdates(log_.events), 1);
}

TEST_F(RemoteApiTest, AForegroundFetchOutcomeCarriesNoRefsMovedKey) {
    gbm_remote_fetch(session_, "origin", nullptr, 0, /*prune=*/0, /*tags=*/0, /*background=*/0);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_EQ(outcome.find("refsMoved"), std::string::npos)
        << "every other outcome's JSON stays byte-identical: " << outcome;
}

void setEnv(const char* name, const std::string& value) {
#ifdef _WIN32
    _putenv_s(name, value.c_str());
#else
    setenv(name, value.c_str(), 1);
#endif
}

void unsetEnv(const char* name) {
#ifdef _WIN32
    _putenv_s(name, "");
#else
    unsetenv(name);
#endif
}

/// A second remote, `sshremote`, reached through a shell script standing in
/// for ssh (the CloneJobApiTest technique): the script plays git's askpass
/// client against whatever GBM_ASKPASS_DIR the operation was given, so a
/// test can see whether a credential prompt was -- or could be -- raised.
class SshRemoteApiTest : public RemoteApiTest {
protected:
    void SetUp() override {
        RemoteApiTest::SetUp();
        ASSERT_EQ(runGit({"remote", "add", "sshremote", "ssh://example.invalid/r.git"}), 0);
    }

    void TearDown() override {
        unsetEnv("GIT_SSH_COMMAND");
        unsetEnv("GIT_SSH_VARIANT");
        RemoteApiTest::TearDown();
        std::error_code ec;
        std::filesystem::remove(script_, ec);
    }

    void useSshScript(const std::string& body) {
        script_ = repo_.parent_path() / (repo_.filename().string() + "-fake-ssh.sh");
        {
            std::ofstream file(script_, std::ios::binary);
            file << body;
        }
        setEnv("GIT_SSH_COMMAND", "sh '" + script_.generic_string() + "'");
        setEnv("GIT_SSH_VARIANT", "ssh");
    }

    std::filesystem::path script_;
};

TEST_F(SshRemoteApiTest, BackgroundFetchNeverRaisesACredentialPrompt) {
    useSshScript(
        "if [ -n \"$GBM_ASKPASS_DIR\" ]; then\n"
        "  printf 'Password for x: ' > \"$GBM_ASKPASS_DIR/request\"\n"
        "  sleep 2\n"
        "fi\n"
        "exit 1\n");

    gbm_remote_fetch(session_,
                     "sshremote",
                     nullptr,
                     0,
                     /*prune=*/0,
                     /*tags=*/0,
                     /*background=*/1);
    ASSERT_TRUE(waitForWorkingCopyOperationFinished(log_));

    const std::string outcome = log_.lastPayloadOfType(GBM_EVENT_WORKING_COPY_OPERATION_FINISHED);
    EXPECT_NE(outcome.find("\"succeeded\":false"), std::string::npos) << outcome;
    EXPECT_TRUE(log_.lastPayloadOfType(GBM_EVENT_CREDENTIAL_REQUESTED).empty())
        << "nobody pressed a button, so nothing may ask for a password";
}

TEST_F(SshRemoteApiTest, PushQueuedBehindABackgroundFetchStillRaisesItsPrompt) {
    // The fetch (upload-pack) holds the queue for a second; the push
    // (receive-pack) asks for a password. The push takes its askpass watch
    // when it is submitted, i.e. while the fetch is still running -- so a
    // background fetch that released "the" watch on finishing would delete
    // the push's request directory and its prompt would never appear.
    useSshScript(
        "case \"$*\" in\n"
        "  *upload-pack*) sleep 1; exit 1 ;;\n"
        "esac\n"
        "printf 'Password for push: ' > \"$GBM_ASKPASS_DIR/request\" || exit 1\n"
        "while [ ! -f \"$GBM_ASKPASS_DIR/cancel\" ] && [ ! -f \"$GBM_ASKPASS_DIR/response\" ] &&"
        " [ -d \"$GBM_ASKPASS_DIR\" ]; do\n"
        "  sleep 0.05\n"
        "done\n"
        "exit 1\n");

    gbm_remote_fetch(session_,
                     "sshremote",
                     nullptr,
                     0,
                     /*prune=*/0,
                     /*tags=*/0,
                     /*background=*/1);
    const char* branches[] = {"main"};
    gbm_push(session_,
             "sshremote",
             branches,
             1,
             /*setUpstream=*/0,
             /*pushTags=*/0,
             /*forceWithLease=*/0);

    ASSERT_TRUE(log_.waitFor([](const auto& events) {
        return anyEventOfType(events, GBM_EVENT_CREDENTIAL_REQUESTED);
    })) << "the push's password prompt was lost";
    EXPECT_EQ(log_.lastPayloadOfType(GBM_EVENT_CREDENTIAL_REQUESTED),
              "{\"prompt\":\"Password for push: \"}");
    gbm_cancel_credential(session_);
}

}  // namespace
}  // namespace gbm::capi
