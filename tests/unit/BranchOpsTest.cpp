// Tests for DeleteBranchOperation's handling of an unmerged local delete,
// using FakeProcessRunner instead of a real repository -- the two branches
// that matter here (the remote-tracking view knows the commit is elsewhere /
// it does not) are exactly the git responses a fake runner can script on
// demand, without depending on git's own timing to reach either state.
#include "core/git/ops/BranchOps.h"
#include "support/FakeProcessRunner.h"

#include <gtest/gtest.h>
#include <string>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

RepoPaths testPaths() {
    return RepoPaths("/repo", "/repo/.git", "/repo/.git");
}

constexpr const char* kNotFullyMergedStderr =
    "error: the branch 'feature' is not fully merged\n"
    "hint: If you are sure you want to delete it, run 'git branch -D feature'\n"
    "hint: Disable this message with \"git config set advice.forceDeleteBranch false\"\n";

void scriptFailedDelete(FakeProcessRunner& runner) {
    FakeProcessRunner::Response failure;
    failure.exitCode = 1;
    failure.err = kNotFullyMergedStderr;
    runner.whenArgsContain({"branch", "-d", "feature"}, failure);
}

TEST(DeleteBranchOperation, ReportsSafeToDeleteWhenAnotherRemoteRefContainsIt) {
    FakeProcessRunner runner;
    scriptFailedDelete(runner);

    // The branch's own upstream ref is present (it was pushed) but that alone
    // does not mean it is merged -- origin/main containing it is the signal
    // that deleting locally loses nothing.
    FakeProcessRunner::Response probe;
    probe.exitCode = 0;
    probe.out = "refs/remotes/origin/feature\nrefs/remotes/origin/main\n";
    runner.whenArgsContain({"for-each-ref", "--contains", "feature", "refs/remotes/"}, probe);

    DeleteBranchRequest request;
    request.names = {"feature"};
    auto operation = makeDeleteBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    // Names the remote it found the commits on, and is explicit that nothing
    // is lost -- this is the "actually safe, just a local view problem" case.
    EXPECT_NE(outcome.summary.find("origin/main"), std::string::npos);
    EXPECT_NE(outcome.summary.find("not lose"), std::string::npos);
    // Never claims certainty it does not have.
    EXPECT_EQ(outcome.summary.find("Git reported an error"), std::string::npos);
}

TEST(DeleteBranchOperation, SkipsOriginHeadAsTheReportedRemote) {
    FakeProcessRunner runner;
    scriptFailedDelete(runner);

    // `for-each-ref` on a real repo returns refs/remotes/<remote>/HEAD (a
    // symref, always sorted first because 'H' < 'm') alongside the actual
    // branches it points at. Reporting "already exists on origin/HEAD" would
    // be meaningless to a user -- the real, nameable branch (origin/main)
    // must be what gets surfaced.
    FakeProcessRunner::Response probe;
    probe.exitCode = 0;
    probe.out = "refs/remotes/origin/HEAD\nrefs/remotes/origin/main\n";
    runner.whenArgsContain({"for-each-ref", "--contains", "feature", "refs/remotes/"}, probe);

    DeleteBranchRequest request;
    request.names = {"feature"};
    auto operation = makeDeleteBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    EXPECT_NE(outcome.summary.find("origin/main"), std::string::npos);
    EXPECT_EQ(outcome.summary.find("origin/HEAD"), std::string::npos);
}

TEST(DeleteBranchOperation, SuggestsFetchingWhenNoRemoteRefContainsIt) {
    FakeProcessRunner runner;
    scriptFailedDelete(runner);

    // Only the branch's own upstream ref shows up -- pushed, but nothing else
    // known locally contains it. This is exactly the state a stale
    // remote-tracking view produces, so the summary must not claim certainty.
    FakeProcessRunner::Response probe;
    probe.exitCode = 0;
    probe.out = "refs/remotes/origin/feature\n";
    runner.whenArgsContain({"for-each-ref", "--contains", "feature", "refs/remotes/"}, probe);

    DeleteBranchRequest request;
    request.names = {"feature"};
    auto operation = makeDeleteBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    EXPECT_NE(outcome.summary.find("fetch"), std::string::npos);
    // Must not overclaim: this is "not found in the last-fetched view", not a
    // confirmed "this really was never merged anywhere".
    EXPECT_EQ(outcome.summary.find("Git reported an error"), std::string::npos);
}

TEST(DeleteBranchOperation, PluralizesTheNotMergedSummaryForAMultiBranchDelete) {
    FakeProcessRunner runner;

    // Same "not fully merged" stderr, but for a request naming several
    // branches at once -- the refineSummaryFromRemoteRefs probe only runs for
    // a single-name request, so this exercises the summary BranchOps sets
    // before that guard, which must read "These branches", not "This branch".
    FakeProcessRunner::Response failure;
    failure.exitCode = 1;
    failure.err =
        "error: the branch 'multi-a' is not fully merged\n"
        "hint: If you are sure you want to delete it, run 'git branch -D multi-a'\n";
    runner.whenArgsContain({"branch", "-d", "multi-a", "multi-b"}, failure);

    DeleteBranchRequest request;
    request.names = {"multi-a", "multi-b"};
    auto operation = makeDeleteBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    EXPECT_NE(outcome.summary.find("These branches"), std::string::npos);
    EXPECT_EQ(outcome.summary.find("This branch "), std::string::npos);
}

TEST(DeleteBranchOperation, KeepsExistingSummaryWhenTheProbeItselfFails) {
    FakeProcessRunner runner;
    scriptFailedDelete(runner);

    FakeProcessRunner::Response probeFailure;
    probeFailure.exitCode = 128;
    probeFailure.err = "fatal: not a git repository\n";
    runner.whenArgsContain({"for-each-ref", "--contains", "feature", "refs/remotes/"},
                           probeFailure);

    DeleteBranchRequest request;
    request.names = {"feature"};
    auto operation = makeDeleteBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    // A secondary probe failure must never mask the primary delete failure
    // with something less informative.
    EXPECT_NE(outcome.summary.find("not merged"), std::string::npos);
    bool offersForce = false;
    for (const OperationChoice& choice : outcome.choices) {
        offersForce = offersForce || choice.kind == OperationChoice::Kind::ForceDiscard;
    }
    EXPECT_TRUE(offersForce);
}

}  // namespace
}  // namespace gbm
