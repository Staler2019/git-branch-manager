#include "core/git/RepoPaths.h"
#include "core/git/ops/MaintenanceOps.h"
#include "support/FakeProcessRunner.h"

#include <chrono>
#include <filesystem>
#include <fstream>
#include <future>
#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

// --- shouldOfferCommitGraph -------------------------------------------------
// Pure decision table, no repository needed -- see the header comment on why
// this logic was pulled out of RepositorySession instead of living there.

TEST(MaintenanceOps, NeverOffersWhenAGraphAlreadyExists) {
    EXPECT_FALSE(shouldOfferCommitGraph(
        /*hasGraph=*/true, kCommitGraphAdviceMinRows * 10, CommitGraphPreference::Unset));
}

TEST(MaintenanceOps, NeverOffersAfterTheUserDeclined) {
    EXPECT_FALSE(shouldOfferCommitGraph(
        /*hasGraph=*/false, kCommitGraphAdviceMinRows * 10, CommitGraphPreference::Declined));
}

TEST(MaintenanceOps, NeverOffersOnceEnabledEvenIfTheGraphIsMissing) {
    // Enabled means "keep this maintained", not "ask every time it happens to
    // be missing" -- e.g. right after a `git gc` pruned an out-of-date graph,
    // before the next write runs. Re-prompting here would be nagging, not
    // helping; the app is expected to just rebuild it, not ask again.
    EXPECT_FALSE(shouldOfferCommitGraph(
        /*hasGraph=*/false, kCommitGraphAdviceMinRows * 10, CommitGraphPreference::Enabled));
}

TEST(MaintenanceOps, DoesNotOfferBelowTheAdviceThreshold) {
    EXPECT_FALSE(shouldOfferCommitGraph(
        /*hasGraph=*/false, kCommitGraphAdviceMinRows - 1, CommitGraphPreference::Unset));
}

TEST(MaintenanceOps, OffersAtOrAboveTheAdviceThresholdWhenUnset) {
    EXPECT_TRUE(shouldOfferCommitGraph(
        /*hasGraph=*/false, kCommitGraphAdviceMinRows, CommitGraphPreference::Unset));
}

// --- hasCommitGraph ----------------------------------------------------------

/// A throwaway `objects/` tree, mirroring DiscoveryTest's TempTree: enough
/// directory structure for RepoPaths::commitGraphFile()/commitGraphChainFile()
/// to resolve against, without a real git repository.
class CommitGraphDetection : public ::testing::Test {
protected:
    void SetUp() override {
        const auto* info = ::testing::UnitTest::GetInstance()->current_test_info();
        root_ = std::filesystem::temp_directory_path() /
                ("gbm-test-" + std::string(info->test_suite_name()) + "-" +
                 std::string(info->name()));
        std::filesystem::remove_all(root_);
        const auto gitDir = root_ / ".git";
        std::filesystem::create_directories(gitDir / "objects" / "info");
        paths_ = RepoPaths(root_, gitDir, gitDir);
    }

    void TearDown() override {
        std::error_code ec;
        std::filesystem::remove_all(root_, ec);
    }

    static void touch(const std::filesystem::path& file) {
        std::filesystem::create_directories(file.parent_path());
        std::ofstream(file).put('\0');
    }

    std::filesystem::path root_;
    RepoPaths paths_;
};

TEST_F(CommitGraphDetection, FalseWhenNeitherFormExists) {
    EXPECT_FALSE(hasCommitGraph(paths_));
}

TEST_F(CommitGraphDetection, TrueForTheSingleFileForm) {
    touch(paths_.commitGraphFile());
    EXPECT_TRUE(hasCommitGraph(paths_));
}

TEST_F(CommitGraphDetection, TrueForTheSplitChainForm) {
    touch(paths_.commitGraphChainFile());
    EXPECT_TRUE(hasCommitGraph(paths_));
}

// --- shouldRefreshIndex -----------------------------------------------------

TEST(MaintenanceOps, RefreshesTheIndexWhenItNeverHas) {
    EXPECT_TRUE(shouldRefreshIndex(std::nullopt, std::chrono::steady_clock::now()));
}

TEST(MaintenanceOps, DoesNotRefreshTheIndexInsideTheInterval) {
    const auto last = std::chrono::steady_clock::now();
    EXPECT_FALSE(shouldRefreshIndex(last, last));
    EXPECT_FALSE(
        shouldRefreshIndex(last, last + kIndexRefreshMinInterval - std::chrono::milliseconds(1)));
}

TEST(MaintenanceOps, RefreshesTheIndexOnceTheIntervalHasPassed) {
    const auto last = std::chrono::steady_clock::now();
    EXPECT_TRUE(shouldRefreshIndex(last, last + kIndexRefreshMinInterval));
}

// --- makeRefreshIndexOperation ----------------------------------------------

class RefreshIndexOperation : public CommitGraphDetection {
protected:
    OperationOutcome runToCompletion(OperationRunner& runner) {
        std::promise<OperationOutcome> done;
        auto future = done.get_future();
        runner.submit(makeRefreshIndexOperation(),
                      [&done](OperationOutcome outcome) { done.set_value(std::move(outcome)); });
        EXPECT_EQ(future.wait_for(std::chrono::seconds(5)), std::future_status::ready)
            << "nobody asked for this work, so it must not sit out a lock";
        return future.get();
    }

    testing::FakeProcessRunner process_;
};

TEST_F(RefreshIndexOperation, RunsUpdateIndexRefreshAndAddsNoUndoPoint) {
    OperationRunner runner(process_, paths_);
    EXPECT_TRUE(runToCompletion(runner).succeeded);

    ASSERT_EQ(process_.invocationCount(), 1u);
    EXPECT_EQ(process_.invokedArgs(0),
              (std::vector<std::string>{"update-index", "-q", "--refresh"}));
    EXPECT_TRUE(runner.undoJournal().empty());
}

TEST_F(RefreshIndexOperation, TheExitCodesAnUnmergedOrLockedIndexGivesAreNotErrors) {
    OperationRunner runner(process_, paths_);
    runToCompletion(runner);

    ASSERT_EQ(process_.invocationCount(), 1u);
    const GitCommand& command = process_.invocations()[0];
    EXPECT_TRUE(command.isBenignExitCode(1)) << "an unmerged entry after a stash pop conflict";
    EXPECT_TRUE(command.isBenignExitCode(128)) << "another process took the lock first";
    EXPECT_FALSE(command.isBenignExitCode(129)) << "a usage error is still our bug";
}

TEST_F(RefreshIndexOperation, YieldsAtOnceToAHeldLockWithoutRunningGit) {
    std::ofstream(paths_.indexLockFile()) << "";
    OperationRunner runner(process_, paths_, std::chrono::seconds(60));

    const OperationOutcome outcome = runToCompletion(runner);

    EXPECT_FALSE(outcome.succeeded);
    EXPECT_EQ(process_.invocationCount(), 0u);
}

TEST_F(RefreshIndexOperation, IsBackgroundWorkThatCannotBeKilled) {
    const auto operation = makeRefreshIndexOperation();
    EXPECT_TRUE(operation->isBackground());
    EXPECT_TRUE(operation->isHousekeeping());
    EXPECT_FALSE(operation->killableMidFlight());
}

}  // namespace
}  // namespace gbm
