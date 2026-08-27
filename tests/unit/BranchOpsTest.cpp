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

    // The "Delete anyway" choice must agree with the summary above it: once
    // the probe found the commits elsewhere, the explanation is the same
    // string as the summary (naming the concrete ref), not a separate,
    // looser sentence that could drift out of sync with it -- and it must
    // not still warn that deleting makes them "only reachable through the
    // reflog", which directly contradicts "will not lose anything".
    ASSERT_FALSE(outcome.choices.empty());
    EXPECT_EQ(outcome.choices.front().explanation, outcome.summary);
    EXPECT_NE(outcome.choices.front().explanation.find("origin/main"), std::string::npos);
    EXPECT_NE(outcome.choices.front().explanation.find("will not lose"), std::string::npos);
    EXPECT_EQ(outcome.choices.front().explanation.find("reflog"), std::string::npos);
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
    // The choice explanation must be pluralized the same way -- it is a
    // separate string built independently of the summary.
    ASSERT_FALSE(outcome.choices.empty());
    EXPECT_NE(outcome.choices.front().explanation.find("These branches"), std::string::npos);
    EXPECT_EQ(outcome.choices.front().explanation.find("This branch "), std::string::npos);
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

/// `git branch -d/-D` is per-name: it deletes what it can and exits 1 if any
/// one name failed. Measured on git 2.55.0:
///
///   $ git branch -d a cur b
///   error: cannot delete branch 'cur' used by worktree at '...'
///   Deleted branch a (was 668c5ce).
///   Deleted branch b (was 668c5ce).
///   exit=1
///
/// So `a` and `b` really were deleted while the app reported total failure --
/// and the "Delete anyway" retry then resent all three names, at which point
/// git answered `error: branch 'a' not found` and exited 1 a second time.
/// These tests script that shape.
void scriptExistingBranches(FakeProcessRunner& runner, const std::string& refnames) {
    FakeProcessRunner::Response existing;
    existing.exitCode = 0;
    existing.out = refnames;
    runner.whenArgsContain({"for-each-ref", "--format=%(refname:short)", "refs/heads/"}, existing);
}

TEST(DeleteBranchOperation, SkipsNamesThatNoLongerExistBeforeRunning) {
    // The retry after "Delete anyway": the first `-d` already deleted three
    // of the four, so resending all four makes git print "not found" three
    // times and exit 1 even though `-D` did exactly what was asked.
    FakeProcessRunner runner;
    scriptExistingBranches(runner, "main\nstill-here\n");

    DeleteBranchRequest request;
    request.names = {"gone-a", "still-here", "gone-b"};
    request.force = true;
    auto operation = makeDeleteBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    // Exactly one delete, carrying only the name that is still there.
    std::vector<std::string> deleteArgs;
    for (std::size_t i = 0; i < runner.invocationCount(); ++i) {
        std::vector<std::string> args = runner.invokedArgs(i);
        if (!args.empty() && args[0] == "branch") {
            deleteArgs = args;
        }
    }
    ASSERT_EQ(deleteArgs.size(), 3u);
    EXPECT_EQ(deleteArgs[0], "branch");
    EXPECT_EQ(deleteArgs[1], "-D");
    EXPECT_EQ(deleteArgs[2], "still-here");
}

TEST(DeleteBranchOperation, SucceedsWithoutRunningGitWhenEveryNameIsAlreadyGone) {
    // Same retry, one step further: every name the user selected was deleted
    // by the first pass. Running git here can only produce "not found" and a
    // failure dialog for work that is already done.
    FakeProcessRunner runner;
    scriptExistingBranches(runner, "main\n");

    DeleteBranchRequest request;
    request.names = {"gone-a", "gone-b"};
    request.force = true;
    auto operation = makeDeleteBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    for (std::size_t i = 0; i < runner.invocationCount(); ++i) {
        EXPECT_NE(runner.invokedArgs(i)[0], "branch");
    }
}

TEST(DeleteBranchOperation, AnEmptyBranchListIsUnknownRatherThanAllDeleted) {
    // A repository you are deleting a local branch in always has at least
    // that branch, so an empty refs/heads/ listing means the probe told us
    // nothing -- reading it as "everything is already gone" would report
    // success for a delete that never ran, which is the one failure mode
    // worse than the bug being fixed.
    FakeProcessRunner runner;
    FakeProcessRunner::Response empty;
    empty.exitCode = 0;
    empty.out = "";
    runner.whenArgsContain({"for-each-ref", "--format=%(refname:short)", "refs/heads/"}, empty);

    DeleteBranchRequest request;
    request.names = {"feature"};
    request.force = true;
    auto operation = makeDeleteBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    // git really ran, with the name the user asked for.
    bool ranDelete = false;
    for (std::size_t i = 0; i < runner.invocationCount(); ++i) {
        std::vector<std::string> args = runner.invokedArgs(i);
        ranDelete = ranDelete || (args.size() == 3 && args[0] == "branch" && args[1] == "-D" &&
                                  args[2] == "feature");
    }
    EXPECT_TRUE(ranDelete);
    EXPECT_EQ(outcome.summary.find("Already deleted"), std::string::npos);
}

TEST(DeleteBranchOperation, ReportsWhichBranchesWereDeletedWhenOnlySomeFailed) {
    // The headline case. `-d a locked b` deletes a and b, refuses `locked`,
    // exits 1. Reporting that as total failure is a lie in both directions:
    // it hides two real deletions and implies the whole selection survived.
    FakeProcessRunner runner;

    FakeProcessRunner::Response before;
    before.exitCode = 0;
    before.out = "main\na\nlocked\nb\n";
    FakeProcessRunner::Response after;
    after.exitCode = 0;
    after.out = "main\nlocked\n";
    // Same command, two answers: the operation probes once before the delete
    // and once after, and the difference *is* the set that really went.
    runner.whenArgsContainInTurn({"for-each-ref", "--format=%(refname:short)", "refs/heads/"},
                                 {before, after});

    FakeProcessRunner::Response failure;
    failure.exitCode = 1;
    failure.err = "error: cannot delete branch 'locked' used by worktree at '/wt'\n";
    runner.whenArgsContain({"branch", "-d", "a"}, failure);

    DeleteBranchRequest request;
    request.names = {"a", "locked", "b"};
    auto operation = makeDeleteBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    // Names both halves: what really went, and what is still standing.
    EXPECT_NE(outcome.summary.find("Deleted a, b"), std::string::npos);
    EXPECT_NE(outcome.summary.find("locked"), std::string::npos);
}

TEST(DeleteBranchOperation, DoesNotClaimDeletionsWhenNothingWasDeleted) {
    // The all-or-nothing failure must not grow a spurious "Deleted ..."
    // clause: the before/after probe answering identically means git deleted
    // nothing, and the message has to stay the plain failure it always was.
    FakeProcessRunner runner;

    FakeProcessRunner::Response unchanged;
    unchanged.exitCode = 0;
    unchanged.out = "main\nfeature\n";
    runner.whenArgsContainInTurn({"for-each-ref", "--format=%(refname:short)", "refs/heads/"},
                                 {unchanged, unchanged});

    scriptFailedDelete(runner);

    DeleteBranchRequest request;
    request.names = {"feature"};
    auto operation = makeDeleteBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    EXPECT_EQ(outcome.summary.find("Deleted"), std::string::npos);
    // Still the message the failure path already produced, untouched.
    EXPECT_NE(outcome.summary.find("reflog"), std::string::npos);
}

TEST(CreateBranchOperation, LeavesHeadAloneWhenCheckoutAfterIsFalse) {
    FakeProcessRunner runner;

    CreateBranchRequest request;
    request.name = "feature";
    request.checkoutAfter = false;
    auto operation = makeCreateBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_TRUE(outcome.succeeded);
    ASSERT_EQ(runner.invocationCount(), 1u);
    EXPECT_EQ(runner.invokedArgs(0)[0], "branch");
}

TEST(CreateBranchOperation, ChecksOutTheNewBranchWhenCheckoutAfterIsTrue) {
    FakeProcessRunner runner;

    CreateBranchRequest request;
    request.name = "feature";
    request.checkoutAfter = true;
    auto operation = makeCreateBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    ASSERT_TRUE(outcome.succeeded);
    ASSERT_EQ(runner.invocationCount(), 2u);
    EXPECT_EQ(runner.invokedArgs(0)[0], "branch");
    EXPECT_EQ(runner.invokedArgs(1)[0], "checkout");
    EXPECT_EQ(runner.invokedArgs(1)[1], "feature");
}

TEST(CreateBranchOperation, ReportsCheckoutFailureAfterBranchWasAlreadyCreated) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response checkoutFailure;
    checkoutFailure.exitCode = 1;
    checkoutFailure.err = "error: your local changes would be overwritten by checkout\n";
    runner.whenArgsContain({"checkout", "feature"}, checkoutFailure);

    CreateBranchRequest request;
    request.name = "feature";
    request.checkoutAfter = true;
    auto operation = makeCreateBranchOperation(request);

    OperationOutcome outcome = operation->run(runner, testPaths(), CancellationToken{});

    EXPECT_FALSE(outcome.succeeded);
    EXPECT_NE(outcome.summary.find("overwritten"), std::string::npos);
}

}  // namespace
}  // namespace gbm
