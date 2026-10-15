// OperationRunner::cancel(id): a user's Cancel, decided per capi unit.
//
// 使用者裁定 (2026-10-15): 「吃cancellationToken 如果capi吃的到cancellationToken。
// 如果真的 cancel 了，capi不行cancel 會拋錯」 and 「capi 中有 git lock 會產生的動作都
// 不能取消」. The unit declares which it is through
// Operation::killableMidFlight(); an operation still in the queue has run
// nothing and taken no lock, so it is always cancellable.
//
// The operations here run no git at all -- each blocks on a latch the test
// controls -- so "queued" and "running" are states the test holds the runner
// in, not races it has to win.
#include "core/git/OperationId.h"
#include "core/git/OperationRunner.h"
#include "core/git/RepoPaths.h"
#include "support/FakeProcessRunner.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <filesystem>
#include <gtest/gtest.h>
#include <memory>
#include <mutex>
#include <optional>
#include <string>

namespace gbm {
namespace {

/// A one-shot gate a test opens from its own thread.
struct Latch {
    std::mutex mutex;
    std::condition_variable cv;
    bool open = false;

    void release() {
        {
            std::lock_guard<std::mutex> lock(mutex);
            open = true;
        }
        cv.notify_all();
    }

    /// Waits until released or `token` is cancelled; returns whether cancelled.
    bool waitOrCancelled(const CancellationToken& token) {
        std::unique_lock<std::mutex> lock(mutex);
        while (!open) {
            if (token.isCancelled()) {
                return true;
            }
            cv.wait_for(lock, std::chrono::milliseconds(5));
        }
        return token.isCancelled();
    }

    void wait() {
        std::unique_lock<std::mutex> lock(mutex);
        cv.wait(lock, [this] { return open; });
    }
};

class BlockingOperation final : public Operation {
public:
    BlockingOperation(bool killable, Latch& gate, Latch* started, std::atomic<bool>* ran)
        : killable_(killable), gate_(gate), started_(started), ran_(ran) {}

    std::string describe() const override { return "Blocking test operation"; }

    bool killableMidFlight() const override { return killable_; }

    OperationOutcome run(IProcessRunner&, const RepoPaths&, CancellationToken token) override {
        if (ran_ != nullptr) {
            ran_->store(true);
        }
        if (started_ != nullptr) {
            started_->release();
        }
        OperationOutcome outcome;
        if (gate_.waitOrCancelled(token)) {
            outcome.succeeded = false;
            outcome.error = GitError(GitError::Code::Cancelled, "Operation cancelled");
            return outcome;
        }
        outcome.succeeded = true;
        return outcome;
    }

private:
    bool killable_;
    Latch& gate_;
    Latch* started_;
    std::atomic<bool>* ran_;
};

class OperationRunnerCancelTest : public ::testing::Test {
protected:
    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        repo_ = std::filesystem::temp_directory_path() /
                ("gbm-runner-cancel-" + std::string(info->name()));
        std::filesystem::remove_all(repo_);
        std::filesystem::create_directories(repo_ / ".git");
        paths_ = RepoPaths(repo_, repo_ / ".git", repo_ / ".git");
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(repo_, ec);
    }

    std::filesystem::path repo_;
    RepoPaths paths_;
    testing::FakeProcessRunner fake_;
};

TEST_F(OperationRunnerCancelTest, AQueuedUnitIsCancelledEvenWhenItCouldNotBeKilled) {
    OperationRunner operations(fake_, paths_);
    Latch frontGate, frontStarted, queuedGate;
    std::atomic<bool> queuedRan{false};

    operations.submit(std::make_unique<BlockingOperation>(false, frontGate, &frontStarted, nullptr),
                      [](OperationOutcome) {});
    frontStarted.wait();

    std::optional<OperationOutcome> queuedOutcome;
    const auto queued = operations.submit(
        std::make_unique<BlockingOperation>(false, queuedGate, nullptr, &queuedRan),
        [&queuedOutcome](OperationOutcome outcome) { queuedOutcome = std::move(outcome); });

    EXPECT_EQ(operations.cancel(queued.id), OperationRunner::CancelResult::Cancelled);

    frontGate.release();
    // Released too, so a broken cancel fails on queuedRan below rather than
    // hanging drain() on an operation nobody would ever let finish.
    queuedGate.release();
    operations.drain();

    EXPECT_FALSE(queuedRan.load()) << "a cancelled queued unit must never start";
    ASSERT_TRUE(queuedOutcome.has_value());
    EXPECT_FALSE(queuedOutcome->succeeded);
    ASSERT_TRUE(queuedOutcome->error.has_value());
    EXPECT_EQ(queuedOutcome->error->code, GitError::Code::Cancelled);
}

TEST_F(OperationRunnerCancelTest, ARunningKillableUnitIsCancelled) {
    OperationRunner operations(fake_, paths_);
    Latch gate, started;

    std::optional<OperationOutcome> outcome;
    const auto handle =
        operations.submit(std::make_unique<BlockingOperation>(true, gate, &started, nullptr),
                          [&outcome](OperationOutcome result) { outcome = std::move(result); });
    started.wait();

    EXPECT_EQ(operations.cancel(handle.id), OperationRunner::CancelResult::Cancelled);
    // Released regardless, so a broken cancel fails the assertions below
    // instead of hanging drain(): the operation reports what its token says.
    gate.release();
    operations.drain();

    ASSERT_TRUE(outcome.has_value());
    ASSERT_TRUE(outcome->error.has_value());
    EXPECT_EQ(outcome->error->code, GitError::Code::Cancelled);
}

TEST_F(OperationRunnerCancelTest, ARunningUnitThatCannotBeKilledRefusesAndRunsToCompletion) {
    OperationRunner operations(fake_, paths_);
    Latch gate, started;

    std::optional<OperationOutcome> outcome;
    const auto handle =
        operations.submit(std::make_unique<BlockingOperation>(false, gate, &started, nullptr),
                          [&outcome](OperationOutcome result) { outcome = std::move(result); });
    started.wait();

    EXPECT_EQ(operations.cancel(handle.id), OperationRunner::CancelResult::NotCancellable);
    EXPECT_FALSE(handle.cancel.isCancelled()) << "a refused cancel must not trip the token";

    gate.release();
    operations.drain();

    ASSERT_TRUE(outcome.has_value());
    EXPECT_TRUE(outcome->succeeded);
}

TEST_F(OperationRunnerCancelTest, AnUnknownOrFinishedIdIsNotFound) {
    OperationRunner operations(fake_, paths_);
    Latch gate;
    gate.release();

    const auto handle =
        operations.submit(std::make_unique<BlockingOperation>(false, gate, nullptr, nullptr),
                          [](OperationOutcome) {});
    operations.drain();

    EXPECT_EQ(operations.cancel(handle.id), OperationRunner::CancelResult::NotFound);
    EXPECT_EQ(operations.cancel(handle.id + 1000), OperationRunner::CancelResult::NotFound);
}

// The id a user's Cancel names is the one a log row carries, and a log row can
// reach every session open on the same directories -- so two runners must
// never hand out the same id.
TEST_F(OperationRunnerCancelTest, IdsAreUniqueAcrossRunners) {
    // One fake each: FakeProcessRunner is not thread-safe, and both workers
    // reach it at once through recordUndoPoint()'s RefStore.
    testing::FakeProcessRunner otherFake;
    OperationRunner first(fake_, paths_);
    OperationRunner second(otherFake, paths_);
    Latch gate;
    gate.release();

    const auto a = first.submit(std::make_unique<BlockingOperation>(false, gate, nullptr, nullptr),
                                [](OperationOutcome) {});
    const auto b = second.submit(std::make_unique<BlockingOperation>(false, gate, nullptr, nullptr),
                                 [](OperationOutcome) {});
    first.drain();
    second.drain();

    EXPECT_NE(a.id, b.id);
    EXPECT_EQ(second.cancel(a.id), OperationRunner::CancelResult::NotFound);
}

class ReadsItsQueuedId final : public Operation {
public:
    explicit ReadsItsQueuedId(std::uint64_t& seen) : seen_(seen) {}

    std::string describe() const override { return "Reads its queued id"; }

    OperationOutcome run(IProcessRunner&, const RepoPaths&, CancellationToken) override {
        seen_ = currentQueuedOperationId();
        OperationOutcome outcome;
        outcome.succeeded = true;
        return outcome;
    }

private:
    std::uint64_t& seen_;
};

TEST_F(OperationRunnerCancelTest, AnOperationSeesItsOwnIdOnlyWhileItRuns) {
    OperationRunner operations(fake_, paths_);
    std::uint64_t first = 0;
    std::uint64_t second = 0;

    const auto a =
        operations.submit(std::make_unique<ReadsItsQueuedId>(first), [](OperationOutcome) {});
    const auto b =
        operations.submit(std::make_unique<ReadsItsQueuedId>(second), [](OperationOutcome) {});
    operations.drain();

    EXPECT_EQ(first, a.id);
    EXPECT_EQ(second, b.id);
    EXPECT_EQ(currentQueuedOperationId(), 0U) << "not on the worker thread";
}

}  // namespace
}  // namespace gbm
