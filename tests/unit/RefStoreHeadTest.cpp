// RefStore::readHead()'s command shape, asserted through FakeProcessRunner.
//
// The point of these tests is the *invocation count* as much as the parsed
// result. readHead() used to issue two git processes unconditionally -- a
// `symbolic-ref` for the branch name followed by a `rev-parse` for the oid --
// and it is on two hot paths at once: RefStore::load() runs it on every refs
// refresh, and OperationRunner::recordUndoPoint() runs it before every
// undoable write. Process creation is roughly two orders of magnitude more
// expensive on Windows than on Linux, so a spare spawn there is not a
// rounding error; see docs/reports/windows-process-cost.md.
//
// A behaviour-only test would stay green if someone reverted the merge back to
// two commands, so every case below pins invocationCount() explicitly.
#include "core/git/RefStore.h"
#include "support/FakeProcessRunner.h"

#include <algorithm>
#include <gtest/gtest.h>
#include <string>
#include <vector>

namespace gbm {
namespace {

using testing::FakeProcessRunner;

RepoPaths testPaths() {
    return RepoPaths("/repo", "/repo/.git", "/repo/.git");
}

constexpr const char* kOid = "8de891509a719cf9c23b3b6e9baebb9ad30f5878";

/// `run()` reassembles stdout from the line splitter and trims the trailing
/// separator, so a two-line git result reaches the caller as "a\nb" with no
/// final newline. The fake passes `out` through verbatim, so the scripted
/// responses here must already be in that shape.
FakeProcessRunner::Response combinedReply(const std::string& oid, const std::string& symbolic) {
    FakeProcessRunner::Response reply;
    reply.out = oid + "\n" + symbolic;
    return reply;
}

TEST(RefStoreReadHead, OnABranchResolvesNameAndOidInASingleInvocation) {
    FakeProcessRunner runner;
    runner.whenArgsContain({"rev-parse", "--symbolic-full-name"},
                           combinedReply(kOid, "refs/heads/main"));

    RefStore store(runner, testPaths());
    auto head = store.readHead(CancellationToken{});

    ASSERT_TRUE(head);
    EXPECT_EQ(head->kind, HeadInfo::Kind::Branch);
    EXPECT_EQ(head->fullRef, "refs/heads/main");
    EXPECT_EQ(head->branchName, "main");
    EXPECT_EQ(head->target.hex(), kOid);

    EXPECT_EQ(runner.invocationCount(), 1u);
}

TEST(RefStoreReadHead, DetachedIsRecognisedFromTheLiteralHeadSymbolicName) {
    // `--symbolic-full-name HEAD` prints the literal string "HEAD" when HEAD is
    // detached. That is unambiguous rather than merely convenient: a real
    // branch always comes back fully qualified as `refs/heads/...`, so a bare
    // "HEAD" cannot be a branch name reaching this code by accident.
    FakeProcessRunner runner;
    runner.whenArgsContain({"rev-parse", "--symbolic-full-name"}, combinedReply(kOid, "HEAD"));

    RefStore store(runner, testPaths());
    auto head = store.readHead(CancellationToken{});

    ASSERT_TRUE(head);
    EXPECT_EQ(head->kind, HeadInfo::Kind::Detached);
    EXPECT_TRUE(head->branchName.empty());
    EXPECT_EQ(head->target.hex(), kOid);

    EXPECT_EQ(runner.invocationCount(), 1u);
}

TEST(RefStoreReadHead, UnbornFallsBackToSymbolicRefAndKeepsTheBranchName) {
    // A repository with no commits yet is a normal state, not a failure, and
    // the branch HEAD points at is still worth showing. The combined command
    // cannot supply it -- with `--revs-only` an unresolvable HEAD yields empty
    // output -- so this is the one case that still costs a second process.
    // It is also the case most likely to be dropped by a later refactor, hence
    // asserting the name and not just the kind.
    FakeProcessRunner runner;
    runner.whenArgsContain({"rev-parse", "--symbolic-full-name"}, FakeProcessRunner::Response{});
    FakeProcessRunner::Response symbolic;
    symbolic.out = "refs/heads/dev";
    runner.whenArgsContain({"symbolic-ref", "--quiet", "HEAD"}, symbolic);

    RefStore store(runner, testPaths());
    auto head = store.readHead(CancellationToken{});

    ASSERT_TRUE(head);
    EXPECT_EQ(head->kind, HeadInfo::Kind::Unborn);
    EXPECT_EQ(head->fullRef, "refs/heads/dev");
    EXPECT_EQ(head->branchName, "dev");

    EXPECT_EQ(runner.invocationCount(), 2u);
}

TEST(RefStoreReadHead, UsesRevsOnlySoAnUnbornHeadIsNotReportedAsAFatalError) {
    // Without `--revs-only`, `git rev-parse HEAD --symbolic-full-name HEAD`
    // exits 128 and writes "fatal: ambiguous argument 'HEAD'" to stderr on an
    // unborn repository. ProcessRunner records *every* invocation into
    // Log::instance(), stderr included, so that wording would surface in the
    // user's operation log every time a freshly-initialised repository is
    // opened -- describing a normal state as a fatal error. The flag is load
    // bearing, not decoration.
    FakeProcessRunner runner;
    RefStore store(runner, testPaths());
    (void)store.readHead(CancellationToken{});

    ASSERT_GE(runner.invocationCount(), 1u);
    const std::vector<std::string> args = runner.invokedArgs(0);
    EXPECT_NE(std::find(args.begin(), args.end(), "--revs-only"), args.end());
}

TEST(RefStoreReadHead, AFailedRevParsePropagatesAsAFailureRatherThanUnborn) {
    // A rev-parse that errors outright (not a repository, git missing) is a
    // different shape from "ran fine, found no HEAD" -- --revs-only's whole
    // point (see the comment above the command in RefStore.cpp) is that an
    // unborn repo exits 0 with empty output, not a non-zero exit with
    // stderr. Folding this into the Unborn fallback used to leave
    // head.target silently and permanently null on every refresh that hit
    // it, with no diagnostic trail, and made a genuinely failed read look
    // identical to a fresh repository to every caller that only checks
    // `kind`. Session::open() never calls readHead()/load() (only the async
    // refresh path does), so propagating this as a real failure does not
    // block a repository from opening.
    FakeProcessRunner runner;
    FakeProcessRunner::Response failure;
    failure.exitCode = 128;
    failure.err = "fatal: not a git repository";
    runner.setDefaultResponse(failure);

    RefStore store(runner, testPaths());
    auto head = store.readHead(CancellationToken{});

    ASSERT_FALSE(head);
    EXPECT_EQ(head.error().code, GitError::Code::NotFound);

    // No wasted second `symbolic-ref` call on a genuine failure -- that
    // fallback is for the Unborn case only.
    EXPECT_EQ(runner.invocationCount(), 1u);
}

TEST(RefStoreReadHead, ATimedOutRevParsePropagatesAsAFailure) {
    FakeProcessRunner runner;
    FakeProcessRunner::Response failure;
    failure.timedOut = true;
    runner.setDefaultResponse(failure);

    RefStore store(runner, testPaths());
    auto head = store.readHead(CancellationToken{});

    ASSERT_FALSE(head);
    EXPECT_EQ(head.error().code, GitError::Code::Timeout);
    EXPECT_EQ(runner.invocationCount(), 1u);
}

}  // namespace
}  // namespace gbm
