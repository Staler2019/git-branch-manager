// What one working-copy read publishes when the line-count passes fail.
//
// The conflict list -- and so, for a plain merge, `conflictActive` itself --
// comes only from this read. When either `git diff --numstat` pass failed the
// whole read used to fail with it, so on a machine slow enough for numstat's
// rename detection to time out, a merge's conflicts simply never appeared.
// Line counts are badges; conflicts are material state. Only the badges may be
// lost.
#include "core/git/WorkingCopyStatus.h"
#include "support/FakeProcessRunner.h"

#include <gtest/gtest.h>
#include <string>
#include <vector>

namespace gbm {
namespace {

using ::gbm::testing::FakeProcessRunner;

/// `git status --porcelain=v2 -z` with one conflicted path (both modified).
FakeProcessRunner::Response conflictedStatus() {
    FakeProcessRunner::Response response;
    const std::string zeros(40, '0');
    response.out = "u UU N... 100644 100644 100644 100644 " + zeros + " " + zeros + " " + zeros +
                   " shared.txt";
    response.out.push_back('\0');
    return response;
}

FakeProcessRunner::Response timedOut() {
    FakeProcessRunner::Response response;
    response.timedOut = true;
    return response;
}

FakeProcessRunner::Response cancelledRun() {
    FakeProcessRunner::Response response;
    response.cancelled = true;
    return response;
}

const RepoPaths kPaths{"/no/such/repo", "/no/such/repo/.git", ""};

TEST(WorkingCopyStatusRead, ANumstatTimeoutStillPublishesTheConflicts) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, conflictedStatus());
    runner.whenArgsContain({"diff", "--numstat"}, timedOut());
    WorkingCopyStatusReader reader(runner, kPaths);

    const auto result = reader.read(CancellationToken());

    ASSERT_TRUE(result) << result.error().message;
    EXPECT_EQ(result.value()->conflicted().size(), 1u);
    EXPECT_TRUE(result.value()->lineCountsUnavailable);
}

TEST(WorkingCopyStatusRead, CountsThatArrivedAreNotMarkedUnavailable) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, conflictedStatus());
    WorkingCopyStatusReader reader(runner, kPaths);

    const auto result = reader.read(CancellationToken());

    ASSERT_TRUE(result);
    EXPECT_FALSE(result.value()->lineCountsUnavailable);
}

// A cancelled read is abandoned work, not a slow one: publishing it would
// replace real badges with zeros and flash "unavailable" on every repository
// switch, for counts that were never actually out of reach.
TEST(WorkingCopyStatusRead, ACancelledNumstatStillFailsTheRead) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, conflictedStatus());
    runner.whenArgsContain({"diff", "--numstat"}, cancelledRun());
    WorkingCopyStatusReader reader(runner, kPaths);

    const auto result = reader.read(CancellationToken());

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::Cancelled);
}

TEST(WorkingCopyStatusRead, AFailedStatusStillFailsTheRead) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"status", "--porcelain=v2"}, timedOut());
    WorkingCopyStatusReader reader(runner, kPaths);

    const auto result = reader.read(CancellationToken());

    ASSERT_FALSE(result);
    EXPECT_EQ(result.error().code, GitError::Code::Timeout);
}

}  // namespace
}  // namespace gbm
