// OperationRunner's preflight waits briefly for another process's index.lock.
//
// A live lock usually belongs to something that is about to finish: an IDE's
// status poll, a terminal command. Failing the user's click on sight turned that
// moment into a recovery dialog. These tests create the lock file themselves, so
// no git and no timing race is involved beyond the wait being measured.
#include "core/git/OperationRunner.h"
#include "core/git/RepoPaths.h"
#include "core/git/ops/StageOps.h"
#include "support/FakeProcessRunner.h"

#include <atomic>
#include <chrono>
#include <filesystem>
#include <fstream>
#include <future>
#include <gtest/gtest.h>
#include <memory>
#include <string>
#include <thread>

namespace gbm {
namespace {

using namespace std::chrono_literals;

class RecordingOperation final : public Operation {
public:
    explicit RecordingOperation(std::atomic<int>& runs) : runs_(runs) {}

    std::string describe() const override { return "Recording test operation"; }

    OperationOutcome run(IProcessRunner&, const RepoPaths&, CancellationToken) override {
        ++runs_;
        OperationOutcome outcome;
        outcome.succeeded = true;
        return outcome;
    }

private:
    std::atomic<int>& runs_;
};

/// Fails its first `lockHeldRuns` runs the way git's own "Unable to create
/// '.git/index.lock'" does, which is what a lock taken after preflight looks like.
class LockLosingOperation final : public Operation {
public:
    LockLosingOperation(std::atomic<int>& runs,
                        int lockHeldRuns,
                        bool retries,
                        GitError::Code code = GitError::Code::LockHeld)
        : runs_(runs), lockHeldRuns_(lockHeldRuns), retries_(retries), code_(code) {}

    std::string describe() const override { return "Lock losing test operation"; }

    bool retriesOnLockHeld() const override { return retries_; }

    OperationOutcome run(IProcessRunner&, const RepoPaths&, CancellationToken) override {
        const int run = ++runs_;
        OperationOutcome outcome;
        outcome.succeeded = run > lockHeldRuns_;
        if (!outcome.succeeded) {
            outcome.error = GitError(code_, "Could not create a Git lock file");
        }
        return outcome;
    }

private:
    std::atomic<int>& runs_;
    int lockHeldRuns_;
    bool retries_;
    GitError::Code code_;
};

class OperationRunnerLockWaitTest : public ::testing::Test {
protected:
    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        root_ = std::filesystem::temp_directory_path() /
                ("gbm-lockwait-" + std::string(info->name()));
        std::filesystem::remove_all(root_);
        std::filesystem::create_directories(root_ / ".git");
        paths_ = std::make_unique<RepoPaths>(root_, root_ / ".git", root_ / ".git");
    }

    void TearDown() override { std::filesystem::remove_all(root_); }

    void holdLock() { std::ofstream(paths_->indexLockFile()) << ""; }

    void releaseLock() { std::filesystem::remove(paths_->indexLockFile()); }

    std::filesystem::path root_;
    std::unique_ptr<RepoPaths> paths_;
    testing::FakeProcessRunner process_;
    std::atomic<int> runs_{0};
};

TEST_F(OperationRunnerLockWaitTest, ALockReleasedDuringTheWaitLetsTheOperationRun) {
    holdLock();
    OperationRunner runner(process_, *paths_, 10s);
    std::promise<OperationOutcome> done;
    runner.submit(std::make_unique<RecordingOperation>(runs_),
                  [&done](OperationOutcome outcome) { done.set_value(std::move(outcome)); });

    std::this_thread::sleep_for(100ms);
    EXPECT_EQ(runs_, 0) << "the operation must not start while the lock is held";
    releaseLock();

    const OperationOutcome outcome = done.get_future().get();
    EXPECT_TRUE(outcome.succeeded);
    EXPECT_EQ(runs_, 1);
}

TEST_F(OperationRunnerLockWaitTest, ALockHeldPastTheLimitIsReportedWithRetry) {
    holdLock();
    OperationRunner runner(process_, *paths_, 100ms);
    std::promise<OperationOutcome> done;
    const auto start = std::chrono::steady_clock::now();
    runner.submit(std::make_unique<RecordingOperation>(runs_),
                  [&done](OperationOutcome outcome) { done.set_value(std::move(outcome)); });

    const OperationOutcome outcome = done.get_future().get();
    EXPECT_GE(std::chrono::steady_clock::now() - start, 100ms);
    EXPECT_FALSE(outcome.succeeded);
    ASSERT_TRUE(outcome.error);
    EXPECT_EQ(outcome.error->code, GitError::Code::LockHeld);
    ASSERT_EQ(outcome.choices.size(), 1u);
    EXPECT_EQ(outcome.choices[0].kind, OperationChoice::Kind::Retry);
    EXPECT_EQ(runs_, 0);
}

TEST_F(OperationRunnerLockWaitTest, CancellingDuringTheWaitReportsCancelledNotLockHeld) {
    holdLock();
    OperationRunner runner(process_, *paths_, 60s);
    std::promise<OperationOutcome> done;
    auto handle =
        runner.submit(std::make_unique<RecordingOperation>(runs_),
                      [&done](OperationOutcome outcome) { done.set_value(std::move(outcome)); });
    std::this_thread::sleep_for(50ms);
    handle.cancel.cancel();

    auto future = done.get_future();
    ASSERT_EQ(future.wait_for(5s), std::future_status::ready);
    const OperationOutcome outcome = future.get();
    ASSERT_TRUE(outcome.error);
    EXPECT_EQ(outcome.error->code, GitError::Code::Cancelled);
    EXPECT_EQ(runs_, 0);
}

TEST_F(OperationRunnerLockWaitTest, AStaleLockIsReportedWithoutWaitingAndOffersRemoval) {
    holdLock();
    std::filesystem::last_write_time(paths_->indexLockFile(),
                                     std::filesystem::file_time_type::clock::now() - 1h);
    OperationRunner runner(process_, *paths_, 60s);
    std::promise<OperationOutcome> done;
    runner.submit(std::make_unique<RecordingOperation>(runs_),
                  [&done](OperationOutcome outcome) { done.set_value(std::move(outcome)); });

    auto future = done.get_future();
    ASSERT_EQ(future.wait_for(5s), std::future_status::ready)
        << "a lock this old belongs to nothing running; waiting cannot help";
    const OperationOutcome outcome = future.get();
    ASSERT_EQ(outcome.choices.size(), 2u);
    EXPECT_EQ(outcome.choices[1].kind, OperationChoice::Kind::RemoveLock);
    EXPECT_TRUE(std::filesystem::exists(paths_->indexLockFile()))
        << "removal stays the user's choice";
}

TEST_F(OperationRunnerLockWaitTest, ShuttingDownDuringTheWaitDoesNotSitOutTheLimit) {
    holdLock();
    const auto start = std::chrono::steady_clock::now();
    {
        OperationRunner runner(process_, *paths_, 60s);
        runner.submit(std::make_unique<RecordingOperation>(runs_), nullptr);
        std::this_thread::sleep_for(50ms);
    }
    EXPECT_LT(std::chrono::steady_clock::now() - start, 5s);
    EXPECT_EQ(runs_, 0);
}

TEST_F(OperationRunnerLockWaitTest, AnOperationThatLostTheLockIsRunAgain) {
    OperationRunner runner(process_, *paths_, 100ms);
    std::promise<OperationOutcome> done;
    runner.submit(std::make_unique<LockLosingOperation>(runs_, 1, /*retries=*/true),
                  [&done](OperationOutcome outcome) { done.set_value(std::move(outcome)); });

    EXPECT_TRUE(done.get_future().get().succeeded);
    EXPECT_EQ(runs_, 2);
    EXPECT_EQ(runner.undoJournal().size(), 1u) << "a retry is one operation to undo";
}

TEST_F(OperationRunnerLockWaitTest, RetriesStopAtTheLimitAndReportLockHeld) {
    OperationRunner runner(process_, *paths_, 100ms);
    std::promise<OperationOutcome> done;
    runner.submit(std::make_unique<LockLosingOperation>(runs_, 100, /*retries=*/true),
                  [&done](OperationOutcome outcome) { done.set_value(std::move(outcome)); });

    const OperationOutcome outcome = done.get_future().get();
    ASSERT_TRUE(outcome.error);
    EXPECT_EQ(outcome.error->code, GitError::Code::LockHeld);
    EXPECT_EQ(runs_, 1 + OperationRunner::kLockRetries);
}

TEST_F(OperationRunnerLockWaitTest, AnOperationThatDidNotOptInRunsOnce) {
    OperationRunner runner(process_, *paths_, 100ms);
    std::promise<OperationOutcome> done;
    runner.submit(std::make_unique<LockLosingOperation>(runs_, 1, /*retries=*/false),
                  [&done](OperationOutcome outcome) { done.set_value(std::move(outcome)); });

    EXPECT_FALSE(done.get_future().get().succeeded);
    EXPECT_EQ(runs_, 1);
}

TEST_F(OperationRunnerLockWaitTest, AnotherErrorIsNotRetried) {
    OperationRunner runner(process_, *paths_, 100ms);
    std::promise<OperationOutcome> done;
    runner.submit(
        std::make_unique<LockLosingOperation>(runs_, 1, /*retries=*/true, GitError::Code::Unknown),
        [&done](OperationOutcome outcome) { done.set_value(std::move(outcome)); });

    EXPECT_FALSE(done.get_future().get().succeeded);
    EXPECT_EQ(runs_, 1);
}

TEST_F(OperationRunnerLockWaitTest, OnlyIdempotentIndexOperationsOptIn) {
    EXPECT_TRUE(makeStageFilesOperation(StageFilesRequest{{"a"}})->retriesOnLockHeld());
    EXPECT_TRUE(makeUnstageFilesOperation(UnstageFilesRequest{{"a"}})->retriesOnLockHeld());
    EXPECT_TRUE(makePartialStageOperation(PartialStageRequest{})->retriesOnLockHeld());
    EXPECT_FALSE(makeDiscardLinesOperation(DiscardLinesRequest{})->retriesOnLockHeld());
}

}  // namespace
}  // namespace gbm
